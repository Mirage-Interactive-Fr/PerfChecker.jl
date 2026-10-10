"""
    counter_bundle(result; case_id="counters", target_id="current") -> RunBundle

Project a measured window into PerfChecker's portable evidence. Count units are
`1`, including CPU cycles; this is never a duration. Exact raw `UInt64` counts
and enabled/running nanoseconds are preserved as decimal strings in the raw
diagnostic. Numeric observations are emitted only up to `2^53-1`, so consumers
using IEEE Float64 cannot silently round larger counts. Such omitted observations
carry a warning. Unavailable results have no numeric observations or fake zeros.
No files are written and no callback is repeated.
"""
function counter_bundle(result::CounterResult; case_id = "counters", target_id = "current")
    result.status in (:complete, :unavailable, :failed, :invalid, :blocked) ||
        throw(ArgumentError("unknown counter result status"))
    result.status == :complete && isempty(result.records) &&
        throw(ArgumentError("a complete counter result requires raw records"))
    result.status == :unavailable && !isempty(result.records) &&
        throw(ArgumentError("unavailable counters cannot contain observations"))
    run_id, attempt_id = string(uuid4()), string(uuid4())
    definitions = Dict{String, Any}[]
    observations = Dict{String, Any}[]
    raw = Dict{String, Any}[]
    omitted = false
    for record in result.records
        _events([record.event])
        record.enabled_ns >= record.running_ns > 0 ||
            throw(ArgumentError("counter enabled/running times are inconsistent"))
        id = "linux.perf.count/" * bytes2hex(sha256(record.event))
        metric = "hardware.perf." * replace(record.event, '-' => '_')
        definition = Dict{String, Any}("id" => id, "metric" => metric,
            "unit" => "1", "collector" => "linuxperf",
            "event" => record.event, "attribution_scope" => "current_thread")
        push!(definitions, definition)
        attributes = Dict{String, Any}("event" => record.event,
            "thread_id" => result.thread_id, "allowed_cpuids" => result.allowed_cpuids,
            "userspace_only" => true, "includes_children" => false,
            "includes_hypervisor" => false, "scaled" => false,
            "raw_value" => string(record.value), "raw_encoding" => "uint64_decimal",
            "enabled_ns" => string(record.enabled_ns),
            "running_ns" => string(record.running_ns), "counter_time_unit" => "ns")
        push!(raw,
            merge(
                Dict{String, Any}("measurement_definition" => id,
                    "metric" => metric, "unit" => "1"),
                attributes))
        if record.value <= UInt64(2)^53 - 1
            push!(observations,
                Dict{String, Any}("record_type" => "observation",
                    "run_id" => run_id, "attempt_id" => attempt_id,
                    "case_id" => string(case_id), "target_id" => string(target_id),
                    "measurement_definition" => id, "metric" => metric, "unit" => "1",
                    "value" => record.value, "aggregation" => "single_counter_window",
                    "scope" => "current_thread", "sample_index" => 1,
                    "attributes" => attributes))
        else
            omitted = true
        end
    end
    diagnostics = [Dict{String, Any}("rule_id" => "hardware.counter.raw",
        "severity" => result.status == :unavailable ? "info" : "debug",
        "message" => result.reason, "evidence" => Dict{String, Any}(
            "status" => string(result.status), "records" => raw,
            "thread_id" => result.thread_id, "allowed_cpuids" => result.allowed_cpuids))]
    omitted && push!(diagnostics,
        Dict{String, Any}(
            "rule_id" => "hardware.counter.numeric_projection_unavailable",
            "severity" => "warning", "message" => "Exact counter exceeds Float64 integer precision; consult uint64_decimal raw evidence.",
            "evidence" => Dict{String, Any}()))
    manifest = Dict{String, Any}("schema_version" => "perfchecker-run-bundle/1",
        "run_id" => run_id, "attempt_id" => attempt_id,
        "state" => string(result.status), "case_id" => string(case_id),
        "suite" => "hardware-counters", "runtime" => Dict(
            "language" => "julia", "julia" => string(VERSION),
            "backend" => "LinuxPerf", "backend_version" => "0.4.2"),
        "collector_capabilities" => ["raw_counts", "enabled_ns", "running_ns"],
        "environment" => Dict("os" => string(Sys.KERNEL),
            "architecture" => string(Sys.ARCH), "cpu_name" => Sys.CPU_NAME), "warnings" => String[])
    RunBundle(manifest, definitions, observations, diagnostics, Dict{String, Any}[])
end

struct CounterUnavailable <: Exception
    reason::String
end
Base.showerror(io::IO, error::CounterUnavailable) = print(io, error.reason)
# Current custom-executor integration: unavailable is not a Pkg failure or a pass.
PerfChecker._unavailable_exception(::CounterUnavailable) = true

function _payload(bundle)
    merge(copy(bundle.manifest),
        Dict{String, Any}(
            "schema_version" => "perfchecker-provider-result/1",
            "measurement_definitions" => bundle.measurement_definitions,
            "observations" => bundle.observations, "diagnostics" => bundle.diagnostics,
            "artifacts" => bundle.artifacts))
end

"""
    counter_command(id; source, environment, package, target_kind, target_version,
                    target_source=nothing, oracle="", probes=[], events=["instructions", "cpu-cycles"],
                    timeout_seconds=300) -> ExternalCommandSpec

Declare a bounded, isolated Julia counter worker. `environment` is an existing,
explicitly prepared project containing this companion and the exact target.
Release version and development source identities are verified before including
the workload; this function installs nothing and executes nothing. `source`
defines `perf_setup()`, `perf_workload(state)`, optional
`perf_synchronize(state, result)`, `perf_cleanup(state)`, and the declared oracle.
The operation runs once; the two-argument oracle receives that actual result.
Preparation/probes/oracle/cleanup are outside the counter window. A supplied
`perf_cleanup` is attempted after preparation returns successfully, including
measurement/oracle failures. If `perf_setup` throws before returning, it is
responsible for releasing its partial resources. Subprocesses
inherit the caller's affinity and environment; no CPUs are repinned.
"""
function counter_command(id::Symbol; source, environment, package,
        target_kind, target_version, target_source = nothing, target_id = string(target_version),
        case_id = string(id), oracle = "",
        oracle_required = true, probes = Any[], pins = Any[], dev_sources = String[],
        events = ["instructions", "cpu-cycles"],
        timeout_seconds = 300)
    source = abspath(String(source))
    environment = abspath(String(environment))
    isfile(source) || throw(ArgumentError("counter workload does not exist"))
    isfile(joinpath(environment, "Project.toml")) ||
        throw(ArgumentError("counter worker project does not exist"))
    project = joinpath(environment, "Project.toml")
    manifest = joinpath(environment, "Manifest.toml")
    isfile(manifest) ||
        throw(ArgumentError("counter worker requires a resolved Manifest.toml"))
    request = Dict{String, Any}("source" => source, "package" => String(package),
        "source_sha256" => bytes2hex(sha256(read(source))),
        "environment_project_sha256" => bytes2hex(sha256(read(project))),
        "environment_manifest_sha256" => bytes2hex(sha256(read(manifest))),
        "target_kind" => String(target_kind), "target_version" => string(target_version),
        "target_source" => target_source, "target_id" => String(target_id),
        "case_id" => String(case_id), "oracle" => String(oracle),
        "oracle_required" => Bool(oracle_required), "probes" => probes,
        "pins" => pins, "dev_sources" => dev_sources,
        "events" => _events(events))
    worker = joinpath(@__DIR__, "worker.jl")
    command = vcat(Base.julia_cmd().exec,
        ["--startup-file=no", "--project=" * environment, worker, JSON.json(request)])
    ExternalCommandSpec(id, "julia-linuxperf", command;
        directory = environment, timeout_seconds)
end

function _counter_execute(planned, config, sink)
    planned.feature.backend == :linuxperf ||
        throw(ArgumentError("LinuxPerf executor accepts only :linuxperf features"))
    planned.target.kind in (:dev, :release) ||
        throw(CounterUnavailable("candidate targets require an explicitly prepared release/development identity"))
    environment = get(config.options, :counter_environment, nothing)
    environment isa AbstractString ||
        throw(ArgumentError("counter_environment is required"))
    oracle = planned.feature.oracle
    probes = [Dict("id" => string(probe.id), "function" => string(probe.function_name),
                  "blocking" => probe.blocking, "category" => string(probe.category))
              for probe in planned.feature.probes]
    command = counter_command(planned.feature.id;
        source = planned.variant.entrypoint, environment,
        package = planned.package_suite.package, target_kind = planned.target.kind,
        target_version = planned.target.compatibility_version,
        target_id = planned.target.label,
        case_id = string(
            planned.suite, "/", planned.package_suite.id, "/", planned.feature.id),
        target_source = planned.target.kind == :dev ? planned.package_suite.source :
                        nothing,
        oracle = oracle === nothing ? "" : string(oracle.function_name),
        oracle_required = oracle === nothing ? false : oracle.required, probes,
        pins = _pin_requests(get(planned.package_suite.release_pins,
            planned.target.compatibility_version, Any[])),
        dev_sources = planned.target.kind == :dev ? planned.package_suite.dev_sources :
                      String[],
        events = get(config.options, :events, ["instructions", "cpu-cycles"]),
        timeout_seconds = get(config.options, :timeout_seconds, 300))
    bundle = run_external_command(command)
    sink(planned, bundle)
    return _counter_checker_result(bundle, config.options[:tags])
end

"""
    _counter_checker_result(bundle::RunBundle, tags)

Convert completed provider evidence to a qualified `PerfChecker.CheckerResult`.
Retain its raw payload and copied worker qualification without running counters.
Unavailable, invalid and blocked states raise their existing typed failures;
other incomplete states raise an error rather than becoming successful results.
"""
function _counter_checker_result(bundle::RunBundle, tags)
    qualification = _worker_qualification(bundle)
    state = bundle.manifest["state"]
    state == "unavailable" && throw(CounterUnavailable(
        join([String(get(item, "message", "")) for item in bundle.diagnostics], "; ")))
    state == "invalid" &&
        throw(PerfChecker.QualificationFailure(:correctness, qualification))
    state == "blocked" && throw(PerfChecker.QualificationFailure(:probe, qualification))
    state == "complete" || error("counter worker failed: " *
          join([String(get(item, "message", "")) for item in bundle.diagnostics], "; "))
    # The portable provider bundle is authoritative; no benchmark-shaped fake columns.
    qualification["counter_bundle"] = _payload(bundle)
    PerfChecker.CheckerResult([PerfChecker.Table(counter_records = [bundle.observations])],
        nothing, tags, Pkg.PackageSpec[], [qualification])
end

function _worker_qualification(bundle)
    record = findfirst(
        item -> get(item, "rule_id", "") == "hardware.counter.qualification",
        bundle.diagnostics)
    record === nothing ? PerfChecker._empty_qualification() :
    deepcopy(bundle.diagnostics[record]["evidence"])
end

"""
    counter_executor(; bundle_sink=(planned, bundle)->nothing)

Return the explicit executor for `run_suite(plan; executor=...)`. Each row uses
`ExternalCommandSpec` and validates its actual worker target. The sink receives
portable provider evidence even for unavailable/failed runs. Use
[`run_counter_suite`](@ref) to retain this evidence in all suite qualifications.
This companion specializes PerfChecker's current internal unavailable predicate
only for its own exception type; ordinary executors and Pkg exceptions are unchanged.
"""
counter_executor(; bundle_sink = (planned, bundle) -> nothing) = (planned, config, setup, workload) -> _counter_execute(
    planned, config, bundle_sink)

"""
    run_counter_suite(plan::SuitePlan; strict=false, kwargs...) -> SoftwareSuiteResult

Run a declared `:linuxperf` suite through real isolated counter workers. Capture
provider bundles and qualification/provenance for every attempted row, including
unavailable rows. Targets/dependencies must already be prepared in each explicit
`counter_environment`; no target installation is performed by this companion.
`strict=true` raises for an execution failure after collecting evidence. Hardware
unavailability remains visible and is never a successful measurement assertion.
"""
function run_counter_suite(plan::PerfChecker.SuitePlan; strict = false, kwargs...)
    bundles = Dict{Any, RunBundle}()
    sink = (planned, bundle) -> (bundles[_run_key(planned)] = bundle)
    result = run_suite(plan; executor = counter_executor(; bundle_sink = sink),
        strict = false, kwargs...)
    runs = map(result.runs) do run
        bundle = get(bundles, _run_key(run.planned), nothing)
        bundle === nothing && return run
        qualification = merge(deepcopy(run.qualification), _worker_qualification(bundle))
        qualification["counter_bundle"] = _payload(bundle)
        PerfChecker._finalize_qualification!(qualification)
        PerfChecker.FeatureRun(run.planned, run.status, run.elapsed_seconds,
            run.result, run.message, qualification)
    end
    combined = PerfChecker.SoftwareSuiteResult(result.plan, result.started_at,
        result.finished_at, runs)
    strict && !suite_passed(combined) && error("counter suite failed")
    combined
end

function _run_key(planned)
    (planned.suite, planned.package_suite.id, planned.feature.id,
        planned.target.label, planned.comparison_key)
end

function _pin_requests(pins)
    map(pins) do pin
        pin isa Pkg.PackageSpec && pin.name !== nothing && pin.version isa VersionNumber ||
            throw(ArgumentError("counter release pins must name an exact PackageSpec version"))
        Dict("name" => pin.name, "version" => string(pin.version))
    end
end

include("worker_runtime.jl")
