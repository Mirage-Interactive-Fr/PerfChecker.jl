const DIAGNOSIS_SCHEMA = "perfchecker-diagnosis/1"
const _SCENARIO_ANALYZERS = Dict(:jet => "JET", :aqua => "Aqua",
    :alloccheck => "AllocCheck", :snoopcompile => "SnoopCompile", :latency => "builtin",
    :gc => "builtin", :memory => "builtin", :heap => "builtin", :locks => "builtin")

"""
    diagnostic_capabilities() -> Vector{Dict}

Describe each supported scenario analyzer's name, package, evidence scope,
compatible package versions and installation scope. The catalogue includes JET,
Aqua, AllocCheck, SnoopCompile and built-in latency, GC, memory, heap and lock
diagnostics. Reading it neither imports those packages nor executes target code.

Catalogue presence is not availability or a passing diagnosis. Analyzer packages
must exist in the selected worker environment; heap snapshots need a report
directory and lock contention needs Julia 1.11 or newer. Consult each record's
scope, then inspect the actual [`diagnose`](@ref) result for that configuration.
"""
function diagnostic_capabilities()
    catalog = TOML.parsefile(joinpath(@__DIR__, "..", "providers", "catalog.toml"))
    scopes = Dict(:jet => "operation inference", :aqua => "package quality",
        :alloccheck => "operation static allocations", :snoopcompile => "first lifecycle inference",
        :latency => "source load and first lifecycle latency",
        :gc => "operation GC time, allocation pressure and collection counts",
        :memory => "reachable state/result size and process memory observations",
        :heap => "redacted heap snapshot after verification; requires a report directory",
        :locks => "operation lock contention; Julia 1.11 or newer")
    [Dict("tool" => string(tool), "package" => package, "scope" => scopes[tool],
         "compatible_versions" => package == "builtin" ? "Julia 1.10 or newer" :
                                  catalog[package]["compat"],
         "installation" => package == "builtin" ? "builtin" : "checked_in_worker",
         "installation_scope" => "selected worker environment only; controller dependencies do not determine availability",
         "qualification" => "not_checked")
     for (tool, package) in sort!(collect(_SCENARIO_ANALYZERS); by = first)]
end
_scenario_capabilities() = diagnostic_capabilities()

include("scenario_runtime.jl")
include("diagnostic_runtime.jl")
include("memory_diagnostics.jl")

"""
    diagnose(catalog::ScenarioCatalog; project=catalog.root,
             tools=[:jet, :aqua, :alloccheck, :snoopcompile, :latency],
             timeout=120, threads=1, cancellation=CancellationToken(),
             options=Dict(), reports=nothing) -> Dict{String, Any}

Run the selected optional analyzers in separate bounded Julia workers. Each
non-Aqua analyzer operates on each declared scenario; Aqua runs once for the
package identified by the catalog root's `Project.toml`. Reject unknown tool
names. Required packages must already exist in `project`; a missing dependency
produces unavailable evidence rather than installing it or passing the check.

`timeout` bounds each worker including startup and `threads` sets its Julia thread
count. `options` supplies analyzer-specific data; `reports` supplies artifact
paths, notably for the redacted heap snapshot. Source/fixture and environment
fingerprints invalidate results if those inputs change during analysis.

Return `perfchecker-diagnosis/1` with `source_provenance` and a `records` array.
Each record carries its tool, scenario/implementation, configuration, input
fingerprints, summary and outcome. Execution `status`, `correctness`, `quality`
and `performance` answer different questions: a completed Aqua analysis can
report failed package quality without verifying a scenario's correctness.
Cancellation stops further jobs after the current worker's final cleanup.

```julia
catalog = load_scenario_catalog("perf/scenarios.toml")
report = diagnose(catalog; project=".", tools=[:jet, :latency], timeout=120)
[(r["tool"], r["status"]) for r in report["records"]]
```
"""
function diagnose(catalog::ScenarioCatalog; project::AbstractString = catalog.root,
        tools = [:jet, :aqua, :alloccheck, :snoopcompile, :latency],
        timeout::Real = 120, threads::Integer = 1,
        cancellation::CancellationToken = CancellationToken(), options::AbstractDict = Dict(),
        reports = nothing)
    selected = unique(Symbol.(collect(tools)))
    all(t -> haskey(_SCENARIO_ANALYZERS, t), selected) ||
        throw(ArgumentError("unknown analyzer"))
    records = Dict{String, Any}[]
    package_file = joinpath(catalog.root, "Project.toml")
    package = isfile(package_file) ? get(TOML.parsefile(package_file), "name", "") : ""
    jobs = Tuple{Symbol, Union{Nothing, ScenarioSpec}}[
                                                       (tool, spec)
                                                       for spec in catalog.scenarios
                                                       for tool in selected
                                                       if tool != :aqua]
    :aqua in selected && pushfirst!(jobs, (:aqua, nothing))
    for (tool, spec) in jobs
        opts = Dict{String, Any}(string(k) => v for (k, v) in pairs(options))
        opts["package"] = package
        if tool == :heap && reports !== nothing
            opts["artifact_dir"] = joinpath(abspath(reports), "artifacts", string(uuid4()))
        end
        request = Dict{String, Any}("tool" => string(tool), "options" => opts)
        spec === nothing || (request["scenario"] = _scenario_dict(spec))
        before = spec === nothing ? Dict() : _scenario_fingerprints(spec)
        environment_before = _environment_provenance(project)
        raw = _scenario_process(
            request; project, timeout, cancellation, diagnostic = true, threads)
        if spec !== nothing && before != _scenario_fingerprints(spec)
            raw["status"] = "invalid"
            raw["message"] = "scenario source or fixture changed during analysis"
        end
        raw["tool"] = string(tool)
        raw["scenario"] = spec === nothing ? "package" : spec.id
        raw["implementation"] = spec === nothing ? "package" : spec.implementation
        raw["source"] = spec === nothing ? catalog.root : spec.source
        raw["configuration"] = Dict(
            "project" => abspath(project), "os" => string(Sys.KERNEL),
            "arch" => string(Sys.ARCH), "threads" => threads)
        environment_after = _environment_provenance(project)
        raw["environment_provenance"] = environment_before
        if environment_before != environment_after
            raw["status"] = "invalid"
            raw["message"] = "worker environment or development dependency source changed during analysis"
            raw["environment_after"] = environment_after
        end
        raw["input_fingerprints"] = before
        raw["summary"] = _diagnostic_summary(raw)
        push!(records, raw)
        cancellation.requested[] && break
    end
    return Dict{String, Any}("schema_version" => DIAGNOSIS_SCHEMA,
        "source_provenance" => _git_provenance(catalog.root), "records" => records)
end
