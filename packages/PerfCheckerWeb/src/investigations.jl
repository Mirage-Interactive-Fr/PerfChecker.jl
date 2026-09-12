struct _InvestigationArtifactBody
    path::String
end

function _investigation_artifact_body(file)
    @static if isdefined(HTTP, :CallbackBody)
        # HTTP 2 requires its streaming-body contract. Open lazily and let the
        # server close the file on completion or when the client disconnects.
        input = Ref{Union{Nothing, IOStream}}(nothing)
        return HTTP.CallbackBody(
            buffer -> begin
                input[] === nothing && (input[] = open(file))
                readbytes!(input[], buffer)
            end,
            () -> begin
                input[] === nothing || close(input[])
                nothing
            end)
    else
        return _InvestigationArtifactBody(file)
    end
end

# Let HTTP own response headers and connection reuse. Only the body is streamed,
# so Oxygen cannot serialize a second response after a manually written stream.
function Base.write(output::IO, body::_InvestigationArtifactBody)
    open(body.path) do input
        buffer = Vector{UInt8}(undef, 1_048_576)
        total = 0
        while !eof(input)
            count = readbytes!(input, buffer)
            total += write(output, view(buffer, 1:count))
        end
        total
    end
end

function _scenario_studio_html(prefix, token)
    base = _html_escape(prefix)
    """<!doctype html><html lang="en"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>PerfChecker investigations</title><link rel="stylesheet" href="$base/assets/investigations.css"></head>
<body data-api="$base" data-token="$(_html_escape(token))"><header><p class="eyebrow">PerfChecker</p><h1>Understand. Improve. Verify.</h1><p>Shared scenarios, separate qualifications, evidence-based advice.</p></header>
<main><section class="card"><h2>Declared scenarios</h2><div id="scenarios"></div><fieldset id="tools"><legend>Analyzers</legend></fieldset><div class="controls"><label>Samples<input id="samples" type="number" min="1" max="10000" value="10"></label><label>Seconds per worker<input id="timeout" type="number" min="1" max="3600" value="120"></label><label>Threads<input id="threads" type="number" min="1" value="1"></label></div><div class="controls"><label>Maximum experiments<input id="max_experiments" type="number" min="1" max="100" value="4"></label><label>Total seconds<input id="budget_seconds" type="number" min="1" max="86400" value="300"></label></div><p id="advisor-status"></p><div class="toolbar"><button id="discover">Discover tests</button><button id="measure">Measure selected</button><button id="diagnose">Diagnose selected</button><button id="investigate">Investigate selected</button><button id="sync">Relate to CI</button><button id="inventory">Tool catalogue</button><button id="cancel" disabled>Cancel</button></div><p id="status" role="status">Ready</p></section>
<section class="card"><h2>Saved evidence</h2><div class="toolbar"><select id="history" aria-label="Saved investigation"></select><button id="open">Open evidence</button><button id="advise">Read advice</button><button id="narrate">Explain with configured model</button><button id="json">Open JSON</button><button id="markdown">Open Markdown</button></div><div class="toolbar"><select id="baseline" aria-label="Baseline measurements"></select><select id="candidate" aria-label="Candidate measurements"></select><button id="compare">Compare before / after</button></div></section>
<p><a href="$base/advisor">Configurer le conseiller et gérer les modèles</a></p><section id="evidence" aria-live="polite"></section></main><script src="$base/assets/investigations.js"></script></body></html>"""
end

function PerfChecker.register_oxygen_routes!(catalog::PerfChecker.ScenarioCatalog;
        prefix::AbstractString = "/perfchecker/scenarios", project::AbstractString = catalog.root,
        catalog_path = nothing, advisor = nothing,
        reports_root::AbstractString = joinpath(
            catalog.root, "perf", "results", "investigations"))
    base = String(rstrip(String(prefix), '/'))
    api = Oxygen.router(base; tags = ["PerfChecker investigations"])
    store = abspath(reports_root)
    mkpath(store)
    token = string(PerfChecker.uuid4())
    mutex = ReentrantLock()
    jobs = Dict{String, Any}()
    setup_file = joinpath(store, "advisor-settings.json")
    setup_options = Dict{String, Any}(
        "investigates" => false, "max_experiments" => 4, "budget_seconds" => 300)
    if isfile(setup_file)
        previous = PerfChecker._json_parsefile(setup_file)
        if advisor === nothing && get(previous, "enabled", false)
            advisor = PerfChecker._advisor_draft(previous["config"])
        end
        for key in keys(setup_options)
            setup_options[key] = get(previous, key, setup_options[key])
        end
    end
    function current_catalog()
        catalog_path === nothing ? catalog : PerfChecker.load_scenario_catalog(catalog_path)
    end
    guarded(request) = HTTP.header(request, "X-PerfChecker-CSRF", "") == token
    function denied()
        Oxygen.json(Dict("error" => "missing investigation session token"); status = 403)
    end
    function failure(error)
        Oxygen.json(Dict("error" => first(sprint(showerror, error), 2000)); status = 400)
    end
    headers = [
        "Content-Security-Policy" => "default-src 'self'; script-src 'self'; style-src 'self' 'unsafe-inline'; frame-ancestors 'none'",
        "Cache-Control" => "no-store", "X-Content-Type-Options" => "nosniff"]
    function get_advisor_settings()
        merge(copy(setup_options),
            Dict("enabled" => advisor !== nothing, "config_location" => setup_file,
                "config" => advisor === nothing ?
                            PerfChecker._advisor_config(PerfChecker.AdvisorConfig()) :
                            PerfChecker._advisor_config(advisor)))
    end
    function save_advisor_settings(input)
        config = get(input, "config", nothing)
        proposed = config === nothing ? nothing : PerfChecker._advisor_draft(config)
        investigates = get(input, "investigates", false)
        count, budget = get(input, "max_experiments", 4), get(input, "budget_seconds", 300)
        investigates isa Bool && count isa Integer && 1 <= count <= 100 &&
            budget isa Real && isfinite(budget) && 1 <= budget <= 86400 ||
            throw(ArgumentError("Invalid investigation limits."))
        proposed !== nothing && proposed.protocol == :mcp_http &&
            proposed.mcp_response == :text && investigates &&
            throw(ArgumentError("MCP investigation requires structured responses."))
        payload = Dict("enabled" => proposed !== nothing,
            "config" => proposed === nothing ? nothing :
                        PerfChecker._advisor_config(proposed),
            "investigates" => proposed !== nothing && investigates, "max_experiments" => count, "budget_seconds" => budget)
        PerfChecker._write_json(setup_file, payload; canonical = true)
        advisor = proposed
        for key in keys(setup_options)
            setup_options[key] = payload[key]
        end
    end
    setup_running = _register_advisor_setup(
        api, base, token, guarded, denied, failure, headers,
        project, store, get_advisor_settings, save_advisor_settings,
        () -> any(job -> PerfChecker.investigation_status(job)["status"] == "running",
            values(jobs)))
    function saved(id)
        occursin(r"^[a-f0-9-]{36}$", id) || throw(ArgumentError("invalid investigation id"))
        directory = joinpath(store, id)
        isdir(directory) || throw(ArgumentError("unknown investigation"))
        metadata = if isfile(joinpath(directory, "job.json"))
            PerfChecker._json_parsefile(joinpath(directory, "job.json"))
        else
            job = lock(mutex) do
                get(jobs, id, nothing)
            end
            job === nothing && throw(ArgumentError("unknown investigation"))
            PerfChecker.investigation_status(job; include_result = false)
        end
        filename = Dict("discover" => "discovery.json",
            "diagnose" => "diagnosis.json", "run" => "run.json",
            "tools" => "tools.json", "sync" => "sync.json", "narrate" => "narrative.json",
            "investigate" => "investigation.json")[metadata["action"]]
        file = joinpath(directory, filename)
        filesize(file) <= 32_000_000 ||
            throw(ArgumentError("report exceeds the 32 MB display limit"))
        return directory, PerfChecker._json_parsefile(file)
    end
    function listing()
        records = Dict{String, Any}[]
        for directory in readdir(store; join = true)
            isfile(joinpath(directory, "job.json")) || continue
            push!(records, PerfChecker._json_parsefile(joinpath(directory, "job.json")))
        end
        lock(mutex) do
            for (id, job) in jobs
                filter!(item -> item["id"] != id, records)
                push!(
                    records, PerfChecker.investigation_status(job; include_result = false))
            end
        end
        return records
    end
    Oxygen.get(api("/")) do
        Oxygen.html(_scenario_studio_html(base, token); headers)
    end
    Oxygen.get(api("/assets/investigations.js")) do
        Oxygen.js(read(joinpath(_STUDIO_ASSET_ROOT, "investigations.js"), String))
    end
    Oxygen.get(api("/assets/investigations.css")) do
        Oxygen.css(read(joinpath(_STUDIO_ASSET_ROOT, "investigations.css"), String))
    end
    Oxygen.get(api("/catalog")) do
        Oxygen.json(merge(PerfChecker.scenario_catalog_dict(current_catalog()),
            Dict("analyzers" => PerfChecker._scenario_capabilities(),
                "advisor" => advisor === nothing ? "disabled" : advisor.model,
                "advisor_limits" => setup_options)))
    end
    Oxygen.get(api("/jobs")) do
        Oxygen.json(listing())
    end
    Oxygen.get(api("/job")) do request
        id = String(get(Oxygen.queryparams(request), "id", ""))
        job = lock(mutex) do
            get(jobs, id, nothing)
        end
        job === nothing && return Oxygen.json(
            Dict("error" => "unknown active investigation"); status = 404)
        Oxygen.json(PerfChecker.investigation_status(job))
    end
    Oxygen.post(api("/launch")) do request
        guarded(request) || return denied()
        try
            payload = _query_request_payload(request)
            action = Symbol(get(payload, "action", ""))
            setup_running() &&
                throw(ArgumentError("Wait for the advisor setup operation or cancel it first."))
            action in (:discover, :run, :diagnose, :sync, :tools, :narrate, :investigate) ||
                throw(ArgumentError("unsupported action"))
            chosen = current_catalog()
            if action in (:run, :diagnose, :investigate)
                chosen = PerfChecker.select_scenarios(chosen, get(payload, "selection", []))
                isempty(chosen.scenarios) &&
                    throw(ArgumentError("select declared scenarios first"))
            end
            count = Int(get(payload, "samples", 10))
            timeout = Float64(get(payload, "timeout", 120))
            threads = Int(get(payload, "threads", 1))
            1 <= count <= 10000 && 1 <= timeout <= 3600 &&
                1 <= threads <= max(Sys.CPU_THREADS, 1) ||
                throw(ArgumentError("invalid measurement limits"))
            tools = Symbol.(get(payload, "tools", ["jet", "latency"]))
            action == :diagnose && isempty(tools) &&
                throw(ArgumentError("select at least one analyzer"))
            all(t -> haskey(PerfChecker._SCENARIO_ANALYZERS, t), tools) ||
                throw(ArgumentError("unknown analyzer"))
            evidence = nothing
            if action == :narrate
                advisor === nothing &&
                    throw(ArgumentError("Configure an advisor in Conseiller et modèles."))
                source_directory, _ = saved(String(get(payload, "evidence_id", "")))
                evidence = PerfChecker._json_parsefile(joinpath(
                    source_directory, "advice", "advice.json"))
            end
            max_experiments = Int(get(payload, "max_experiments", 4))
            budget_seconds = Float64(get(payload, "budget_seconds", 300))
            1 <= max_experiments <= 100 && 1 <= budget_seconds <= 86400 ||
                throw(ArgumentError("invalid investigation budget"))
            return lock(mutex) do
                any(
                    job -> PerfChecker.investigation_status(job; include_result = false)["status"] ==
                           "running",
                    values(jobs)) &&
                    return Oxygen.json(
                        Dict("error" => "an investigation is already running");
                        status = 409)
                if length(jobs) >= 128
                    oldest = first(sort!(collect(keys(jobs)); by = id -> jobs[id].started))
                    delete!(jobs, oldest)
                end
                id = string(PerfChecker.uuid4())
                directory = joinpath(store, id)
                job = PerfChecker.launch_investigation(
                    action; root = catalog.root, catalog = chosen,
                    project, tools, samples = count, timeout, threads, reports = directory,
                    advisor = action == :narrate || setup_options["investigates"] ?
                              advisor : nothing,
                    evidence, max_experiments, budget_seconds)
                job.id = id
                jobs[id] = job
                @async begin
                    PerfChecker.wait_investigation(job)
                    mkpath(directory)
                    PerfChecker._write_json(joinpath(directory, "job.json"),
                        PerfChecker.investigation_status(job; include_result = false); canonical = true)
                end
                Oxygen.json(PerfChecker.investigation_status(job; include_result = false);
                    status = 202)
            end
        catch error
            failure(error)
        end
    end
    Oxygen.post(api("/cancel")) do request
        guarded(request) || return denied()
        payload = _query_request_payload(request)
        job = lock(mutex) do
            get(jobs, get(payload, "id", ""), nothing)
        end
        job === nothing &&
            return Oxygen.json(Dict("error" => "unknown investigation"); status = 404)
        PerfChecker.cancel!(job)
        Oxygen.json(PerfChecker.investigation_status(job; include_result = false))
    end
    Oxygen.get(api("/evidence")) do request
        try
            params = Oxygen.queryparams(request)
            directory, payload = saved(String(get(params, "id", "")))
            advice = get(params, "advice", "false") == "true"
            advice && (payload = PerfChecker._json_parsefile(joinpath(
                directory, "advice", "advice.json")))
            format = get(params, "format", "html")
            format == "json" && return Oxygen.json(payload)
            if format == "markdown"
                basename = advice ? joinpath("advice", "advice.md") :
                           payload["schema_version"] == PerfChecker.DISCOVERY_SCHEMA ?
                           "discovery.md" :
                           payload["schema_version"] == "perfchecker-scenario-run/1" ?
                           "run.md" :
                           get(
                    Dict("perfchecker-tool-catalog/1" => "tools.md",
                        "perfchecker-scenario-sync/1" => "sync.md",
                        "perfchecker-narrative/1" => "narrative.md", "perfchecker-investigation/1" => "investigation.md"),
                    payload["schema_version"],
                    "diagnosis.md")
                isfile(joinpath(directory, basename)) ||
                    throw(ArgumentError("Markdown is unavailable for this saved report"))
                return HTTP.Response(
                    200, ["Content-Type" => "text/markdown; charset=utf-8"],
                    read(joinpath(directory, basename), String))
            end
            html = sprint(show, MIME"text/html"(), PerfChecker.investigation_view(payload))
            if !advice
                artifacts = [a for r in get(payload, "records", [])
                             for a in get(r, "artifacts", [])]
                for (index, artifact) in enumerate(artifacts)
                    url = "$base/artifact?id=$(get(params, "id", ""))&index=$index"
                    html *= "<p><a download href=\"$(_html_escape(url))\">Download $(_html_escape(get(artifact, "kind", "artifact")))</a></p>"
                end
            end
            Oxygen.html(html; headers)
        catch error
            failure(error)
        end
    end
    Oxygen.get(api("/artifact")) do request
        try
            params = Oxygen.queryparams(request)
            directory, payload = saved(String(get(params, "id", "")))
            artifacts = [a for r in get(payload, "records", [])
                         for a in get(r, "artifacts", [])]
            index = parse(Int, String(get(params, "index", "0")))
            1 <= index <= length(artifacts) ||
                throw(ArgumentError("unknown recorded artifact"))
            artifact = artifacts[index]
            file = realpath(artifact["path"])
            relative = relpath(file, realpath(directory))
            (isabspath(relative) || first(splitpath(relative)) == "..") &&
                throw(ArgumentError("artifact is outside its saved investigation"))
            bytes2hex(open(PerfChecker.SHA.sha256, file)) == get(artifact, "sha256", "") ||
                throw(ArgumentError("artifact changed since its diagnosis"))
            HTTP.Response(200,
                ["Content-Type" => "application/octet-stream",
                    "Content-Disposition" => "attachment; filename=after-operation.heapsnapshot",
                    "X-Content-Type-Options" => "nosniff",
                    "Content-Length" => string(filesize(file))],
                _investigation_artifact_body(file))
        catch error
            failure(error)
        end
    end
    Oxygen.post(api("/advise")) do request
        guarded(request) || return denied()
        try
            payload = _query_request_payload(request)
            directory, evidence = saved(String(get(payload, "id", "")))
            advice = haskey(evidence, "advice") ? evidence["advice"] :
                     haskey(evidence, "fallback") ? evidence["fallback"] :
                     evidence["schema_version"] == PerfChecker.DIAGNOSIS_SCHEMA ?
                     PerfChecker.advise(evidence) :
                     PerfChecker.advise(
                Dict("schema_version" => PerfChecker.DIAGNOSIS_SCHEMA, "records" => []);
                bundles = PerfChecker.read_scenario_runs(joinpath(directory, "bundles")))
            PerfChecker.write_investigation_report(
                advice, joinpath(directory, "advice"); force = true)
            Oxygen.json(advice)
        catch error
            failure(error)
        end
    end
    Oxygen.post(api("/compare")) do request
        guarded(request) || return denied()
        try
            payload = _query_request_payload(request)
            baseline, _ = saved(String(get(payload, "baseline", "")))
            candidate, _ = saved(String(get(payload, "candidate", "")))
            result = PerfChecker.compare_scenarios(
                PerfChecker.read_scenario_runs(joinpath(baseline, "bundles")),
                PerfChecker.read_scenario_runs(joinpath(candidate, "bundles")))
            PerfChecker.write_investigation_report(
                result, joinpath(store, "comparison-" * string(PerfChecker.uuid4())))
            Oxygen.html(
                sprint(show, MIME"text/html"(), PerfChecker.investigation_view(result));
                headers)
        catch error
            failure(error)
        end
    end
    return api
end

function PerfChecker.serve_suite(catalog::PerfChecker.ScenarioCatalog;
        host::AbstractString = "127.0.0.1", port::Integer = 8080, async::Bool = false,
        prefix::AbstractString = "/perfchecker/scenarios", project::AbstractString = catalog.root,
        catalog_path = nothing, advisor = nothing,
        reports_root::AbstractString = joinpath(
            catalog.root, "perf", "results", "investigations"))
    lowercase(String(host)) in ("127.0.0.1", "localhost", "::1") ||
        throw(ArgumentError("the scenario studio is restricted to loopback"))
    PerfChecker.register_oxygen_routes!(
        catalog; prefix, project, catalog_path, advisor, reports_root)
    return Oxygen.serve(; host = String(host), port = Int(port), async)
end
