# Standalone worker: do not import PerfChecker into the measured process.
using TestItemRunner, Test, TOML, SHA

mutable struct MeasuredTestSet <: Test.AbstractTestSet
    inner::Test.DefaultTestSet
    started::UInt64
    allocated::Int
    depth::Int
    instrumented::Bool
    records::Vector{Any}
end
function MeasuredTestSet(description::AbstractString; verbose = false, kwargs...)
    parent = Test.get_testset()
    sink = parent isa MeasuredTestSet ? parent.records : Any[]
    MeasuredTestSet(Test.DefaultTestSet(description; verbose, kwargs...), time_ns(),
        Base.gc_bytes(), Test.get_testset_depth(), false, sink)
end
function Test.record(ts::MeasuredTestSet, result::Union{Test.Result, Test.AbstractTestSet})
    Test.record(ts.inner, result)
end
function Test.finish(ts::MeasuredTestSet)
    seconds = (time_ns() - ts.started) / 1e9
    bytes = Base.gc_bytes() - ts.allocated
    if ts.instrumented
        push!(ts.records,
            (name = ts.inner.description, depth = ts.depth,
                seconds, bytes, inner = ts.inner))
    end
    Test.finish(ts.inner)
    ts
end

function counts(ts::Test.DefaultTestSet)
    passes = ts.n_passed
    failures = errors = broken = 0
    for result in ts.results
        if result isa Test.DefaultTestSet
            nested = counts(result)
            passes += nested.passes
            failures += nested.failures
            errors += nested.errors
            broken += nested.broken
        elseif result isa Test.Fail
            failures += 1
        elseif result isa Test.Error
            errors += 1
        elseif result isa Test.Broken
            broken += 1
        end
    end
    (; passes, failures, errors, broken)
end

function main(input, output)
    request = TOML.parsefile(input)
    records = Any[]
    result = Dict{String, Any}("status" => "error", "correctness" => "not_checked")
    try
        bytes2hex(sha256(read(request["filename"]))) == request["source_sha256"] ||
            error("test item source changed after discovery")
        selected = Ref(0)
        failure = nothing
        try
            TestItemRunner.run_tests(request["root"];
                filter = item -> begin
                    match = normpath(item.filename) == normpath(request["filename"]) &&
                            item.name == request["name"]
                    match && (selected[] += 1)
                    match
                end,
                testset = (name; verbose = false) -> MeasuredTestSet(
                    Test.DefaultTestSet(name; verbose), time_ns(), Base.gc_bytes(),
                    Test.get_testset_depth(), true, records))
        catch error
            failure = error
        end
        selected[] == 1 || error("expected exactly one native test item")
        candidates = filter(r -> r.name == request["name"], records)
        isempty(candidates) && error("runner did not produce item timing")
        measured = candidates[argmax([r.depth for r in candidates])]
        tally = counts(measured.inner)
        passed = failure === nothing &&
                 tally.failures == tally.errors == tally.broken == 0 && tally.passes > 0
        merge!(result,
            Dict("status" => "complete", "correctness" => passed ? "passed" : "not_passed",
                "seconds" => measured.seconds, "bytes" => measured.bytes,
                "passes" => tally.passes, "failures" => tally.failures, "errors" => tally.errors,
                "broken" => tally.broken, "julia_version" => string(VERSION),
                "runner_version" => string(Base.pkgversion(TestItemRunner)),
                "source_sha256" => request["source_sha256"]))
        failure === nothing || (result["message"] = first(sprint(showerror, failure), 4096))
    catch error
        result["message"] = first(sprint(showerror, error), 4096)
    end
    open(io -> TOML.print(io, result), output, "w")
end
main(ARGS...)
