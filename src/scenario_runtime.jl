# Included by measurement workers and ordinary tests. No dependency on PerfChecker.
module SharedScenarioRuntime
using TOML
using Profile

struct ScenarioUnavailable <: Exception
    reason::String
end
Base.showerror(io::IO, error::ScenarioUnavailable) = print(io, error.reason)

struct ScenarioFailure <: Exception
    phase::Symbol
    cause::Any
end
function Base.showerror(io::IO, error::ScenarioFailure)
    (print(io, "scenario ", error.phase, ": "); showerror(io, error.cause))
end

function callback(phase, f, args...)
    try
        return f(args...)
    catch error
        throw(ScenarioFailure(phase, error))
    end
end

function load_case(spec)
    missing = filter(package -> Base.find_package(package) === nothing,
        get(spec, "requirements", String[]))
    isempty(missing) ||
        throw(ScenarioUnavailable("missing scenario dependencies: " * join(missing, ", ")))
    owner = Module(gensym(:SharedCase))
    Base.include(owner, spec["source"])
    factory = owner
    for component in split(spec["factory"], '.')
        factory = Base.invokelatest(getfield, factory, Symbol(component))
    end
    parameters = get(spec, "parameters", Dict{String, Any}())
    case = Base.invokelatest(factory, parameters)
    case isa NamedTuple || error("scenario factory must return a NamedTuple")
    all(name -> hasproperty(case, name), (:prepare, :operation, :verify)) ||
        error("scenario requires prepare, operation and verify functions")
    if hasproperty(case, :availability)
        available = Base.invokelatest(case.availability)
        available isa NamedTuple && hasproperty(available, :available) &&
            hasproperty(available, :reason) ||
            error("availability must return (available=Bool, reason=String)")
        available.available isa Bool || error("availability flag must be Bool")
        available.available || throw(ScenarioUnavailable(string(available.reason)))
    end
    return case
end

mutable struct Evaluation{C, S, R}
    case::C
    state::S
    result::Base.RefValue{R}
    closed::Bool
end
function prepare(case)
    state = callback(:prepare, case.prepare)
    result_type = Core.Compiler.return_type(case.operation, Tuple{typeof(state)})
    result_type === Union{} && (result_type = Any)
    return Evaluation(case, state, Ref{result_type}(), false)
end

function cleanup!(evaluation)
    evaluation.closed && return
    evaluation.closed = true
    hasproperty(evaluation.case, :cleanup) &&
        callback(:cleanup, evaluation.case.cleanup, evaluation.state)
    return nothing
end

function operation!(evaluation)
    try
        result = callback(:operation, evaluation.case.operation, evaluation.state)
        hasproperty(evaluation.case, :synchronize) &&
            callback(:synchronize, evaluation.case.synchronize, evaluation.state, result)
        evaluation.result[] = result
        return result
    catch
        cleanup!(evaluation)
        rethrow()
    end
end

function verify!(evaluation)
    try
        callback(:verify, evaluation.case.verify, evaluation.state, evaluation.result[]) ===
        true ||
            throw(ScenarioFailure(:verify,
                ErrorException("correctness oracle returned a value other than true")))
    finally
        cleanup!(evaluation)
    end
    return nothing
end

function once(case)
    evaluation = prepare(case)
    try
        operation!(evaluation)
        verify!(evaluation)
    finally
        cleanup!(evaluation)
    end
end

function measure_benchmark(
        case, count; raw::Bool = false, seconds::Real = 3600, options = (;))
    if !isdefined(@__MODULE__, :BenchmarkTools)
        tool = Base.require(Main, :BenchmarkTools)
        @eval const BenchmarkTools = $tool
    end
    # Setup/teardown are benchmark hooks, including every warmup and calibration call.
    @eval function benchmark_impl(case, count, seconds, options)
        benchmark = BenchmarkTools.@benchmarkable operation!(evaluation) setup=(evaluation = prepare($case)) teardown=(verify!(evaluation)) evals=1 samples=$count seconds=$seconds
        trial = BenchmarkTools.run(benchmark; warmup = true, options...)
        return trial
    end
    trial = Base.invokelatest(() -> benchmark_impl(case, count, seconds, options))
    raw && return trial
    return [Dict{String, Any}("time" => Float64(t) / 1e9,
                "bytes" => trial.memory, "allocs" => trial.allocs) for t in trial.times]
end

function measure_chairmark(
        case, count; raw::Bool = false, seconds::Real = 3600, gc::Bool = true)
    if !isdefined(@__MODULE__, :Chairmarks)
        tool = Base.require(Main, :Chairmarks)
        @eval const Chairmarks = $tool
    end
    @eval function chairmark_impl(case, count, seconds, gc)
        benchmark = Chairmarks.@be prepare($case) (evaluation->(operation!(evaluation); evaluation)) verify! evals=1 samples=$count seconds=$seconds gc=$gc
        return benchmark
    end
    benchmark = Base.invokelatest(() -> chairmark_impl(case, count, seconds, gc))
    raw && return benchmark
    return [Dict{String, Any}("time" => sample.time, "bytes" => sample.bytes,
                "allocs" => sample.allocs) for sample in benchmark.samples]
end

function profile_case(case, count, allocations)
    once(case)
    Profile.clear()
    allocations && Profile.Allocs.clear()
    for _ in 1:count
        evaluation = prepare(case)
        try
            if allocations
                Profile.Allocs.@profile sample_rate=1.0 operation!(evaluation)
            else
                Profile.@profile operation!(evaluation)
            end
            verify!(evaluation)
        finally
            cleanup!(evaluation)
        end
    end
    sites = Dict{String, Any}[]
    if allocations
        grouped = Dict{Tuple{String, Int}, Int}()
        for allocation in Profile.Allocs.fetch().allocs
            frames = filter(f -> !f.from_c && f.line > 0 && !isempty(string(f.file)),
                allocation.stacktrace)
            isempty(frames) && continue
            # Keep full stacks: allocation internals are not necessarily the user's source site.
            frame = first(frames)
            push!(sites,
                Dict("bytes" => Int(allocation.size), "file" => string(frame.file),
                    "line" => Int(frame.line), "stack" => [Dict("file" => string(f.file),
                                                               "line" => Int(f.line), "function" => string(f.func))
                                                           for f in frames]))
        end
    else
        io = IOBuffer()
        Profile.print(io; format = :flat)
        data, lookup = Profile.retrieve(; include_meta = false)
        grouped = Dict{Tuple, Int}()
        frames = String[]
        function record!()
            isempty(frames) && return
            stack = Tuple(reverse(first(frames, min(length(frames), 128))))
            grouped[stack] = get(grouped, stack, 0) + 1
            empty!(frames)
        end
        for pointer in data
            if pointer == 0
                record!()
            else
                found = get(lookup, pointer, [])
                for frame in (found isa AbstractVector ? found : [found])
                    frame.from_c || frame.line <= 0 || isempty(string(frame.file)) ||
                        push!(frames, "$(frame.func) ($(frame.file):$(frame.line))")
                end
            end
        end
        record!()
        return Dict{String, Any}("profile_text" => String(take!(io)),
            "cpu_stacks" => [Dict("stack" => collect(stack), "value" => count)
                             for (stack, count) in grouped],
            "profile_samples" => sum(values(grouped); init = 0))
    end
    return Dict{String, Any}("allocation_sites" => sites,
        "profile_samples" => length(sites), "sampling_rate" => 1.0)
end

function execute(spec, collector, count)
    case = load_case(spec)
    return Base.invokelatest(execute_loaded, case, collector, count)
end

function execute_loaded(case, collector, count)
    result = Dict{String, Any}("status" => "complete", "correctness" => "passed",
        "collector" => collector, "runtime" => Dict("language" => "julia",
            "version" => string(VERSION), "threads" => Threads.nthreads()))
    if collector == "benchmark"
        result["samples"] = measure_benchmark(case, count)
        result["collector_version"] = Base.invokelatest(() -> string(Base.pkgversion(BenchmarkTools)))
    elseif collector == "chairmark"
        result["samples"] = measure_chairmark(case, count)
        result["collector_version"] = Base.invokelatest(() -> string(Base.pkgversion(Chairmarks)))
    else
        merge!(result, profile_case(case, count, collector == "profile_alloc"))
    end
    return result
end
end
