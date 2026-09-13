const DIAGNOSIS_SCHEMA = "perfchecker-diagnosis/1"
const _SCENARIO_ANALYZERS = Dict(:jet => "JET", :aqua => "Aqua",
    :alloccheck => "AllocCheck", :snoopcompile => "SnoopCompile", :latency => "builtin",
    :gc => "builtin", :memory => "builtin", :heap => "builtin", :locks => "builtin")

"Describe executable diagnostic tools without loading packages or executing target code."
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

"Run optional analyzers in separate bounded processes. Reports never install missing packages."
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
