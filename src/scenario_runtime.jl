# Included by measurement workers and ordinary tests. No dependency on PerfChecker.
module SharedScenarioRuntime
using TOML
using Profile
include("profile_runtime.jl")

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

"""
    PendingScenarioCleanup

A live-scenario failure retaining exception-owned resources whose cleanup has
not completed. `close(error)` retries every pending owner, retains failures for
diagnosis, and clears owners only after their `isopen` reports false. Preserve
this structured error and stop the live campaign until cleanup succeeds.
"""
mutable struct PendingScenarioCleanup <: Exception
    original::Any
    owners::Vector{Any}
    failures::Vector{CapturedException}
    retry_failures::Vector{CapturedException}
end
function _owner_isopen(owner)
    try
        value = isopen(owner)
        return value isa Bool ? value : true
    catch
        return true
    end
end
Base.isopen(error::PendingScenarioCleanup) = any(_owner_isopen, error.owners)
function Base.showerror(io::IO, error::PendingScenarioCleanup)
    print(io, isopen(error) ? "scenario cleanup remains pending; close(error) retries: " :
        "scenario cleanup recovered; original failure: ")
    showerror(io, error.original)
    for failure in (error.failures..., error.retry_failures...)
        print(io, "; cleanup: ")
        showerror(io, failure.ex)
    end
end
function _owned_exception_owners(error)
    owners, stack = Any[], Any[error]
    seen = IdDict{Any, Nothing}()
    while !isempty(stack)
        value = pop!(stack)
        haskey(seen, value) && continue
        seen[value] = nothing
        if value isa Exception && applicable(close, value) && applicable(isopen, value)
            push!(owners, value)
        elseif value isa ScenarioFailure
            push!(stack, value.cause)
        elseif value isa CapturedException
            push!(stack, value.ex)
        elseif value isa CompositeException
            append!(stack, reverse(value.exceptions))
        end
    end
    return owners
end
function _recover_owners(owners; retry_pending = false)
    pending, failures = Any[], CapturedException[]
    attempted, released = 0, 0
    blocked = false
    for owner in owners
        _owner_isopen(owner) || continue
        if blocked
            push!(pending, owner)
            continue
        end
        if owner isa PendingScenarioCleanup && !retry_pending
            # An inner boundary already attempted recovery. Do not silently
            # add another automatic retry while unwinding a live campaign.
            push!(pending, owner)
            blocked = true
            continue
        end
        attempted += 1
        try
            close(owner)
        catch error
            push!(failures, CapturedException(error, catch_backtrace()))
        end
        if _owner_isopen(owner)
            push!(pending, owner)
            blocked = true
        else
            released += 1
        end
    end
    return (; pending, failures, attempted, released)
end
function Base.close(error::PendingScenarioCleanup)
    result = _recover_owners(error.owners; retry_pending = true)
    error.owners = result.pending
    error.retry_failures = result.failures
    isempty(error.owners) || throw(error)
    return nothing
end
function recover_exception!(error)
    error isa PendingScenarioCleanup && isopen(error) && throw(error)
    result = _recover_owners(_owned_exception_owners(error))
    isempty(result.pending) || throw(PendingScenarioCleanup(error, result.pending,
        result.failures, CapturedException[]))
    return (; attempted = result.attempted, released = result.released, pending = 0,
        cleanup_errors = Tuple(sprint(showerror, failure.ex) for failure in result.failures))
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
    pending_cleanup::Any
end
function prepare(case)
    state = callback(:prepare, case.prepare)
    result_type = Core.Compiler.return_type(case.operation, Tuple{typeof(state)})
    result_type === Union{} && (result_type = Any)
    return Evaluation(case, state, Ref{result_type}(), false, nothing)
end

function _cleanup_raw!(evaluation)
    evaluation.closed && return
    hasproperty(evaluation.case, :cleanup) &&
        callback(:cleanup, evaluation.case.cleanup, evaluation.state)
    evaluation.closed = true
    return nothing
end

mutable struct EvaluationCleanupOwner{E} <: Exception
    evaluation::Union{Nothing, E}
    primary::Union{Nothing, CapturedException}
    cleanup::Union{Nothing, CapturedException}
    dependency::Any

    function EvaluationCleanupOwner{E}(evaluation, primary, cleanup, dependency) where {E}
        return new{E}(evaluation, primary, cleanup, dependency)
    end
end
Base.isopen(owner::EvaluationCleanupOwner) = owner.evaluation !== nothing
function Base.showerror(io::IO, owner::EvaluationCleanupOwner)
    print(io, "scenario state cleanup is retained")
    for captured in (owner.primary, owner.cleanup)
        captured === nothing && continue
        print(io, "; ")
        showerror(io, captured.ex)
    end
end
function Base.close(owner::EvaluationCleanupOwner)
    evaluation = owner.evaluation
    evaluation === nothing && return nothing
    # A dependent owned failure must be quiescent before its parent case state
    # (which can be a world/runner) is allowed to close.
    if owner.dependency !== nothing
        close(owner.dependency)
        owner.dependency = nothing
    end
    for captured in (owner.primary, owner.cleanup)
        captured === nothing && continue
        try
            recover_exception!(captured.ex)
        catch pending
            pending isa PendingScenarioCleanup && (owner.dependency = pending)
            rethrow()
        end
    end
    try
        _cleanup_raw!(evaluation)
    catch cleanup
        owner.cleanup = CapturedException(cleanup, catch_backtrace())
        rethrow()
    end
    evaluation.pending_cleanup = nothing
    owner.evaluation = nothing
    return nothing
end
function _pending_evaluation!(evaluation, primary, cleanup, dependency)
    owner = EvaluationCleanupOwner{typeof(evaluation)}(evaluation, primary, cleanup, dependency)
    failures = cleanup === nothing ? CapturedException[] : CapturedException[cleanup]
    pending = PendingScenarioCleanup(owner, Any[owner], failures, CapturedException[])
    evaluation.pending_cleanup = pending
    throw(pending)
end
function cleanup!(evaluation)
    evaluation.closed && return nothing
    evaluation.pending_cleanup === nothing || throw(evaluation.pending_cleanup)
    try
        _cleanup_raw!(evaluation)
    catch cleanup
        _pending_evaluation!(evaluation, nothing, CapturedException(cleanup, catch_backtrace()), nothing)
    end
    return nothing
end
function _cleanup_after_failure!(evaluation, primary, trace)
    evaluation.pending_cleanup === nothing || throw(evaluation.pending_cleanup)
    captured = CapturedException(primary, trace)
    try
        recover_exception!(primary)
    catch dependency
        if dependency isa PendingScenarioCleanup
            _pending_evaluation!(evaluation, captured, nothing, dependency)
        else
            _pending_evaluation!(evaluation, captured, CapturedException(dependency, catch_backtrace()), nothing)
        end
    end
    try
        _cleanup_raw!(evaluation)
    catch cleanup
        _pending_evaluation!(evaluation, captured, CapturedException(cleanup, catch_backtrace()), nothing)
    end
    return nothing
end
function operation!(evaluation)
    try
        result = callback(:operation, evaluation.case.operation, evaluation.state)
        hasproperty(evaluation.case, :synchronize) &&
            callback(:synchronize, evaluation.case.synchronize, evaluation.state, result)
        evaluation.result[] = result
        return result
    catch primary
        _cleanup_after_failure!(evaluation, primary, catch_backtrace())
        rethrow()
    end
end

function verify!(evaluation)
    evaluation.pending_cleanup === nothing || throw(evaluation.pending_cleanup)
    try
        callback(:verify, evaluation.case.verify, evaluation.state, evaluation.result[]) ===
        true ||
            throw(ScenarioFailure(:verify,
                ErrorException("correctness oracle returned a value other than true")))
    catch primary
        _cleanup_after_failure!(evaluation, primary, catch_backtrace())
        rethrow()
    end
    cleanup!(evaluation)
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
    total_bytes = 0
    total_allocations = 0
    if allocations
        evaluation = prepare(case)
        try
            total_bytes = Base.@allocated operation!(evaluation)
            verify!(evaluation)
        finally
            cleanup!(evaluation)
        end
        evaluation = prepare(case)
        try
            total_allocations = Base.@allocations operation!(evaluation)
            verify!(evaluation)
        finally
            cleanup!(evaluation)
        end
    end
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
        captured = Profile.Allocs.fetch().allocs
        for allocation in captured
            frames = filter(
                f -> !f.from_c && f.line > 0 &&
                         PerfCheckerProfileRuntime.usable_source(string(f.file)),
                allocation.stacktrace)
            isempty(frames) && continue
            # Keep full stacks: allocation internals are not necessarily the user's source site.
            frame = first(frames)
            push!(sites,
                Dict("bytes" => Int64(allocation.size), "file" => string(frame.file),
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
    summary = PerfCheckerProfileRuntime.allocation_summary(
        total_bytes = total_bytes, total_allocations = total_allocations,
        sampled_allocations = length(captured), source_allocations = length(sites),
        retained_allocations = length(sites),
        retained_bytes = sum(site["bytes"] for site in sites; init = Int64(0)),
        sample_rate = 1.0, profile_evaluations = count,
        weight_semantics = "raw sampled bytes and events across all profile evaluations")
    return Dict{String, Any}("allocation_sites" => sites,
        "profile_samples" => length(sites), "sampling_rate" => 1.0,
        "allocation_profile" => summary)
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
