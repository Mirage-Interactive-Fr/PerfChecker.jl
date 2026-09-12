# Optional advice-tool client. No roots, sampling, shell execution or autonomous
# tool discovery/calling is granted to the server. The chosen tool is explicit.
const MCP_MAX_BYTES = 1_000_000

function mcp_response(value, id)
    value isa AbstractDict && get(value, "jsonrpc", nothing) == "2.0" ||
        throw(ArgumentError("invalid MCP JSON-RPC response"))
    # Request-related notifications can precede the response in an SSE stream.
    if haskey(value, "method")
        !haskey(value, "id") ||
            throw(ArgumentError("MCP server requested unsupported client interaction"))
        return nothing
    end
    response_id = get(value, "id", nothing)
    typeof(response_id) == typeof(id) && response_id == id ||
        throw(ArgumentError("MCP response ID mismatch"))
    haskey(value, "error") && throw(ArgumentError("MCP request failed: " *
                        string(get(value["error"], "code", "unknown"))))
    result = get(value, "result", nothing)
    result isa AbstractDict || throw(ArgumentError("MCP response has no result object"))
    haskey(result, "inputRequests") &&
        throw(ArgumentError("MCP tool requires unsupported sampling, elicitation or roots"))
    result
end

function mcp_read(stream, content_type, id)
    if startswith(lowercase(content_type), "application/json")
        bytes = read_advisor_bytes(stream, MCP_MAX_BYTES)
        length(bytes) <= MCP_MAX_BYTES || throw(ArgumentError("MCP response exceeds limit"))
        result = mcp_response(PerfChecker._json_parse(String(bytes)), id)
        result === nothing &&
            throw(ArgumentError("MCP returned a notification instead of a result"))
        return result
    end
    startswith(lowercase(content_type), "text/event-stream") ||
        throw(ArgumentError("unsupported MCP response content type"))
    # Read incrementally: a server need not close immediately after its result.
    line, data = UInt8[], String[]
    count = 0
    while !eof(stream)
        byte = read(stream, UInt8)
        count += 1
        count <= MCP_MAX_BYTES || throw(ArgumentError("MCP stream exceeds limit"))
        if byte != 0x0a
            push!(line, byte)
            continue
        end
        !isempty(line) && last(line) == 0x0d && pop!(line)
        text = String(copy(line))
        empty!(line)
        if isempty(text) && !isempty(data)
            result = mcp_response(PerfChecker._json_parse(join(data, "\n")), id)
            empty!(data)
            result === nothing || return result
        elseif startswith(text, "data:")
            value = text[6:end]
            startswith(value, " ") && (value = value[2:end])
            push!(data, value)
        end
    end
    throw(ArgumentError("MCP stream ended without a result"))
end

function mcp_post(config, message; session = "", notification = false,
        extra_headers = Pair{String, String}[])
    headers = ["Content-Type" => "application/json",
        "Accept" => "application/json, text/event-stream",
        "MCP-Protocol-Version" => config.mcp_version]
    isempty(session) || push!(headers, "Mcp-Session-Id" => session)
    if config.mcp_version == "2026-07-28"
        push!(headers, "Mcp-Method" => message["method"])
        params = message["params"]
        haskey(params, "name") && push!(headers, "Mcp-Name" => params["name"])
    end
    append!(headers, extra_headers)
    if !isempty(config.api_key_env)
        key = get(ENV, config.api_key_env, "")
        isempty(key) && throw(ArgumentError("configured credential is absent"))
        push!(headers, "Authorization" => "Bearer " * key)
    end
    output, received_session = Ref{Any}(), Ref("")
    HTTP.open("POST", config.endpoint, headers; retry = false, redirect = false,
        readtimeout = ceil(Int, config.timeout), connect_timeout = ceil(
            Int, min(config.timeout, 10)),
        status_exception = false) do stream
        write(stream, sprint(io -> PerfChecker.JSON.print(io, message)))
        HTTP.closewrite(stream)
        response = HTTP.startread(stream)
        response.status == (notification ? 202 : 200) ||
            throw(ArgumentError("MCP endpoint returned HTTP $(response.status); check protocol version and authentication"))
        received_session[] = HTTP.header(response, "Mcp-Session-Id", "")
        session_value = received_session[]
        length(session_value) <= 1024 && all(c -> 0x21 <= Int(c) <= 0x7e, session_value) ||
            throw(ArgumentError("invalid MCP session identifier"))
        output[] = notification ? nothing :
                   mcp_read(
            stream, HTTP.header(response, "Content-Type", ""), message["id"])
    end
    output[], received_session[]
end

function mcp_request(config, method, id, params = Dict{String, Any}())
    params = Dict{String, Any}(params)
    if config.mcp_version == "2026-07-28"
        params["_meta"] = Dict(
            "io.modelcontextprotocol/protocolVersion" => config.mcp_version,
            "io.modelcontextprotocol/clientInfo" => Dict(
                "name" => "PerfChecker", "version" => "1.0.0"),
            "io.modelcontextprotocol/clientCapabilities" => Dict())
    end
    Dict("jsonrpc" => "2.0", "id" => id, "method" => method, "params" => params)
end

function mcp_tool_headers(schema, arguments)
    # Modern MCP requires mirroring annotated tool arguments into HTTP headers.
    # Reject unsupported annotations instead of sending a nonconforming request.
    headers = Pair{String, String}[]
    names = Set{String}()
    function walk(node, values; reachable = true)
        node isa AbstractDict || return
        if haskey(node, "x-mcp-header")
            name = node["x-mcp-header"]
            reachable && name isa AbstractString &&
                occursin(r"^[!#$%&'*+.^_`|~0-9A-Za-z-]+$", name) ||
                throw(ArgumentError("unsupported MCP header annotation"))
            lowercase(name) in names &&
                throw(ArgumentError("duplicate MCP header annotation"))
            push!(names, lowercase(name))
            get(node, "type", "") in ("string", "integer", "boolean") ||
                throw(ArgumentError("invalid MCP header parameter type"))
            if values !== nothing
                (values isa AbstractString || values isa Bool ||
                 (values isa Integer && abs(big(values)) <= 9007199254740991)) ||
                    throw(ArgumentError("invalid MCP header parameter value"))
                text = string(values)
                plain = strip(text) == text &&
                        all(c -> c == '\t' || 0x20 <= Int(c) <= 0x7e, text) &&
                        !(startswith(text, "=?base64?") && endswith(text, "?="))
                encoded = plain ? text : "=?base64?" * base64encode(text) * "?="
                push!(headers, "Mcp-Param-" * name => encoded)
            end
        end
        for (key, value) in node
            if key == "properties" && value isa AbstractDict
                for (property, child) in value
                    walk(child,
                        values isa AbstractDict ? get(values, property, nothing) : nothing;
                        reachable)
                end
            elseif value isa AbstractDict
                walk(value, nothing; reachable = false)
            elseif value isa AbstractVector
                for child in value
                    walk(child, nothing; reachable = false)
                end
            end
        end
    end
    walk(schema, arguments)
    headers
end

function PerfChecker.advisor_transport(
        ::Val{:mcp_http}, config::PerfChecker.AdvisorConfig, body::AbstractDict)
    session = ""
    try
        if config.mcp_version == "2025-11-25"
            initialized, session = mcp_post(config,
                mcp_request(config, "initialize", 1,
                    Dict("protocolVersion" => config.mcp_version, "capabilities" => Dict(),
                        "clientInfo" => Dict("name" => "PerfChecker", "version" => "1.0.0"))))
            get(initialized, "protocolVersion", "") == config.mcp_version ||
                throw(ArgumentError("MCP server selected an unsupported version"))
            haskey(get(initialized, "capabilities", Dict()), "tools") ||
                throw(ArgumentError("MCP server does not expose tools"))
            mcp_post(
                config, Dict("jsonrpc" => "2.0", "method" => "notifications/initialized");
                session, notification = true)
        end
        selected, cursor = nothing, nothing
        for page in 1:32
            params = cursor === nothing ? Dict{String, Any}() :
                     Dict{String, Any}("cursor" => cursor)
            catalog, _ = mcp_post(
                config, mcp_request(config, "tools/list", page + 1, params); session)
            tools = get(catalog, "tools", nothing)
            tools isa AbstractVector || throw(ArgumentError("invalid MCP tool catalogue"))
            matches = filter(
                t -> t isa AbstractDict && get(t, "name", "") == config.mcp_tool, tools)
            length(matches) <= 1 || throw(ArgumentError("duplicate selected MCP tool"))
            if !isempty(matches)
                selected = only(matches)
                break
            end
            cursor = get(catalog, "nextCursor", nothing)
            cursor === nothing && break
            cursor isa AbstractString ||
                throw(ArgumentError("invalid MCP catalogue cursor"))
        end
        selected === nothing &&
            throw(ArgumentError("selected MCP advice tool is unavailable"))
        arguments = copy(config.mcp_arguments)
        arguments[config.mcp_prompt_argument] = join(
            (message["content"] for message in body["messages"]), "\n\nPerfChecker evidence:\n")
        schema = get(selected, "inputSchema", Dict())
        all(key -> haskey(arguments, key), get(schema, "required", [])) ||
            throw(ArgumentError("selected MCP tool requires additional configured arguments"))
        headers = config.mcp_version == "2026-07-28" ? mcp_tool_headers(schema, arguments) :
                  Pair{String, String}[]
        result, _ = mcp_post(config,
            mcp_request(config, "tools/call", 100,
                Dict("name" => config.mcp_tool, "arguments" => arguments));
            session,
            extra_headers = headers)
        get(result, "isError", false) === false ||
            throw(ArgumentError("MCP advice tool reported an error"))
        structured = get(result, "structuredContent", nothing)
        if config.mcp_response == :structured && structured isa AbstractDict &&
           haskey(structured, "cards")
            content = sprint(io -> PerfChecker.JSON.print(io, structured))
        else
            blocks = get(result, "content", [])
            blocks isa AbstractVector || throw(ArgumentError("invalid MCP tool content"))
            content = join(
                [block["text"]
                 for block in blocks
                 if
                 block isa AbstractDict && get(block, "type", "") == "text" &&
                 get(block, "text", nothing) isa AbstractString],
                "\n")
            if isempty(content) && config.mcp_response == :text &&
               structured isa AbstractDict
                content = sprint(io -> PerfChecker.JSON.print(io, structured))
            end
            isempty(content) && throw(ArgumentError("MCP advice tool returned no text"))
        end
        config.mcp_response == :text && return Dict("external_review" => content)
        Dict("choices" => [Dict("message" => Dict("content" => content))])
    finally
        # Legacy session release is best-effort and never masks the advice result.
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
