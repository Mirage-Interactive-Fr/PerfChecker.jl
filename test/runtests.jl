using TestItemRunner
using Test, Dates

# TestItemRunner 1.3.2 calls this factory for package/file/item testsets.
# END records finalization, not a pass: failures and interruptions still propagate.
struct ProgressTestSet <: Test.AbstractTestSet
    inner::Test.DefaultTestSet
    started::UInt64
    label::String
    results::Vector{Any} # Preserve TestItemRunner's optional failfast inspection.
end

function ProgressTestSet(description::AbstractString; verbose = false, kwargs...)
    parent = Test.get_testset()
    label = parent isa ProgressTestSet ? parent.label * " / " * description :
            String(description)
    inner = Test.DefaultTestSet(description; verbose, kwargs...)
    testset = ProgressTestSet(inner, time_ns(), label, inner.results)
    println(stderr, "BEGIN ", Dates.now(Dates.UTC), "Z ", repr(label))
    flush(stderr)
    return testset
end

function Test.record(testset::ProgressTestSet,
        result::Union{Test.Result, Test.AbstractTestSet})
    Test.record(testset.inner, result isa ProgressTestSet ? result.inner : result)
end

function Test.finish(testset::ProgressTestSet)
    try
        Test.finish(testset.inner)
    finally
        elapsed = (time_ns() - testset.started) / 1e9
        println(stderr, "END ", Dates.now(Dates.UTC), "Z ", repr(testset.label),
            " elapsed=", round(elapsed; digits = 3), "s")
        flush(stderr)
    end
    return testset
end

profile = get(ENV, "PERFCHECKER_TEST_PROFILE", "full")
selected_tags = Set(Symbol.(filter(!isempty,
    split(get(ENV, "PERFCHECKER_TEST_TAGS", ""), ','))))
isolated_tags = Set([:oxygen_latest, :wgl])

function selected_testitem(testitem)
    relative = relpath(testitem.filename, dirname(@__DIR__))
    first(splitpath(relative)) in ("src", "ext", "test") || return false
    tags = Set(testitem.tags)
    isempty(selected_tags) && return isempty(isolated_tags ∩ tags)
    requested_isolated = selected_tags ∩ isolated_tags
    if isempty(requested_isolated)
        return isempty(isolated_tags ∩ tags) && !isempty(selected_tags ∩ tags)
    end
    return !isempty(requested_isolated ∩ tags)
end

@run_package_tests(testset=ProgressTestSet,
    filter=ti -> (
        (profile == "full" || :historical ∉ ti.tags) &&
        selected_testitem(ti)))
