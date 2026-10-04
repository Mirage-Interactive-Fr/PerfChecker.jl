# Read-only discovery never sends evidence or invokes a model/tool.
function setup_http(config, method, endpoint; body = nothing, empty_ok = false)
    headers = ["Content-Type" => "application/json"]
    result = Ref{Any}()
    if !isempty(config.api_key_env)
        secret = get(ENV, config.api_key_env, "")
        isempty(secret) &&
            throw(ArgumentError("The configured credential environment variable is absent."))
        push!(headers, "Authorization" => "Bearer " * secret)
    end
    HTTP.open(method, endpoint, headers; retry = false, redirect = false,
        status_exception = false, readtimeout = ceil(Int, config.timeout),
        connect_timeout = ceil(Int, min(config.timeout, 10))) do stream
        write(
            stream, body === nothing ? "" : sprint(io -> PerfChecker.JSON.print(io, body)))
        HTTP.closewrite(stream)
        response = HTTP.startread(stream)
        result[] = (response.status, read_advisor_bytes(stream, 1_000_000))
    end
    # Validate outside the callback: HTTP 1 wraps callback errors in RequestError.
    status, bytes = result[]
    status == 200 ||
        throw(ArgumentError("Provider returned HTTP $status. Check its address and authentication."))
    length(bytes) <= 1_000_000 ||
        throw(ArgumentError("Provider inventory exceeds the display limit."))
    return empty_ok && isempty(bytes) ? Dict() : PerfChecker._json_parse(String(bytes))
end

function setup_mcp_tools(config)
    session = ""
    try
        if config.mcp_version == "2025-11-25"
            result, session = mcp_post(config,
                mcp_request(config, "initialize", 1,
                    Dict("protocolVersion" => config.mcp_version, "capabilities" => Dict(),
                        "clientInfo" => Dict("name" => "PerfChecker", "version" => "1.0.0"))))
            get(result, "protocolVersion", "") == config.mcp_version ||
                throw(ArgumentError("Unsupported MCP version selected by server."))
            haskey(get(result, "capabilities", Dict()), "tools") ||
                throw(ArgumentError("This MCP server exposes no tools."))
            mcp_post(
                config, Dict("jsonrpc" => "2.0", "method" => "notifications/initialized");
                session, notification = true)
        end
        entries, cursor, seen = Any[], nothing, Set{String}()
        for page in 1:32
            params = cursor === nothing ? Dict{String, Any}() :
                     Dict{String, Any}("cursor" => cursor)
            result, _ = mcp_post(
                config, mcp_request(config, "tools/list", page + 1, params); session)
            rows = get(result, "tools", nothing)
            rows isa AbstractVector || throw(ArgumentError("Invalid MCP tool inventory."))
            for row in rows
                name = get(row, "name", "")
                name isa String && occursin(r"^[A-Za-z0-9_.-]{1,128}$", name) &&
                    !(name in seen) ||
                    throw(ArgumentError("Invalid or duplicate MCP tool name."))
                push!(seen, name)
                push!(entries,
                    Dict("name" => name,
                        "description" => first(string(get(row, "description", "")), 2000),
                        "inputSchema" => get(row, "inputSchema", Dict()), "annotations" => get(
                            row, "annotations", Dict())))
            end
            length(entries) <= 1024 ||
                throw(ArgumentError("Too many MCP tools to display."))
            cursor = get(result, "nextCursor", nothing)
            cursor === nothing && return entries
            cursor isa String || throw(ArgumentError("Invalid MCP catalogue cursor."))
        end
        throw(ArgumentError("MCP inventory exceeds 32 pages."))
    finally
        if !isempty(session)
            headers = [
                "Mcp-Session-Id" => session, "MCP-Protocol-Version" => config.mcp_version]
            isempty(config.api_key_env) || push!(headers,
                "Authorization" => "Bearer " * get(ENV, config.api_key_env, ""))
            try
                HTTP.request(
                    "DELETE", config.endpoint, headers; retry = false, redirect = false,
                    status_exception = false, readtimeout = 2, connect_timeout = 2)
            catch
            end
        end
    end
end

function PerfChecker.advisor_setup_transport(
        config::PerfChecker.AdvisorConfig, action::Symbol, model::String)
    if config.protocol == :mcp_http
        action in (:probe, :models) ||
            throw(ArgumentError("MCP tools cannot manage local model files."))
        entries = setup_mcp_tools(config)
        selected = any(t -> t["name"] == config.mcp_tool, entries)
        return Dict(
            "status" => "complete", "tools" => entries, "selected_available" => selected,
            "message" => "MCP connected. Select a tool that answers prompts. No tool was called.")
    elseif config.protocol == :ollama
        endswith(config.endpoint, "/api/chat") ||
            throw(ArgumentError("Use the Ollama /api/chat endpoint."))
        base = chop(config.endpoint; tail = length("/api/chat"))
        if action in (:probe, :models)
            payload = setup_http(config, "GET", base * "/api/tags")
            models = [Dict(
                          "name" => row["name"], "size_bytes" => get(row, "size", nothing),
                          "digest" => get(row, "digest", "")) for row in payload["models"]]
            return Dict("status" => "complete", "models" => models,
                "selected_available" => any(r -> r["name"] == config.model, models),
                "message" => "Ollama connected. Sizes include shared layers; their sum is not unique disk usage. Free disk space is not reported by this API.")
        elseif action == :pull
            result = setup_http(config, "POST", base * "/api/pull";
                body = Dict("model" => model, "stream" => false))
            get(result, "status", "") == "success" ||
                throw(ArgumentError("The download did not report success. Refresh installed models."))
        elseif action == :delete
            setup_http(config, "DELETE", base * "/api/delete";
                body = Dict("model" => model), empty_ok = true)
        elseif action == :unload
            setup_http(config, "POST", base * "/api/generate";
                body = Dict("model" => model, "keep_alive" => 0, "stream" => false))
        else
            throw(ArgumentError("Unsupported Ollama action."))
        end
        return Dict("status" => "complete",
            "message" => action == :pull ?
                         "Download completed. Refresh the inventory to see its size." :
                         action == :delete ?
                         "Model removed from Ollama. Shared layers may remain in use by other models." :
                         "Model unloaded from memory; its files remain installed.")
    elseif config.protocol in (:chat_completions, :chat_completions_schema)
        action in (:probe, :models) ||
            throw(ArgumentError("File management is only available for local Ollama."))
        endswith(config.endpoint, "/chat/completions") ||
            throw(ArgumentError("Use a Chat Completions endpoint ending in /chat/completions."))
        endpoint = chop(config.endpoint; tail = length("chat/completions")) * "models"
        payload = setup_http(config, "GET", endpoint)
        models = [Dict("name" => row["id"]) for row in payload["data"]]
        return Dict("status" => "complete", "models" => models,
            "selected_available" => any(r -> r["name"] == config.model, models),
            "message" => "Model inventory connected. Generation and answer quality have not been tested.")
    end
    throw(ArgumentError("This custom provider has no setup interface. Keep using its configuration file."))
end
