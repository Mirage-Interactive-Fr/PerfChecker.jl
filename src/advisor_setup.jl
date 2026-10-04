"Validate a setup draft, optionally before an MCP advice tool has been selected."
function _advisor_draft(input::AbstractDict; discovery = false)
    values = Dict{String, Any}(string(k) => v for (k, v) in input)
    if discovery && get(values, "protocol", "") == "mcp_http" &&
       isempty(get(values, "mcp_tool", ""))
        values["mcp_tool"] = "_discovery_only"
    end
    AdvisorConfig(; (Symbol(k) => v for (k, v) in values)...)
end

"Extension point for optional connection checks and local model management."
advisor_setup_transport(config, action, model) = throw(ArgumentError("Setup is unavailable for this provider; install HTTP in the controller environment."))

"""
    advisor_setup(configuration; action=:probe, model="", confirmed=false, project, cancellation)

Check a connection or discover available models/MCP tools without sending project
evidence. Ollama `:pull`, `:delete`, and `:unload` require explicit confirmation
and a loopback endpoint. Operations run in a cancellable worker. Model files are
managed by the existing Ollama server, never bundled with PerfChecker.
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
    Base.require(Main, :HTTP)
    try
        Base.invokelatest(advisor_setup_transport, config,
            Symbol(request["setup_action"]), request["setup_model"])
    catch error
        Dict("status" => "error",
            "message" => error isa ArgumentError ? error.msg :
                         "Connection failed. Check the server address, authentication environment variable and protocol version.")
    end
end

"Start a cancellable setup task for web/Pluto clients. Opening a view never calls this."
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
