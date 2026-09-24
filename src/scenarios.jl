const SCENARIO_CATALOG_SCHEMA = "perfchecker-scenario-catalog/1"

# Legacy FeatureSpec suites use the same lifecycle for their timing collectors.
# The worker imports only this standalone runtime and the selected timing package.
function _fresh_feature_setup(options)
    runtime = joinpath(@__DIR__, "scenario_runtime.jl")
    oracle = get(options, :feature_oracle, "")
    oracle_required = get(options, :feature_oracle_required, true)
    return quote
        isdefined(Main, :SharedScenarioRuntime) || include($runtime)
        _perfchecker_shared_case = let
            oracle_name = Symbol($oracle)
            case = (
                prepare = () -> isdefined(Main, :perf_setup) ? Main.perf_setup() : nothing,
                operation = state -> Main.perf_workload(state),
                synchronize = (state, result) -> isdefined(Main, :perf_synchronize) ?
                                                 Main.perf_synchronize(state, result) :
                                                 nothing,
                verify = (state, result) -> if isempty($oracle) || (!$oracle_required &&
                                                !isdefined(Main, oracle_name))
                    true
                else
                    oracle = getfield(Main, oracle_name)
                    value = applicable(oracle, state, result) ? oracle(state, result) :
                            applicable(oracle, state) ? oracle(state) : oracle()
                    if value isa NamedTuple || value isa AbstractDict
                        evidence = Dict(string(k) => v for (k, v) in pairs(value))
                        lowercase(string(get(evidence, "status", "passed"))) in (
                            "pass", "passed", "valid", "available", "supported", "ok")
                    else
                        value === true || value === nothing || value isa AbstractString
                    end
                end,
                cleanup = state -> isdefined(Main, :perf_cleanup) ?
                                   Main.perf_cleanup(state) : nothing)
            case
        end
    end
end

function _fresh_feature_expression(options, collector)
    setup = _fresh_feature_setup(options)
    count = something(get(options, :samples, 10), 10)
    seconds = something(get(options, :seconds, 5), 5)
    benchmark_options = (;
        (k => options[k] for k in (:overhead, :gctrial, :gcsample,
                                 :time_tolerance, :memory_tolerance) if haskey(options, k))...)
    gc = get(options, :gc, true)
    return quote
        $setup
        if $(collector == :benchmark)
            Base.invokelatest(
                SharedScenarioRuntime.measure_benchmark, _perfchecker_shared_case, $count;
                raw = true, seconds = $seconds, options = $benchmark_options)
        else
            Base.invokelatest(
                SharedScenarioRuntime.measure_chairmark, _perfchecker_shared_case, $count;
                raw = true, seconds = $seconds, gc = $gc)
        end
    end
end

function _fresh_profile_evaluation(instrumented::Expr)
    return quote
        let _perfchecker_evaluation = SharedScenarioRuntime.prepare(_perfchecker_shared_case)
            try
                _perfchecker_observation = $instrumented
                SharedScenarioRuntime.verify!(_perfchecker_evaluation)
                _perfchecker_observation
            finally
                SharedScenarioRuntime.cleanup!(_perfchecker_evaluation)
            end
        end
    end
end

"A shared, dependency-free Julia factory, identified independently of its measurement collector."
struct ScenarioSpec
    id::String
    source::String
    factory::String
    implementation::String
    parameters::Dict{String, Any}
    fixtures::Vector{String}
    collectors::Vector{Symbol}
    repeatable::Bool
    requirements::Vector{String}
end

function ScenarioSpec(id::String, source::String, factory::String, implementation::String,
        parameters::Dict{String, Any}, fixtures::Vector{String},
        collectors::Vector{Symbol}, repeatable::Bool)
    ScenarioSpec(id, source, factory, implementation, parameters,
        fixtures, collectors, repeatable, String[])
end

function ScenarioSpec(id::AbstractString; source::AbstractString,
        factory::AbstractString = "make_case", implementation::AbstractString = "default",
        parameters::AbstractDict = Dict(), fixtures = String[],
        collectors = [:benchmark], repeatable::Bool = false, requirements = String[])
    isempty(id) && throw(ArgumentError("scenario id must not be empty"))
    isempty(implementation) && throw(ArgumentError("implementation must not be empty"))
    all(part -> occursin(r"^[A-Za-z_][A-Za-z_0-9!]*$", part), split(factory, '.')) ||
        throw(ArgumentError("factory must be a dotted Julia identifier"))
    isfile(source) || throw(ArgumentError("scenario source does not exist: $source"))
    selected = Symbol.(collect(collectors))
    !isempty(selected) &&
        all(c -> c in (:benchmark, :chairmark, :profile, :profile_alloc), selected) ||
        throw(ArgumentError("unsupported or empty scenario collectors"))
    all(isfile, fixtures) || throw(ArgumentError("scenario fixture does not exist"))
    params = Dict{String, Any}(string(k) => v for (k, v) in pairs(parameters))
    # This is also the process-boundary validation: no executable expressions or closures.
    TOML.print(IOBuffer(), Dict("parameters" => params))
    return ScenarioSpec(
        String(id), abspath(source), String(factory), String(implementation),
        params, abspath.(String.(fixtures)), unique(selected), repeatable, String.(requirements))
end

"The explicit catalog used by both local execution and CI. Inferred candidates are never members."
struct ScenarioCatalog
    root::String
    scenarios::Vector{ScenarioSpec}
    function ScenarioCatalog(root::String, scenarios::Vector{ScenarioSpec})
        allunique((s.id, s.implementation) for s in scenarios) ||
            throw(ArgumentError("duplicate scenario/implementation identity"))
        new(abspath(root), copy(scenarios))
    end
end

function ScenarioCatalog(root::AbstractString, scenarios::AbstractVector{ScenarioSpec})
    keys = [(s.id, s.implementation) for s in scenarios]
    allunique(keys) || throw(ArgumentError("duplicate scenario/implementation identity"))
    return ScenarioCatalog(abspath(root), collect(scenarios))
end

function _scenario_dict(spec::ScenarioSpec)
    Dict{String, Any}("id" => spec.id, "source" => spec.source,
        "factory" => spec.factory, "implementation" => spec.implementation,
        "parameters" => spec.parameters, "fixtures" => spec.fixtures,
        "collectors" => string.(spec.collectors), "repeatable" => spec.repeatable, "requirements" => spec.requirements)
end

"Return the portable representation of an explicit scenario catalog."
scenario_catalog_dict(catalog::ScenarioCatalog) = Dict{String, Any}(
    "schema_version" => SCENARIO_CATALOG_SCHEMA, "root" => catalog.root,
    "scenarios" => _scenario_dict.(catalog.scenarios))

"Read a TOML catalog without evaluating package or test code. Paths are relative to the catalog."
function load_scenario_catalog(path::AbstractString)
    payload = TOML.parsefile(path)
    get(payload, "schema_version", "") == SCENARIO_CATALOG_SCHEMA ||
        throw(ArgumentError("unsupported scenario catalog schema"))
    base = dirname(abspath(path))
    root = normpath(joinpath(base, get(payload, "root", ".")))
    cases = ScenarioSpec[]
    for item in get(payload, "scenarios", Any[])
        push!(cases,
            ScenarioSpec(item["id"];
                source = normpath(joinpath(base, item["source"])),
                factory = get(item, "factory", "make_case"),
                implementation = get(item, "implementation", "default"),
                parameters = get(item, "parameters", Dict()),
                fixtures = [normpath(joinpath(base, f))
                            for f in get(item, "fixtures", String[])],
                collectors = Symbol.(get(item, "collectors", ["benchmark"])),
                repeatable = get(item, "repeatable", false), requirements = get(
                    item, "requirements", String[])))
    end
    return ScenarioCatalog(root, cases)
end

"Thread-safe cancellation request, checked while an isolated child is running."
mutable struct CancellationToken
    requested::Threads.Atomic{Bool}
end
CancellationToken() = CancellationToken(Threads.Atomic{Bool}(false))
"Request cancellation of scenario measurements or diagnostics."
cancel!(token::CancellationToken) = (token.requested[] = true; nothing)

function _scenario_fingerprints(spec::ScenarioSpec)
    Dict{String, Any}(path => isfile(path) ? _sha256_file(path) : "missing"
    for path in [spec.source; spec.fixtures])
end

"Select exact scenario/implementation pairs; inferred or unknown identities are rejected."
function select_scenarios(catalog::ScenarioCatalog, selection::AbstractVector)
    requested = [(String(item["id"]), String(item["implementation"])) for item in selection]
    allunique(requested) || throw(ArgumentError("duplicate scenario selection"))
    available = Dict((spec.id, spec.implementation) => spec for spec in catalog.scenarios)
    all(key -> haskey(available, key), requested) ||
        throw(ArgumentError("unknown scenario selection"))
    return ScenarioCatalog(catalog.root, [available[key] for key in requested])
end

"Read shared-scenario bundles from one measurement directory without modifying them."
function read_scenario_runs(directory::AbstractString)
    isdir(directory) || throw(ArgumentError("scenario report directory does not exist"))
    paths = isfile(joinpath(directory, "manifest.json")) ? [String(directory)] :
            filter(
        path -> isfile(joinpath(path, "manifest.json")), readdir(directory; join = true))
    bundles = filter(bundle -> haskey(bundle.manifest, "scenario"), read_run_bundle.(paths))
    isempty(bundles) && throw(ArgumentError("no shared scenario bundles found"))
    return bundles
end

function _stop_scenario_worker(process)
    process_running(process) || return
    if Sys.iswindows()
        stopped = run(pipeline(ignorestatus(`taskkill /PID $(getpid(process)) /T /F`);
            stdout = devnull, stderr = devnull))
        # libuv may not have observed exit yet after taskkill completed successfully.
        # A second TerminateProcess on that handle can fail with EACCES.
        success(stopped) && return
    else
        # The worker owns its process group (detach=true); never signal the controller's group.
        ccall(:kill, Cint, (Cint, Cint), -getpid(process), 9)
    end
    if process_running(process)
        try
            kill(process)
        catch error
            # Ignore only an observed concurrent exit; retain genuine stop failures.
            timedwait(() -> process_exited(process), 1; pollint = 0.01) == :ok ||
                rethrow(error)
        end
    end
end

function _scenario_process(request::AbstractDict; project::AbstractString,
        timeout::Real, cancellation::CancellationToken, diagnostic::Bool = false,
        threads::Integer = 1, advisor::Bool = false, testitems::Bool = false)
    timeout > 0 && isfinite(timeout) ||
        throw(ArgumentError("timeout must be finite and positive"))
    threads > 0 || throw(ArgumentError("threads must be positive"))
    isfile(joinpath(project, "Project.toml")) ||
        throw(ArgumentError("worker project does not exist"))
    cancellation.requested[] && return Dict{String, Any}("status" => "cancelled")
    return mktempdir() do directory
        input, output = joinpath(directory, "request.toml"),
        joinpath(directory, "response.toml")
        open(io -> TOML.print(io, request), input, "w")
        worker = joinpath(
            @__DIR__, testitems ? "testitem_worker.jl" :
                      advisor ? "advisor_worker.jl" :
                      diagnostic ? "diagnostic_worker.jl" : "scenario_worker.jl")
        command = `$(Base.julia_cmd()) --startup-file=no --history-file=no --threads=$threads --project=$(abspath(project)) $worker $input $output`
        Sys.iswindows() || (command = Cmd(command; detach = true))
        # A selected worker project must not silently borrow packages from the
        # controller's global environment or a custom ambient load path.
        command = addenv(command,
            "JULIA_LOAD_PATH" => join(("@", "@stdlib"), Sys.iswindows() ? ';' : ':'))
        if testitems
            command = addenv(command, "PERFCHECKER_TESTITEM_MODE" => "performance")
        end
        started = time()
        logpath = joinpath(directory, "worker.log")
        return open(logpath, "w") do log
            process = run(pipeline(command; stdout = log, stderr = log); wait = false)
            status = "complete"
            try
                while process_running(process)
                    if cancellation.requested[] || time() - started > timeout
                        status = cancellation.requested[] ? "cancelled" : "timeout"
                        _stop_scenario_worker(process)
                        break
                    end
                    sleep(0.025)
                end
                wait(process)
                flush(log)
                if status != "complete"
                    return Dict{String, Any}("status" => status,
                        "message" => "isolated worker stopped", "elapsed_seconds" => time() -
                                                                                     started)
                elseif !success(process) || !isfile(output)
                    message = first(read(logpath, String), 8192)
                    return Dict{String, Any}("status" => "error", "message" => message)
                end
                result = TOML.parsefile(output)
                advisor && (result = _json_parse(result["payload_json"]))
                result["worker_elapsed_seconds"] = time() - started
                diagnostic && (result["log_excerpt"] = last(read(logpath, String), 16384))
                return result
            finally
                process_running(process) && _stop_scenario_worker(process)
                wait(process)
            end
        end
    end
end

function _scenario_bundle(catalog, spec, collector, raw, fingerprints)
    status = get(raw, "status", "error")
    definition_context = Dict("collector" => string(collector),
        "collector_version" => get(raw, "collector_version", string(VERSION)),
        "parameters" => spec.parameters, "repeatable" => spec.repeatable,
        "fixtures" => [fingerprints[path] for path in spec.fixtures],
        "source_sha256" => fingerprints[spec.source], "factory" => spec.factory,
        "measurement" => "operation-and-synchronization;fresh-state;evals=1/v1")
    fingerprint = _content_digest(definition_context)
    definitions, observations = Dict{String, Any}[], Dict{String, Any}[]
    metrics = (("time", "julia.wall.time", "s"), ("bytes", "julia.alloc.bytes", "By"),
        ("allocs", "julia.alloc.count", "1"))
    for (field, metric, unit) in metrics
        definition = "$metric/shared-$(collector)/$fingerprint"
        push!(definitions,
            Dict("id" => definition, "metric" => metric, "unit" => unit,
                "context" => definition_context))
        for (i, sample) in enumerate(get(raw, "samples", Any[]))
            haskey(sample, field) || continue
            push!(observations,
                Dict("metric" => metric, "unit" => unit,
                    "value" => sample[field], "measurement_definition" => definition,
                    "comparison_key" => definition, "sample_index" => i,
                    "attributes" => Dict("implementation" => spec.implementation,
                        "collector" => string(collector))))
        end
    end
    diagnostics = Dict{String, Any}[]
    status == "complete" || push!(diagnostics,
        Dict("rule_id" => "scenario.$status",
            "severity" => "error", "message" => get(raw, "message", status)))
    bundle = _provider_result(Dict("schema_version" => PROVIDER_RESULT_SCHEMA,
        "suite" => "shared-scenarios", "case_id" => spec.id, "target_id" => spec.implementation,
        "state" => status == "complete" ? "complete" : "failed",
        "runtime" => get(raw, "runtime", Dict("language" => "julia")),
        "environment" => Dict("os" => string(Sys.KERNEL), "arch" => string(Sys.ARCH),
            "hardware_ids" => Dict("cpu" => Sys.CPU_NAME, "host" => gethostname())),
        "measurement_definitions" => definitions, "observations" => observations,
        "diagnostics" => diagnostics))
    bundle.manifest["scenario"] = _scenario_dict(spec)
    bundle.manifest["source_provenance"] = _git_provenance(catalog.root)
    bundle.manifest["input_fingerprints"] = fingerprints
    bundle.manifest["qualification"] = Dict("availability" => status,
        "correctness" => get(raw, "correctness", "not_checked"),
        "quality" => "not_checked", "performance" => "not_compared")
    bundle.manifest["scenario_evidence"] = raw
    return bundle
end

"Measure explicit shared scenarios in fresh Julia processes; no package installation is performed."
function run_scenarios(catalog::ScenarioCatalog; project::AbstractString = catalog.root,
        samples::Integer = 10, timeout::Real = 120, threads::Integer = 1,
        cancellation::CancellationToken = CancellationToken(), reports = nothing)
    samples > 0 || throw(ArgumentError("samples must be positive"))
    bundles = RunBundle[]
    for spec in catalog.scenarios, collector in spec.collectors
        before = _scenario_fingerprints(spec)
        environment_before = _environment_provenance(project)
        request = Dict{String, Any}("scenario" => _scenario_dict(spec),
            "collector" => string(collector), "samples" => samples)
        raw = _scenario_process(request; project, timeout, cancellation, threads)
        after = _scenario_fingerprints(spec)
        if before != after
            raw["status"] = "invalid"
            raw["message"] = "scenario source or fixture changed during execution"
        end
        environment_after = _environment_provenance(project)
        raw["environment_provenance"] = environment_before
        if environment_before != environment_after
            raw["status"] = "invalid"
            raw["message"] = "worker environment or development dependency source changed during execution"
            raw["environment_after"] = environment_after
        end
        bundle = _scenario_bundle(catalog, spec, collector, raw, before)
        bundle.manifest["environment_provenance"] = [raw["environment_provenance"]]
        push!(bundles, bundle)
        reports === nothing ||
            write_run_bundle(bundle, joinpath(reports, bundle.manifest["run_id"]))
        cancellation.requested[] && return bundles
    end
    return bundles
end

function _scenario_run_record(bundle::RunBundle)
    summaries = Dict{String, Any}[]
    for metric in sort!(unique(String(o["metric"]) for o in bundle.observations))
        records = filter(o -> o["metric"] == metric, bundle.observations)
        values = Float64[o["value"] for o in records]
        isempty(values) && continue
        indices = unique(round.(
            Int, range(1, length(values); length = min(1000, length(values)))))
        push!(summaries,
            Dict("metric" => metric, "unit" => first(records)["unit"],
                "samples" => length(values), "median" => _median(values), "minimum" => minimum(values),
                "maximum" => maximum(values), "display_values" => values[indices],
                "display_truncated" => length(values) > 1000))
    end
    raw = bundle.manifest["scenario_evidence"]
    profile = Dict{String, Any}("kind" => get(raw, "collector", "unknown"),
        "text" => get(raw, "profile_text", ""), "samples" => get(raw, "profile_samples", 0),
        "stacks" => first(get(raw, "cpu_stacks", []), 2000),
        "allocation_sites" => first(get(raw, "allocation_sites", []), 2000),
        "truncated" => length(get(raw, "cpu_stacks", [])) > 2000 ||
                       length(get(raw, "allocation_sites", [])) > 2000)
    return Dict{String, Any}(
        "run_id" => bundle.manifest["run_id"], "scenario" => bundle.manifest["scenario"],
        "collector" => get(bundle.manifest["scenario_evidence"], "collector", "unknown"),
        "qualification" => bundle.manifest["qualification"], "summaries" => summaries, "profile" => profile)
end

"Compare each scenario/implementation/collector separately, retaining configurations not tested."
function compare_scenarios(baselines::AbstractVector{RunBundle},
        candidates::AbstractVector{RunBundle}; kwargs...)
    function key(b)
        (b.manifest["scenario"]["id"], b.manifest["scenario"]["implementation"],
            get(b.manifest["scenario_evidence"], "collector", "unknown"))
    end
    left, right = Dict(key(b) => b for b in baselines),
    Dict(key(b) => b for b in candidates)
    length(left) == length(baselines) && length(right) == length(candidates) ||
        throw(ArgumentError("duplicate scenario configuration"))
    records = Dict{String, Any}[]
    for identity in sort!(collect(union(keys(left), keys(right))))
        record = Dict{String, Any}(
            "scenario" => identity[1], "implementation" => identity[2],
            "collector" => identity[3])
        if !haskey(left, identity) || !haskey(right, identity)
            record["status"] = "not_tested"
        else
            comparison = compare_bundles(left[identity], right[identity]; kwargs...)
            record["status"] = string(comparison_verdict(comparison))
            record["comparison"] = comparison_dict(comparison)
        end
        push!(records, record)
    end
    return Dict("schema_version" => "perfchecker-scenario-comparison/1",
        "configurations" => records)
end
