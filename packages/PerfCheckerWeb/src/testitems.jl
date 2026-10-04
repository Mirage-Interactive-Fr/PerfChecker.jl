function PerfChecker.register_testitem_routes!(root::AbstractString;
        prefix::AbstractString = "/perfchecker/items",
        project::AbstractString = dirname(Base.active_project()),
        reports_root::AbstractString = joinpath(root, "perf", "results", "testitems"))
    Base.get_extension(PerfChecker, :TestItemRunnerExt) === nothing &&
        throw(ArgumentError("load TestItemRunner before registering test item routes"))
    occursin(r"^/[A-Za-z0-9_/-]+$", prefix) || throw(ArgumentError("invalid route prefix"))
    root, project, reports_root = abspath(root), abspath(project), abspath(reports_root)
    base = String(rstrip(String(prefix), '/'))
    api = Oxygen.router(base; tags = ["PerfChecker test items"])
    token = string(PerfChecker.uuid4())
    mutex = ReentrantLock()
    state = Dict{String, Any}("status" => "idle")
    cancellation = Ref(PerfChecker.CancellationToken())
    guard(req) = HTTP.header(req, "X-PerfChecker-CSRF", "") == token
    Oxygen.get(api("/")) do
        Oxygen.html(
            """<!doctype html><html lang="en"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>PerfChecker test items</title><link rel="stylesheet" href="$base/assets/items.css">
<body data-token="$token"><main><h1>Existing test items</h1><p>The same tests, with time and allocation measurements. No duplicate workload.</p>
<p>Includes shared and perf_only items. Excludes test_only. Each item runs once.</p>
<button id="refresh">Refresh items</button><button id="run">Measure selected</button><button id="cancel" disabled>Cancel</button>
<p id="status" role="status">Ready</p><div id="items"></div><h2>Results</h2><div id="results" aria-live="polite"></div>
</main><script src="$base/assets/items.js"></script></body></html>""";
            headers = ["Cache-Control" => "no-store",
                "Content-Security-Policy" => "default-src 'self'; object-src 'none'; base-uri 'none'; frame-ancestors 'none'"])
    end
    Oxygen.get(api("/assets/items.js")) do
        Oxygen.js(read(joinpath(_STUDIO_ASSET_ROOT, "testitems.js"), String))
    end
    Oxygen.get(api("/assets/items.css")) do
        Oxygen.css("body{font:16px system-ui;background:#121821;color:#e8eef5;margin:0}main{max-width:960px;margin:3rem auto;padding:0 1.5rem}button{font:inherit;padding:.6rem 1rem;margin:.3rem;border-radius:6px;cursor:pointer}label,article{display:block;padding:1rem;margin:.5rem 0;background:#202c3b;border-radius:6px}input{margin-right:.8rem}small{display:block;color:#afc0d5;margin-top:.4rem}button:disabled{opacity:.5}")
    end
    Oxygen.get(api("/items")) do
        Oxygen.json(Base.invokelatest(PerfChecker.discover_testitems, root))
    end
    Oxygen.get(api("/state")) do
        Oxygen.json(lock(() -> deepcopy(state), mutex))
    end
    Oxygen.post(api("/cancel")) do request
        guard(request) || return Oxygen.json(Dict("error" => "invalid token"); status = 403)
        lock(mutex) do
            PerfChecker.cancel!(cancellation[])
        end
        Oxygen.json(Dict("status" => "cancellation_requested"))
    end
    Oxygen.post(api("/run")) do request
        guard(request) || return Oxygen.json(Dict("error" => "invalid token"); status = 403)
        try
            payload = _query_request_payload(request)
            ids = String.(get(payload, "ids", String[]))
            !isempty(ids) && allunique(ids) ||
                throw(ArgumentError("select distinct test items"))
            listing = Base.invokelatest(PerfChecker.discover_testitems, root)
            known = Set(i["id"] for i in listing["items"])
            all(id -> id in known, ids) ||
                throw(ArgumentError("unknown or excluded test item"))
            return lock(mutex) do
                state["status"] == "running" &&
                    return Oxygen.json(Dict("error" => "a run is active"); status = 409)
                empty!(state)
                state["status"] = "running"
                cancellation[] = PerfChecker.CancellationToken()
                captured_token = cancellation[]
                directory = joinpath(reports_root, string(PerfChecker.uuid4()))
                @async begin
                    completed = try
                        result = Base.invokelatest(PerfChecker.run_testitems, root;
                            ids, project, reports = directory, cancellation = captured_token)
                        Dict(
                            "status" => captured_token.requested[] ? "cancelled" :
                                        "complete",
                            "result" => result)
                    catch error
                        Dict("status" => "error",
                            "message" => first(sprint(showerror, error), 2048))
                    end
                    lock(mutex) do
                        empty!(state)
                        merge!(state, completed)
                    end
                end
                Oxygen.json(Dict("status" => "running"); status = 202)
            end
        catch error
            Oxygen.json(
                Dict("error" => first(sprint(showerror, error), 2048)); status = 400)
        end
    end
    api
end
