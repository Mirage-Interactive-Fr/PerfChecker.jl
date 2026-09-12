function _scenario_cli(command, positional, options, stdout)
    root = abspath(_cli_value(
        options, "root", isempty(positional) ? pwd() : first(positional)))
    reports = _cli_value(options, "reports")
    force = _cli_bool(options, "force")
    payload = if command == "sync"
        scenario_sync(root; previous = _cli_value(options, "previous"))
    elseif command == "tools"
        tool_catalog(; category = _cli_value(options, "category"))
    elseif command in ("narrate", "evaluate-advisors")
        source = _cli_value(options, "source")
        source === nothing && throw(ArgumentError("--source is required"))
        configuration = _cli_value(options, "advisor-config")
        config = configuration === nothing ? AdvisorConfig() :
                 AdvisorConfig(;
            (Symbol(k) => v for (k, v) in _json_parsefile(configuration))...)
        project = abspath(_cli_value(options, "project", dirname(Base.active_project())))
        input = _json_parsefile(source)
        command == "narrate" ? narrate_advice(input; config, project) :
        evaluate_advisors(input["cases"]; config, project,
            include_investigator = _cli_bool(options, "investigator"),
            max_experiments = Base.parse(Int, _cli_value(options, "max-experiments", "4")),
            budget_seconds = Base.parse(
                Float64, _cli_value(options, "budget-seconds", "300")))
    elseif command == "investigate"
        catalog = load_scenario_catalog(_cli_value(
            options, "catalog", joinpath(root, "perf", "scenarios.toml")))
        selection = _cli_value(options, "selection")
        selection === nothing ||
            (catalog = select_scenarios(catalog, _json_parsefile(selection)))
        configuration = _cli_value(options, "advisor-config")
        advisor = configuration === nothing ? nothing :
                  AdvisorConfig(;
            (Symbol(k) => v for (k, v) in _json_parsefile(configuration))...)
        result = investigate(
            catalog; project = abspath(_cli_value(options, "project", catalog.root)),
            samples = Base.parse(Int, _cli_value(options, "samples", "10")), threads = Base.parse(
                Int, _cli_value(options, "threads", "1")),
            tools = Symbol.(split(
                _cli_value(options, "tools", "jet,alloccheck,latency"), ',')),
            max_experiments = Base.parse(Int, _cli_value(options, "max-experiments", "4")),
            budget_seconds = Base.parse(
                Float64, _cli_value(options, "budget-seconds", "300")),
            timeout = Base.parse(Float64, _cli_value(options, "timeout", "120")), advisor, reports)
        JSON.print(stdout, result, 2)
        return result["status"] == "cancelled" ? 1 : 0
    elseif command == "discover"
        discover(root; previous = _cli_value(options, "previous"))
    elseif command in ("diagnose", "run")
        catalog = load_scenario_catalog(_cli_value(
            options, "catalog", joinpath(root, "perf", "scenarios.toml")))
        selection = _cli_value(options, "selection")
        selection === nothing ||
            (catalog = select_scenarios(catalog, _json_parsefile(selection)))
        project = abspath(_cli_value(options, "project", catalog.root))
        timeout = Base.parse(Float64, _cli_value(options, "timeout", "120"))
        threads = Base.parse(Int, _cli_value(options, "threads", "1"))
        if command == "run"
            bundles = run_scenarios(catalog; project, timeout, threads, reports,
                samples = Base.parse(Int, _cli_value(options, "samples", "10")))
            result = Dict("schema_version" => "perfchecker-scenario-run/1",
                "runs" => _scenario_run_record.(bundles))
            reports === nothing || write_investigation_report(result, reports; force)
            JSON.print(stdout, result, 2)
            return !isempty(bundles) && all(bundle_passed, bundles) ? 0 : 1
        end
        selected = Symbol.(split(
            _cli_value(options, "tools", "jet,aqua,alloccheck,snoopcompile,latency"), ','))
        diagnose(catalog; project, timeout, threads, tools = selected, reports)
    elseif command == "compare"
        baseline = _cli_value(options, "baseline")
        candidate = _cli_value(options, "candidate")
        baseline !== nothing && candidate !== nothing ||
            throw(ArgumentError("scenario comparison requires --baseline and --candidate directories"))
        compare_scenarios(read_scenario_runs(baseline), read_scenario_runs(candidate);
            min_samples = Base.parse(Int, _cli_value(options, "min-samples", "10")))
    else
        source = _cli_value(options, "source", _cli_value(options, "bundle"))
        source === nothing &&
            throw(ArgumentError("advise requires --source=<diagnosis.json> or --bundle=<directory>"))
        if isdir(source)
            isfile(joinpath(source, "manifest.json")) ? advise(read_run_bundle(source)) :
            advise(Dict("schema_version" => DIAGNOSIS_SCHEMA, "records" => []);
                bundles = read_scenario_runs(source))
        else
            advise(_json_parsefile(source))
        end
    end
    if reports === nothing
        JSON.print(stdout, payload, 2)
    else
        foreach(path -> println(stdout, path),
            write_investigation_report(payload, reports; force))
    end
    if command == "diagnose"
        # Availability is distinct from findings, but requested missing checks are not successful execution.
        records = payload["records"]
        return !isempty(records) && all(r -> r["status"] == "complete", records) ? 0 : 1
    end
    command == "narrate" && return payload["status"] in ("complete", "not_needed") ? 0 : 1
    return 0
end
