@testitem "MCP advice tools, custom prompts and qualification boundaries" tags=[
    :integration, :advisor_mcp] begin
    using PerfChecker, HTTP, Sockets, Base64
    socket = listen(ip"127.0.0.1", 0)
    port = getsockname(socket)[2]
    close(socket)
    requests = Any[]
    mode = Ref(:structured)
    answer = Dict(
        "cards" => [Dict("evidence_id" => "e1",
            "explanation" => "Observation, experiment and verification.")],
        "experiment_id" => "stop")
    encode(value) = sprint(io -> PerfChecker.JSON.print(io, value))
    server = HTTP.serve!("127.0.0.1", port; verbose = false) do request
        request.method == "GET" && return HTTP.Response(200, "ready")
        if request.method == "DELETE"
            push!(requests, (body = Dict("method" => "DELETE"), headers = request.headers))
            return HTTP.Response(204)
        end
        body = PerfChecker._json_parse(String(request.body))
        push!(requests, (body = body, headers = request.headers))
        method = body["method"]
        method == "notifications/initialized" && return HTTP.Response(202)
        result = if method == "initialize"
            Dict("protocolVersion" => "2025-11-25",
                "capabilities" => Dict("tools" => Dict()),
                "serverInfo" => Dict("name" => "test", "version" => "1"))
        elseif method == "tools/list"
            if !haskey(body["params"], "cursor")
                Dict("tools" => [], "nextCursor" => "page2")
            else
                Dict("tools" => [Dict("name" => "advise",
                    "inputSchema" => Dict("type" => "object",
                        "properties" => Dict("question" => Dict("type" => "string"),
                            "locale" => Dict("type" => "string", "x-mcp-header" => "Locale")),
                        "required" => ["question", "locale"]))])
            end
        else
            mode[] == :tool_error ? Dict("isError" => true, "content" => []) :
            mode[] == :interaction ?
            Dict("inputRequests" => [Dict("method" => "sampling/createMessage")]) :
            mode[] == :unknown ?
            Dict("structuredContent" => Dict("cards" => [Dict(
                "evidence_id" => "alien", "explanation" => "bad")])) :
            mode[] == :plain ?
            Dict("content" => [Dict("type" => "text", "text" => "No JSON contract")]) :
            mode[] == :text ?
            Dict("content" => [Dict("type" => "text", "text" => encode(answer))]) :
            Dict("structuredContent" => answer)
        end
        payload = Dict("jsonrpc" => "2.0", "id" => mode[] == :wrong_id ? 999 : body["id"],
            "result" => result)
        headers = ["Content-Type" => "application/json"]
        method == "initialize" && push!(headers, "Mcp-Session-Id" => "owned-test-session")
        if mode[] == :sse && method == "tools/call"
            note = encode(Dict("jsonrpc" => "2.0", "method" => "notifications/progress",
                "params" => Dict()))
            return HTTP.Response(200, ["Content-Type" => "text/event-stream"],
                ": heartbeat\r\n\r\ndata: $note\r\n\r\ndata: $(encode(payload))\r\n\r\n")
        end
        HTTP.Response(200, headers, encode(payload))
    end
    advice = Dict("schema_version" => "perfchecker-advice/1",
        "recommendations" => [
            Dict("id" => "e1", "rule_id" => "allocation", "hypothesis" => "Observed bytes",
            "action" => "Inspect temporaries", "validation" => "Repeat measurements")])
    config(version = "2026-07-28"; kwargs...) = AdvisorConfig(protocol = :mcp_http,
        endpoint = "http://127.0.0.1:$port/mcp", mcp_tool = "advise", mcp_prompt_argument = "question",
        mcp_arguments = Dict("locale" => "English ✓"), mcp_version = version, mcp_response = :structured,
        instructions = "Prioritize improvements to shared code.", timeout = 60; kwargs...)
    try
        HTTP.get("http://127.0.0.1:$port/ready")
        # Real worker transport, not just a parser test.
        for (version, selected_mode) in (("2026-07-28", :sse), ("2025-11-25", :text))
            mode[] = selected_mode
            empty!(requests)
            result = narrate_advice(advice; config = config(version))
            @test result["status"] == "complete"
            @test result["cards"] == answer["cards"]
            @test result["authority"] == "unverified_narrative"
            @test result["experiment_id"] == "stop"
            @test result["fallback"] == advice
            calls = filter(r -> r.body["method"] == "tools/call", requests)
            @test length(calls) == 1
            call = only(calls)
            @test call.body["params"]["name"] == "advise"
            @test occursin(
                config().instructions, call.body["params"]["arguments"]["question"])
            @test occursin("Observed bytes", call.body["params"]["arguments"]["question"])
            @test occursin("in English", call.body["params"]["arguments"]["question"])
            if version == "2026-07-28"
                @test call.body["params"]["_meta"]["io.modelcontextprotocol/clientCapabilities"] ==
                      Dict()
                @test HTTP.header(
                    HTTP.Request("POST", "/", call.headers), "Mcp-Param-Locale") ==
                      "=?base64?" * base64encode("English ✓") * "?="
                @test !any(r -> r.body["method"] == "initialize", requests)
            else
                @test any(r -> r.body["method"] == "notifications/initialized", requests)
                @test last(requests).body["method"] == "DELETE"
                @test HTTP.header(
                    HTTP.Request("POST", "/", call.headers), "Mcp-Session-Id") ==
                      "owned-test-session"
            end
        end
        for selected_mode in (:unknown, :plain, :interaction, :tool_error, :wrong_id)
            mode[] = selected_mode
            result = narrate_advice(advice; config = config())
            @test result["status"] == "error"
            @test result["fallback"] == advice
            @test isempty(result["cards"])
        end
        mode[] = :structured
        text_config = AdvisorConfig(protocol = :mcp_http, endpoint = config().endpoint,
            mcp_tool = "advise", mcp_prompt_argument = "question",
            mcp_arguments = Dict("locale" => "en"), timeout = 60)
        mode[] = :plain
        text_result = narrate_advice(advice; config = text_config)
        @test text_result["status"] == "complete"
        @test text_result["external_review"] == "No JSON contract"
        @test text_result["reference_status"] == "unstructured_not_verified"
        @test text_result["experiment_id"] == "stop" && isempty(text_result["cards"])
        @test agent_evidence(text_result)["external_review"] == "No JSON contract"
        view_result = copy(text_result)
        view_result["fallback"] = Dict(
            "schema_version" => "perfchecker-advice/1", "recommendations" => [])
        view_result["external_review"] = "<script>alert(1)</script>"
        html = sprint(show, MIME"text/html"(), investigation_view(view_result))
        @test occursin("&lt;script&gt;", html) && !occursin("<script>", html)
        @test_throws ArgumentError narrate_advice(advice; config = text_config,
            experiments = [Dict("id" => "run", "purpose" => "measure")])
        mode[] = :structured
        missing = AdvisorConfig(protocol = :mcp_http, endpoint = config().endpoint,
            mcp_tool = "absent", timeout = 60)
        empty!(requests)
        @test narrate_advice(advice; config = missing)["status"] == "error"
        @test !any(r -> r.body["method"] == "tools/call", requests)
        token = CancellationToken()
        cancel!(token)
        @test narrate_advice(advice; config = config(), cancellation = token)["status"] ==
              "cancelled"
        @test_throws ArgumentError AdvisorConfig(protocol = :mcp_http)
        @test_throws ArgumentError AdvisorConfig(mcp_version = "unknown")
        @test_throws ArgumentError AdvisorConfig(instructions = repeat("a", 5001))
        @test_throws ArgumentError AdvisorConfig(mcp_arguments = Dict("prompt" => "override"))
        @test_throws ArgumentError AdvisorConfig(protocol = :mcp_http, mcp_tool = "advise",
            endpoint = "https://server.example/mcp")
        extension = Base.get_extension(PerfChecker, :HTTPAdvisorExt)
        @test_throws ArgumentError extension.mcp_tool_headers(
            Dict("oneOf" => [
                Dict("x-mcp-header" => "Bad", "type" => "string")]), Dict())
        @test_throws ArgumentError extension.mcp_read(
            IOBuffer("data: {}\n\n"), "text/event-stream", 1)
        @test_throws ArgumentError extension.mcp_read(IOBuffer("{}"), "text/plain", 1)
        @test_throws ArgumentError extension.mcp_read(
            IOBuffer(repeat("x", 1_000_001)), "application/json", 1)
    finally
        close(server)
    end
end
