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

"""
    ScenarioSpec(id; source, factory="make_case", implementation="default",
                 parameters=Dict(), fixtures=String[], collectors=[:benchmark],
                 repeatable=false, requirements=String[])

Declare a Julia workload and correctness protocol shared by measurement and
diagnostic workers. `id` and `implementation` form the scenario identity;
`factory` is a possibly dotted Julia function name in the existing `source` file.
The constructor resolves source and fixture paths, checks their existence and
validates TOML-compatible `parameters`. It does not include the source or invoke
the factory. `requirements` lists packages that must already be available to the
worker; packages are not installed implicitly.

The factory receives the parameter dictionary and returns a named tuple with
callbacks `prepare()`,
`operation(state)` and `verify(state, result)`. Verification must return `true`.
Optional `synchronize(state, result)` belongs to the operation boundary;
`cleanup(state)` releases state when Julia unwinds normally, including operation
or verification errors. Forced worker termination cannot guarantee an arbitrary
user cleanup callback, so externally owned files must remain recoverable. An
optional `availability()` callback returns `(available=Bool, reason=String)` and
can mark the workload unavailable before measurement.

`collectors` is a nonempty selection of `:benchmark`, `:chairmark`, `:profile`
and `:profile_alloc`. Each run prepares a fresh worker and preserves its collector
identity. `repeatable` records the workload's declared repeatability; it does not
prove it or bypass the correctness oracle. Empty or unsupported collector
selections are rejected; repeated collector values are normalized to one entry.

```julia
spec = ScenarioSpec("sum_squares"; source="perf/cases.jl",
    factory="make_sum_case", collectors=[:benchmark, :profile_alloc],
    parameters=Dict("length" => 1000), requirements=["Example"])
# The source factory has not run; select a prepared worker project before execution.
```
"""
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

"""
    ScenarioCatalog(root::AbstractString, scenarios::AbstractVector{ScenarioSpec})

Store an absolute package root and a copied vector of explicitly declared
scenarios. Reject duplicate `(id, implementation)` identities. Construction does
not discover tests, evaluate source or prepare dependencies. Proposals returned
by [`discover`](@ref) are not executable catalog members until the caller defines
their factory and correctness protocol.

```jldoctest
julia> catalog = ScenarioCatalog(pwd(), ScenarioSpec[]);

julia> isempty(catalog.scenarios)
true
```
"""
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

"""
    scenario_catalog_dict(catalog::ScenarioCatalog) -> Dict{String, Any}

Return a `perfchecker-scenario-catalog/1` object containing the absolute `root` and each
scenario's identity, factory, parameters, source, fixtures, collectors and
requirements. This conversion neither writes TOML nor runs the factory. Absolute
paths describe this local catalog; use relative paths deliberately when preparing
a catalog file for another machine.
"""
scenario_catalog_dict(catalog::ScenarioCatalog) = Dict{String, Any}(
    "schema_version" => SCENARIO_CATALOG_SCHEMA, "root" => catalog.root,
    "scenarios" => _scenario_dict.(catalog.scenarios))

"""
    load_scenario_catalog(path::AbstractString) -> ScenarioCatalog

Parse a TOML file with schema `perfchecker-scenario-catalog/1`. Resolve `root`, scenario
`source` and fixture paths against the catalog file's directory, then validate
each [`ScenarioSpec`](@ref). Missing files, unsupported collectors and duplicate
identities are errors. Parsing does not include package or test source, run the
factory, or install its dependencies. Prepare the selected worker `project`
before calling [`run_scenarios`](@ref) or [`diagnose`](@ref).
"""
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

"""
    CancellationToken()

Create a thread-safe, initially unrequested cancellation token for scenario,
diagnostic or advisor operations. Pass the same token to the operation and call
[`cancel!`](@ref) from another task to request interruption. A requested token is
not reset automatically; use a new token for an independent operation.

Requesting cancellation does not wait for worker termination. Wait for the
operation's final status before accessing resources owned by its worker.

```jldoctest
julia> token = CancellationToken(); cancel!(token);

julia> token.requested[]
true
```
"""
mutable struct CancellationToken
    requested::Threads.Atomic{Bool}
end
CancellationToken() = CancellationToken(Threads.Atomic{Bool}(false))
"""
    cancel!(token::CancellationToken) -> nothing

Atomically record a cancellation request. Repeated calls are harmless. Worker
owners observe the request and perform their own shutdown and cleanup; this
function does not itself kill a process or wait for cleanup. A remote advisor
server may have its own interruption contract. Inspect the operation's returned
status and diagnostics rather than treating this request as completed shutdown.
"""
cancel!(token::CancellationToken) = (token.requested[] = true; nothing)

function _scenario_fingerprints(spec::ScenarioSpec)
    Dict{String, Any}(path => isfile(path) ? _sha256_file(path) : "missing"
    for path in [spec.source; spec.fixtures])
end

"""
    select_scenarios(catalog::ScenarioCatalog, selection::AbstractVector) -> ScenarioCatalog

Return a catalog containing the exact `"id"`/`"implementation"` pairs named by
the selection dictionaries, in selection order. Reject duplicate selections and
unknown identities. An empty selection returns an empty catalog. Filtering does
not execute factories or promote inferred candidates to declared scenarios.
"""
function select_scenarios(catalog::ScenarioCatalog, selection::AbstractVector)
    requested = [(String(item["id"]), String(item["implementation"])) for item in selection]
    allunique(requested) || throw(ArgumentError("duplicate scenario selection"))
    available = Dict((spec.id, spec.implementation) => spec for spec in catalog.scenarios)
    all(key -> haskey(available, key), requested) ||
        throw(ArgumentError("unknown scenario selection"))
    return ScenarioCatalog(catalog.root, [available[key] for key in requested])
end

"""
    read_scenario_runs(directory::AbstractString) -> Vector{RunBundle}

Read a scenario bundle directory, or its immediate child bundle directories,
using [`read_run_bundle`](@ref)'s integrity checks. Keep bundles whose manifest
contains scenario metadata. Reject a missing directory or a directory containing
no such bundles. This is not a recursive search and does not modify evidence or
rerun the workload; use [`list_run_bundles`](@ref) for broader discovery.
"""
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

function _advisor_worker_diagnostics(logpath::AbstractString)
    # Read only a bounded tail, and expose only fixed phase markers. Provider
    # output can contain credentials, prompts, local paths or transport headers.
    excerpt = open(logpath, "r") do io
        seekend(io)
        seek(io, max(0, position(io) - 8192))
        String(read(io))
    end
    phases = ("dependencies_loading", "request_loading", "provider_loading",
        "provider_loaded", "transport", "mcp_initialize", "mcp_initialized_notification",
        "mcp_tools_list", "mcp_tools_call", "mcp_session_release", "response_validation",
        "response_write", "failed", "complete")
    markers = String[]
    phase = "process_start"
    for line in split(excerpt, '\n')
        isascii(line) || continue
        matched = match(
            r"^PERFCHECKER_ADVISOR_PHASE ([a-z_]+) ([0-9]+\.[0-9]+(?:e[+-]?[0-9]+)?)$",
            line)
        matched === nothing && continue
        matched[1] in phases || continue
        matched[1] in ("failed", "response_write", "complete") || (phase = matched[1])
        push!(markers, line)
    end
    Dict{String, Any}("worker_phase" => phase, "worker_log_excerpt" => join(markers, '\n'))
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
        # Controller instrumentation must not alter worker measurements or create
        # coverage/allocation files inside the fingerprinted development source.
        command = `$(Base.julia_cmd()) --startup-file=no --history-file=no --code-coverage=none --track-allocation=none --threads=$threads --project=$(abspath(project)) $worker $input $output`
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
                    result = Dict{String, Any}("status" => status,
                        "message" => "isolated worker stopped", "elapsed_seconds" => time() -
                                                                                     started)
                    advisor && merge!(result, _advisor_worker_diagnostics(logpath))
                    return result
                elseif !success(process) || !isfile(output)
                    message = advisor ? "isolated advisor worker failed" :
                              first(read(logpath, String), 8192)
                    result = Dict{String, Any}("status" => "error", "message" => message)
                    advisor && merge!(result, _advisor_worker_diagnostics(logpath))
                    return result
                end
                result = TOML.parsefile(output)
                advisor && (result = _json_parse(result["payload_json"]))
                advisor && get(result, "status", "error") != "complete" &&
                    merge!(result, _advisor_worker_diagnostics(logpath))
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
    if haskey(raw, "allocation_profile")
        summary = raw["allocation_profile"]
        diagnostic = _allocation_profile_diagnostic(summary)
        diagnostic === nothing || push!(diagnostics, diagnostic)
        for (field, metric, unit) in (("total_bytes", "julia.alloc.bytes", "By"),
            ("total_allocations", "julia.alloc.count", "1"))
            definition = "$metric/shared-profile-independent-totals/$fingerprint"
            context = merge(copy(definition_context),
                Dict("measurement" => summary["total_semantics"]))
            push!(definitions,
                Dict("id" => definition, "metric" => metric,
                    "unit" => unit, "context" => context))
            push!(observations,
                Dict("metric" => metric, "unit" => unit,
                    "value" => summary[field], "measurement_definition" => definition,
                    "comparison_key" => definition, "sample_index" => 1,
                    "aggregation" => "independent_operation_total", "scope" => "whole_operation",
                    "attributes" => Dict("implementation" => spec.implementation,
                        "collector" => string(collector), "profile_status" => summary["status"])))
        end
    end
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

"""
    run_scenarios(catalog::ScenarioCatalog; project=catalog.root, samples=10,
                  timeout=120, threads=1, cancellation=CancellationToken(),
                  reports=nothing) -> Vector{RunBundle}

Execute every declared scenario/collector pair in a separate Julia worker using
the existing `project`. `samples` must be positive; `timeout` is a finite positive
per-worker wall-time budget including startup, and `threads` selects the worker's
Julia thread count. Required collector and workload packages must already be
installed in that environment. Factories prepare state outside the measurement;
the operation and optional synchronization are measured, and verification checks
the result outside that boundary.

Return one portable bundle per attempted pair, including explicit unavailable,
invalid, error, timeout or cancelled outcomes. Source, fixtures and environment
fingerprints are checked before and after a run; changed inputs invalidate its
evidence. With `reports`, write each bundle under its run ID in that directory.
Cancellation returns the attempted bundles and does not start remaining pairs.
An empty catalog returns an empty vector without launching a worker.

The worker owner stops its process and cleans its own temporary transport files.
Ordinary Julia unwinding invokes the scenario's cleanup callback; forcibly
terminating the worker cannot run arbitrary user callbacks. Keep externally owned
temporary resources recoverable independently, and inspect recorded cleanup
failures before considering cancellation complete.

```julia
catalog = load_scenario_catalog("perf/scenarios.toml")
bundles = run_scenarios(catalog; project=".", samples=20,
    timeout=120, reports="perf/results/scenarios")
all(bundle_passed, bundles) # Inspect failed or unavailable bundles individually.
```
"""
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
        "allocation_profile" => get(raw, "allocation_profile", Dict()),
        "truncated" => length(get(raw, "cpu_stacks", [])) > 2000 ||
                       length(get(raw, "allocation_sites", [])) > 2000)
    return Dict{String, Any}(
        "run_id" => bundle.manifest["run_id"], "scenario" => bundle.manifest["scenario"],
        "collector" => get(bundle.manifest["scenario_evidence"], "collector", "unknown"),
        "qualification" => bundle.manifest["qualification"], "summaries" => summaries, "profile" => profile)
end

"""
    compare_scenarios(baselines::AbstractVector{RunBundle},
                      candidates::AbstractVector{RunBundle}; kwargs...) -> Dict

Join saved bundles by `(scenario id, implementation, collector)` and compare each
matched pair with [`compare_bundles`](@ref). Forward comparison keywords such as
`relative_limits`, `min_samples` and sample statistics; units and measurement
definitions must remain compatible. Duplicate identities on either side are
errors. Unmatched configurations stay `"not_tested"`, rather than being counted
as improvements or silently dropped.

Return `perfchecker-scenario-comparison/1` with a `configurations` array containing
each identity, status and matched comparison evidence. This only compares existing
evidence; it does not run workloads, install versions or change source.
"""
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
