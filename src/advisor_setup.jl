"Validate a setup draft, optionally before an MCP advice tool has been selected."
function _advisor_draft(input::AbstractDict; discovery = false)
    values = Dict{String, Any}(string(k) => v for (k, v) in input)
    if discovery && get(values, "protocol", "") == "mcp_http" &&
       isempty(get(values, "mcp_tool", ""))
        values["mcp_tool"] = "_discovery_only"
    end
    AdvisorConfig(; (Symbol(k) => v for (k, v) in values)...)
end

"""
    advisor_setup_transport(config, action, model)

Provider extension hook called in a setup worker by [`advisor_setup`](@ref).
The HTTP advisor extension implements connection probes, model/tool listings
and authorized local Ollama management, returning a status dictionary.
The base fallback throws `ArgumentError` when no provider method is available.
Call the public worker API for timeout/cancellation and confirmation validation;
direct invocation does not provide that lifecycle boundary.
"""
advisor_setup_transport(config, action, model) = throw(ArgumentError("Setup is unavailable for this provider; install HTTP in the controller environment."))

"""
    advisor_setup(configuration; action=:probe, model="", confirmed=false,
                  project=dirname(Base.active_project()), cancellation=CancellationToken())

Check a connection or discover available models/MCP tools without sending project
evidence. Ollama `:pull`, `:delete`, and `:unload` require explicit confirmation
and a loopback endpoint. Operations run in a cancellable worker. Model files are
managed by the existing Ollama server, never bundled with PerfChecker.
Accept an `AdvisorConfig` or draft dictionary. `:validate` returns validated
configuration immediately without contacting a provider; `:probe`/`:models`
allow an MCP discovery draft with no selected tool. Return a status dictionary,
with worker results labelled `perfchecker-advisor-setup/1`, `evidence_sent=false`
and `generation_tested=false`. MCP probes use the explicitly configured version:
2026 discovery reads `server/discover` before listing tools; 2025 uses `initialize`.
The `server` result contains the selected protocol, advertised versions, bounded
server identity and known capabilities. These are self-reported display metadata,
not trusted authorization or a guarantee that a tool can generate advice.
Missing provider packages can be unavailable;
connection errors become diagnostic results. Invalid actions, model names or
unconfirmed/nonlocal management raise `ArgumentError` before execution.
Cancellation stops the worker; partial provider-owned downloads may remain.
"""
function advisor_setup(input::Union{AdvisorConfig, AbstractDict}; action::Symbol = :probe,
        model::AbstractString = "", confirmed::Bool = false,
        project::AbstractString = dirname(Base.active_project()), cancellation = CancellationToken())
    action in (:validate, :probe, :models, :pull, :delete, :unload) ||
        throw(ArgumentError("unknown advisor setup action"))
    config = input isa AdvisorConfig ? input :
             _advisor_draft(input; discovery = action in (:probe, :models))
    if action in (:pull, :delete, :unload)
        confirmed || throw(ArgumentError("confirm the selected model operation explicitly"))
        config.protocol == :ollama &&
            occursin(r"^https?://(localhost|127\.0\.0\.1|\[::1\])(?::[0-9]+)?/",
                config.endpoint) ||
            throw(ArgumentError("model management is limited to a local Ollama server"))
        occursin(r"^[A-Za-z0-9][A-Za-z0-9._:/-]{0,199}$", model) &&
            !occursin("..", model) ||
            throw(ArgumentError("invalid model name"))
    end
    action == :validate &&
        return Dict("status" => "complete", "config" => _advisor_config(config))
    result = _scenario_process(
        Dict("config" => _advisor_config(config),
            "setup_action" => string(action), "setup_model" => String(model));
        project, timeout = config.timeout, cancellation, advisor = true, threads = 1)
    merge(result,
        Dict("schema_version" => "perfchecker-advisor-setup/1", "action" => string(action),
            "evidence_sent" => false, "generation_tested" => false))
end

function _advisor_setup_inprocess(config, request)
    Base.find_package("HTTP") === nothing && return Dict("status" => "unavailable",
        "message" => "Install HTTP in the PerfChecker controller environment to connect a provider.")
    _advisor_phase(:provider_loading)
    Base.require(Main, :HTTP)
    _advisor_phase(:provider_loaded)
    try
        _advisor_phase(:transport)
        Base.invokelatest(advisor_setup_transport, config,
            Symbol(request["setup_action"]), request["setup_model"])
    catch error
        Dict("status" => "error",
            "message" => error isa ArgumentError ? error.msg :
                         "Connection failed. Check the server address, authentication environment variable and protocol version.")
    end
end

"""
    launch_advisor_setup(input; kwargs...)

Start [`advisor_setup`](@ref) asynchronously and return an `InvestigationJob`
with action `:advisor_setup`. Forward setup keywords and use the job's own
cancellation token. Inspect with [`investigation_status`](@ref), wait with
[`wait_investigation`](@ref), or request cancellation with [`cancel!`](@ref).
Setup errors are retained in the job as `status=:error`; successful worker
status/result is copied to the job. Calling this explicitly starts setup;
constructing or displaying an investigation view does not.
"""
function launch_advisor_setup(input; kwargs...)
    job = InvestigationJob(
        string(uuid4()), :advisor_setup, CancellationToken(), nothing, :running,
        nothing, nothing, "", time(), nothing, ReentrantLock())
    job.task = @async begin
        try
            result = advisor_setup(input; cancellation = job.cancellation, kwargs...)
            lock(job.lock) do
                job.result = result
                job.status = Symbol(result["status"])
                job.finished = time()
            end
        catch error
            lock(job.lock) do
                job.status = :error
                job.error = sprint(showerror, error)
                job.finished = time()
            end
        end
    end
    job
end
