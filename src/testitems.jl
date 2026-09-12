"""
    testitem_filter(mode=:performance; tags=[], exclude_tags=[])

Build a TestItemRunner filter. Untagged items are shared. `:test_only` excludes
performance execution; `:perf_only` excludes functional execution. Contradictory
tags are rejected. A nonempty tag selection matches any requested tag.
Use `@run_package_tests filter=testitem_filter(:test)` in functional CI.
Loading PerfChecker never changes TestItemRunner's default behavior.
"""
function testitem_filter(
        mode::Symbol = :performance; tags = Symbol[], exclude_tags = Symbol[])
    mode in (:test, :performance, :all) ||
        throw(ArgumentError("mode must be test, performance or all"))
    wanted, excluded = Set(Symbol.(tags)), Set(Symbol.(exclude_tags))
    return function (item)
        itemtags = Set(Symbol.(item.tags))
        :perf_only in itemtags && :test_only in itemtags &&
            throw(ArgumentError("$(item.name) has conflicting perf_only/test_only tags"))
        mode == :test && :perf_only in itemtags && return false
        mode == :performance && :test_only in itemtags && return false
        isempty(intersect(itemtags, excluded)) || return false
        isempty(wanted) || !isempty(intersect(itemtags, wanted))
    end
end

"""
    discover_testitems(root=pwd(); mode=:performance, tags=[], exclude_tags=[])

List existing `@testitem` declarations without executing their bodies, setup
modules, or surrounding source code. Load `TestItemRunner` to enable this method.

`mode=:performance` includes ordinary items and `:perf_only`, but excludes
`:test_only`. `mode=:test` does the converse; `:all` keeps both categories.
`tags` matches any requested tag; `exclude_tags` always removes matching items.
An item carrying both reserved tags is rejected.

Return a dictionary with schema `perfchecker-testitems/1`, normalized root,
selection mode, `executed=false`, and an `items` array. Each item contains its
stable ID, name, relative file, tags and source SHA-256. IDs identify the file/name
pair; renaming either changes the ID. Duplicate names in one file are rejected.

Discovery writes no report and launches no measured workload. Missing directories,
invalid declarations and ambiguous identities raise an error rather than silently
producing a partial listing. See [`run_testitems`](@ref) to execute a selection.
"""
function discover_testitems end

"""
    run_testitems(root=pwd(); ids=nothing, tags=[], exclude_tags=[],
                  project=dirname(Base.active_project()), samples=1,
                  timeout=120, threads=1, reports=nothing,
                  cancellation=CancellationToken())

Execute a selection from [`discover_testitems`](@ref) with the official
TestItemRunner lifecycle. Load `TestItemRunner` before calling. Prepare `project`
with the target's test dependencies first; running does not install packages.

`ids=nothing` selects every item admitted by the performance/tag filters. Explicit
IDs must be unique and known. Empty selections and nonpositive sample counts are
errors. Each sample runs in a fresh process with the requested Julia threads and
timeout. There is no implicit warmup or repetition.

The measured scope includes item setup, imports, assertions and module cleanup.
It is suitable for checking the cost of an existing test; it does not isolate an
inner operation. Use a feature workload when that narrower scope is required.

Return a `perfchecker-testitem-run/1` dictionary with item/sample records and a
functional `passed` flag. `performance=not_compared` means no regression budget
was evaluated; functional success is not a performance verdict. Source or
environment changes during a sample invalidate its evidence. Failures, timeouts
and cancellation remain visible in the result.

If `reports` is supplied, write the report into that directory without replacing
an existing `testitems.json`. Cancellation stops the current worker and prevents
further selected items from running. See [`testitem_filter`](@ref) for reserved tags.
"""
function run_testitems end

"Register an Oxygen UI for existing TestItemRunner items. Load PerfCheckerWeb; bind the server to loopback or supply external authentication."
function register_testitem_routes! end
