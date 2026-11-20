# Reuse SharedScenarioRuntime, already included by diagnostics.jl and by
# isolated workers; do not create a second lifecycle or collector implementation.

const _LIVE_SCENARIO_LOCK = ReentrantLock()
const _LIVE_SCENARIO_ACTIVE = Ref(false)

function _live_callback_sources(case, source_files)
    files = Set{String}()
    missing = String[]
    definitions = Dict{String, Any}[]
    for name in (:prepare, :operation, :verify, :synchronize, :cleanup, :availability)
        hasproperty(case, name) || continue
        callable = getproperty(case, name)
        found = false
        for method in methods(callable)
            file = string(method.file)
            available = isfile(file)
            available && push!(files, abspath(file))
            found |= available
            push!(definitions, Dict("callback" => string(name), "signature" => string(method.sig),
                "file" => file, "line" => Int(method.line), "source_available" => available))
        end
        found || push!(missing, string(name))
    end
    for file in source_files
        file isa AbstractString && isfile(file) || throw(ArgumentError("declared callback source does not exist"))
        push!(files, abspath(file))
    end
    return sort!(collect(files)), missing, definitions
end
_live_fingerprints(files) = Dict{String, Any}(file => _sha256_file(file) for file in files)

"""
    run_scenario(case::NamedTuple; id, implementation="default",
        collectors=(:benchmark,), samples=10, project=..., source_files=(),
        qualification=Dict(), qualification_limits="", exclusive_profiles=false)

Measure already-loaded callbacks in this process without writing a factory or
serializing executable closures. Return ordinary `RunBundle`s, one per selected
collector. `case` has `prepare()`, `operation(state)`, `verify(state,result)::Bool`
and optionally `synchronize(state,result)`, `cleanup(state)`, and `availability()`.
Use the same fresh-state, evals=1 collectors as [`run_scenarios`](@ref). The oracle
and cleanup hooks are outside the timed operation; synchronization is inside.
Preparation must clean up acquisitions if it throws before returning its state.
After state publication, callback failures and oracle failures run cleanup.

Declared and discoverable method source files and the project/development
package environment are hashed before and after each collector; drift invalidates
that bundle. `qualification` records caller-supplied live-workload identity.
If any callback lacks discoverable source, explicitly describe that limitation
in `qualification_limits`, even when supplemental source files are declared.
File hashes do not prove live lowered code matches disk, capture immutability,
absence of external effects or cross-session closure portability.

This is an IN-PROCESS experiment: other tasks, JIT history, shared caches and
external globals remain visible. Concurrent or nested calls to this entry point
are rejected. CPU/allocation profiles additionally require
`exclusive_profiles=true`: the caller grants exclusive ownership of both global
profile buffers and consents to clearing them. Julia has no public allocation-
profiler active-state query; unrelated external profiling cannot be detected or
protected. Do not use this option during another profiler or timing campaign.
No GC enable/disable settings are changed; the chosen collector's normal GC
policy still applies. Profile evidence is never a timing/FPS measurement.

BenchmarkTools allocation values are trial-level estimates repeated alongside
its timing samples. They are not independent exact allocation observations.
Source/environment qualification does not imply process isolation, owned-memory
measurement, a correctness proof beyond the supplied oracle, or a preferred
backend. Nothing is persisted by this function.
"""
function run_scenario(case::NamedTuple; id::AbstractString,
    implementation::AbstractString = "default", collectors = (:benchmark,),
    samples::Integer = 10,
    project::AbstractString = something(Base.active_project(), pwd()),
    source_files = (), qualification = Dict(),
    qualification_limits::AbstractString = "", exclusive_profiles::Bool = false)
    isempty(id) && throw(ArgumentError("scenario id must not be empty"))
    isempty(implementation) && throw(ArgumentError("implementation must not be empty"))
    !(samples isa Bool) && samples > 0 || throw(ArgumentError("samples must be positive"))
    all(name -> hasproperty(case, name), (:prepare, :operation, :verify)) ||
        throw(ArgumentError("callback scenario requires prepare, operation and verify"))
    selected = unique(Symbol.(collect(collectors)))
    !isempty(selected) && all(c -> c in (:benchmark, :chairmark, :profile, :profile_alloc), selected) ||
        throw(ArgumentError("unsupported or empty collectors"))
    profiling = any(c -> c in (:profile, :profile_alloc), selected)
    profiling && !exclusive_profiles && throw(ArgumentError("in-process profiles require exclusive_profiles=true"))
    root = isfile(project) ? dirname(abspath(project)) : abspath(project)
    isdir(root) || throw(ArgumentError("scenario project directory does not exist"))
    files, missing, definitions = _live_callback_sources(case, source_files)
    isempty(missing) || !isempty(strip(qualification_limits)) ||
        throw(ArgumentError("callbacks without discoverable source require explicit qualification_limits"))
    frozen_qualification = deepcopy(qualification)
    # Validate/digest only an evidence snapshot, not executable callback objects.
    qualification_digest = _content_digest(frozen_qualification)
    trylock(_LIVE_SCENARIO_LOCK) || throw(ArgumentError("another live scenario is active"))
    if _LIVE_SCENARIO_ACTIVE[]
        unlock(_LIVE_SCENARIO_LOCK)
        throw(ArgumentError("nested live scenarios are prohibited"))
    end
    _LIVE_SCENARIO_ACTIVE[] = true
    bundles = RunBundle[]
    try
        for collector in selected
            before = _live_fingerprints(files)
            environment_before = _environment_provenance(root)
            raw = try
                if hasproperty(case, :availability)
                    available = Base.invokelatest(case.availability)
                    available isa NamedTuple && hasproperty(available, :available) &&
                        hasproperty(available, :reason) && available.available isa Bool ||
                        throw(ArgumentError("availability requires available::Bool and reason"))
                    available.available || throw(SharedScenarioRuntime.ScenarioUnavailable(string(available.reason)))
                end
                Base.invokelatest(SharedScenarioRuntime.execute_loaded, case, string(collector), Int(samples))
            catch error
                error isa InterruptException && rethrow()
                Dict{String, Any}("status" => error isa SharedScenarioRuntime.ScenarioUnavailable ? "unavailable" : "error",
                    "correctness" => "not_passed", "collector" => string(collector),
                    "message" => sprint(showerror, error),
                    "runtime" => Dict("language" => "julia", "version" => string(VERSION),
                        "threads" => Threads.nthreads()))
            end
            after = _live_fingerprints(files)
            environment_after = _environment_provenance(root)
            if before != after || environment_before != environment_after ||
                _content_digest(qualification) != qualification_digest
                raw["status"] = "invalid"
                raw["message"] = "callback source, caller qualification or environment changed during execution"
                raw["source_after"] = after
                raw["environment_after"] = environment_after
            end
            context = Dict{String, Any}("collector" => string(collector),
                "collector_version" => get(raw, "collector_version", string(VERSION)),
                "measurement" => "operation-and-synchronization;fresh-state;evals=1;live-inprocess/v1",
                "source_fingerprints" => before, "definitions" => definitions,
                "qualification" => frozen_qualification, "qualification_limits" => string(qualification_limits),
                "isolation" => "none;caller-process", "parameters" => Dict())
            scenario = Dict{String, Any}("id" => String(id), "implementation" => String(implementation),
                "execution" => "live-callbacks", "collectors" => string.(selected),
                "parameters" => Dict(), "source_files" => files)
            bundle = _scenario_bundle_from_context(root, scenario, collector, raw, before, context;
                suite = "live-scenarios")
            bundle.manifest["environment_provenance"] = [environment_before]
            bundle.manifest["live_qualification"] = Dict("scope" => "in-process;not-isolated",
                "limits" => string(qualification_limits), "undiscoverable_callbacks" => missing,
                "exclusive_profiles" => exclusive_profiles, "caller" => frozen_qualification)
            push!(bundles, bundle)
        end
    finally
        _LIVE_SCENARIO_ACTIVE[] = false
        unlock(_LIVE_SCENARIO_LOCK)
    end
    return bundles
end
