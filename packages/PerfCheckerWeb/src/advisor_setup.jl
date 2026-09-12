function _register_advisor_setup(api, base, token, guarded, denied, failure, headers,
        project, store, get_settings, save_settings, is_running)
    active = Ref{Any}(nothing)
    setup_lock = ReentrantLock()
    Oxygen.get(api("/advisor")) do
        Oxygen.html(
            """<!doctype html><html lang="fr"><head><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>Conseiller et modèles · PerfChecker</title><link rel="stylesheet" href="$base/assets/investigations.css"><link rel="stylesheet" href="$base/assets/advisor-panel.css"></head><body data-api="$base" data-token="$token"><a href="$base/">Retour aux investigations</a><main id="advisor-root"></main><script src="$base/assets/advisor-panel.js"></script><script src="$base/assets/advisor-web.js"></script></body></html>""";
            headers)
    end
    for (file, format) in (
        ("advisor-panel.js", :js), ("advisor-web.js", :js), ("advisor-panel.css", :css))
        Oxygen.get(api("/assets/" * file)) do
            content = read(joinpath(_STUDIO_ASSET_ROOT, file), String)
            format == :js ? Oxygen.js(content) : Oxygen.css(content)
        end
    end
    Oxygen.get(api("/advisor-settings")) do request
        guarded(request) || return denied()
        Oxygen.json(get_settings())
    end
    Oxygen.post(api("/advisor-action")) do request
        guarded(request) || return denied()
        try
            sizeof(request.body) <= 32000 ||
                throw(ArgumentError("Setup request exceeds 32 KB."))
            input = _query_request_payload(request)
            action = Symbol(get(input, "action", ""))
            action in (:save, :probe, :models, :pull, :delete, :unload) ||
                throw(ArgumentError("Unknown setup action."))
            lock(setup_lock) do
                is_running() &&
                    throw(ArgumentError("Wait for the current investigation before configuring its advisor."))
                active[] !== nothing &&
                    PerfChecker.investigation_status(active[])["status"] == "running" &&
                    throw(ArgumentError("A setup operation is already running."))
                if action == :save
                    save_settings(input)
                    return Oxygen.json(Dict("status" => "complete",
                        "message" => "Configuration enregistrée pour ce studio. Aucun appel de génération effectué."))
                end
                config = input["config"]
                config isa AbstractDict ||
                    throw(ArgumentError("Choose an optional provider first."))
                active[] = PerfChecker.launch_advisor_setup(
                    config; action, model = get(input, "model", ""),
                    confirmed = get(input, "confirmed", false), project)
                Oxygen.json(PerfChecker.investigation_status(active[]); status = 202)
            end
        catch error
            failure(error)
        end
    end
    Oxygen.get(api("/advisor-job")) do request
        guarded(request) || return denied()
        lock(setup_lock) do
            active[] === nothing && return Oxygen.json(Dict("status" => "idle"))
            Oxygen.json(PerfChecker.investigation_status(active[]))
        end
    end
    Oxygen.post(api("/advisor-cancel")) do request
        guarded(request) || return denied()
        lock(setup_lock) do
            active[] === nothing || PerfChecker.cancel!(active[])
            Oxygen.json(Dict("status" => "cancelling"))
        end
    end
    () -> active[] !== nothing &&
        PerfChecker.investigation_status(active[])["status"] == "running"
end
