function _target_identity(request)
    project = Base.active_project()
    manifest = joinpath(dirname(project), "Manifest.toml")
    bytes2hex(sha256(read(project))) == request["environment_project_sha256"] &&
        bytes2hex(sha256(read(manifest))) == request["environment_manifest_sha256"] ||
        throw(CounterUnavailable("worker environment changed after declaration"))
    installed = collect(values(Pkg.dependencies()))
    backend = only(filter(info -> info.name == "LIKWID", installed))
    backend.version == v"0.4.6" ||
        throw(CounterUnavailable("counter backend version differs from the supported contract"))
    matching = filter(info -> info.name == request["package"], installed)
    length(matching) == 1 ||
        throw(CounterUnavailable("requested package is not uniquely installed"))
    info = only(matching)
    expected = VersionNumber(request["target_version"])
    info.version == expected ||
        throw(CounterUnavailable("installed target version differs from declared target"))
    if request["target_kind"] == "dev"
        source = request["target_source"]
        source isa AbstractString && info.source !== nothing &&
            realpath(info.source) == realpath(source) ||
            throw(CounterUnavailable("installed development source differs from declared target"))
    elseif request["target_kind"] == "release"
        info.is_tracking_registry ||
            throw(CounterUnavailable("declared release is not installed from the registry"))
    else
        throw(CounterUnavailable("unsupported target kind"))
    end
    for pin in request["pins"]
        entries = filter(item -> item.name == pin["name"], installed)
        length(entries) == 1 && only(entries).version == VersionNumber(pin["version"]) ||
            throw(CounterUnavailable("installed dependency differs from exact release pin"))
    end
    for source in request["dev_sources"]
        project = TOML.parsefile(joinpath(source, "Project.toml"))
        entries = filter(item -> item.name == project["name"], installed)
        length(entries) == 1 && only(entries).source !== nothing &&
            realpath(only(entries).source) == realpath(source) ||
            throw(CounterUnavailable("installed development dependency differs from declaration"))
    end
    project = Base.active_project()
    manifest = joinpath(dirname(project), "Manifest.toml")
    Dict{String, Any}(
        "target" => Dict("name" => info.name,
            "version" => string(info.version), "source" => info.source,
            "tree_sha1" => info.tree_hash === nothing ? nothing : string(info.tree_hash)),
        "project_sha256" => bytes2hex(sha256(read(project))),
        "manifest_sha256" => isfile(manifest) ? bytes2hex(sha256(read(manifest))) : nothing,
        "backend" => Dict("name" => backend.name, "version" => string(backend.version),
            "source_sha256" => bytes2hex(sha256(read(pathof(LIKWID))))),
        "requested_pins" => request["pins"], "julia_version" => string(VERSION))
end

function _check_record(raw)
    raw === true || raw === nothing || raw isa AbstractString ?
    Dict{String, Any}(
        "status" => "passed", "message" => raw isa AbstractString ? String(raw) : "") :
    raw === false ?
    Dict{String, Any}("status" => "failed", "message" => "check returned false") :
    raw isa AbstractDict || raw isa NamedTuple ?
    begin
        record = Dict{String, Any}(string(key) => value for (key, value) in pairs(raw))
        status = lowercase(String(get(record, "status", "passed")))
        record["status"] = status in (
            "pass", "passed", "available", "supported", "ok", "valid") ?
                           "passed" :
                           status in ("unavailable", "unsupported", "missing") ?
                           "unavailable" : "failed"
        get!(record, "message", "")
        record
    end :
    Dict{String, Any}("status" => "failed", "message" => "unsupported check return type")
end

function _run_request(request)
    qualification = PerfChecker._empty_qualification()
    qualification["source_provenance"] = Dict(
        "entrypoint_sha256" => bytes2hex(sha256(read(request["source"]))))
    measured = CounterResult(
        :unavailable, "not_started", CounterRecord[], Int[], Int[], nothing)
    owner = nothing
    has(name) = Base.invokelatest(isdefined, owner, name)
    field(name) = Base.invokelatest(getfield, owner, name)
    accepts(f, args...) = Base.invokelatest(applicable, f, args...)
    state = nothing
    prepared = false
    output = Ref{Any}()
    invoked = false
    phase = "source_validation"
    try
        actual_source = bytes2hex(sha256(read(request["source"])))
        actual_source == request["source_sha256"] ||
            throw(CounterUnavailable("workload source changed after command declaration"))
        phase = "target_validation"
        qualification["environment_provenance"] = _target_identity(request)
        phase = "source_loading"
        owner = Module(gensym(:HardwareCounterWorkload), true, true)
        Base.include(owner, request["source"])
        has(:perf_workload) || error("perf_workload(state) is required")
        phase = "prepare"
        state = has(:perf_setup) ? Base.invokelatest(field(:perf_setup)) : nothing
        prepared = true
        phase = "probes"
        probe_records = Dict{String, Any}[]
        for probe in request["probes"]
            name = Symbol(probe["function"])
            record = if has(name)
                callback = field(name)
                accepts(callback, state) ? _checked_call(callback, state) :
                _checked_call(callback)
            else
                Dict{String, Any}(
                    "status" => "unavailable", "message" => "probe is not defined")
            end
            merge!(record, probe)
            push!(probe_records, record)
        end
        qualification["probes"] = probe_records
        if any(record -> record["blocking"] && record["status"] != "passed", probe_records)
            measured = CounterResult(:blocked, "blocking probe did not pass",
                CounterRecord[], Int[], Int[], nothing)
        else
            phase = "operation"
            measured = measure_counters(; event_set = request["event_set"],
                cpuids = request["cpuids"], units = request["units"]) do
                output[] = Base.invokelatest(field(:perf_workload), state)
                invoked = true
                has(:perf_synchronize) &&
                    Base.invokelatest(field(:perf_synchronize), state, output[])
                nothing
            end
            # The counter window is stopped before any oracle call. Never repeat workload.
            if invoked && !isempty(request["oracle"])
                phase = "oracle"
                name = Symbol(request["oracle"])
                record = if has(name)
                    oracle = field(name)
                    raw = accepts(oracle, state, output[]) ?
                          _checked_call(oracle, state, output[]) :
                          accepts(oracle, state) ? _checked_call(oracle, state) :
                          _checked_call(oracle)
                    _check_record(raw)
                else
                    Dict{String, Any}(
                        "status" => request["oracle_required"] ? "failed" : "not_checked",
                        "message" => "oracle is not defined")
                end
                record["function"] = request["oracle"]
                record["required"] = request["oracle_required"]
                qualification["correctness"] = record
                !(record["status"] in ("passed", "not_checked")) &&
                    (measured = CounterResult(
                        :invalid, "correctness oracle failed", measured.records,
                        measured.allowed_cpuids, measured.cpuids, measured.group_time_seconds,
                        measured.access_mode, measured.perf_pid))
            end
        end
    catch error
        measured = CounterResult(error isa CounterUnavailable ? :unavailable : :failed,
            phase * ": " * sprint(showerror, error), CounterRecord[], Int[], Int[], nothing)
    finally
        if prepared && has(:perf_cleanup)
            try
                Base.invokelatest(field(:perf_cleanup), state)
            catch error
                measured = CounterResult(
                    :failed, measured.reason * "; cleanup: " * sprint(showerror, error),
                    CounterRecord[], Int[], Int[], nothing)
            end
        end
    end
    PerfChecker._finalize_qualification!(qualification)
    bundle = counter_bundle(measured;
        case_id = request["case_id"], target_id = request["target_id"])
    push!(bundle.diagnostics,
        Dict{String, Any}("rule_id" => "hardware.counter.qualification",
            "severity" => "info", "message" => "Worker qualification and explicit source/environment identities",
            "evidence" => qualification))
    bundle
end

function _provider_main(text)
    request = JSON.parse(text)
    bundle = _run_request(request)
    destination = ENV["PERFCHECKER_OUTPUT"]
    open(destination, "w") do io
        JSON.print(io, _payload(bundle))
    end
    nothing
end

function _checked_call(callback, args...)
    try
        _check_record(Base.invokelatest(callback, args...))
    catch error
        Dict{String, Any}("status" => "failed", "message" => sprint(showerror, error))
    end
end
