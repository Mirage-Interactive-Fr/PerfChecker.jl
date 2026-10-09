@testitem "Advisor setup and explicit model lifecycle" tags=[:integration, :advisor_setup] begin
    using PerfChecker, HTTP, Sockets
    listener = listen(ip"127.0.0.1", 0)
    port = getsockname(listener)[2]
    close(listener)
    calls = Any[]
    slow = Ref(false)
    mcp_mode = Ref(:valid)
    mcp_version = Ref("2026-07-28")
    active_request = Ref(false)
    encode(value) = sprint(io -> PerfChecker.JSON.print(io, value))
    server = HTTP.serve!("127.0.0.1", port; verbose = false) do request
        request.target == "/ready" && return HTTP.Response(200, "ready")
        input = request.method == "GET" || request.body === nothing ||
                isempty(request.body) ? Dict() :
                PerfChecker._json_parse(String(request.body))
        push!(calls, (method = request.method, target = request.target, input = input))
        if slow[]
            active_request[] = true
            try
                sleep(20)
            finally
                active_request[] = false
            end
        end
        body = if request.target == "/api/tags"
            Dict("models" => [Dict(
                "name" => "tiny:latest", "size" => 523000000, "digest" => "shared")])
        elseif request.target == "/v1/models"
            Dict("data" => [Dict("id" => "tiny")])
        elseif request.target == "/api/pull"
            Dict("status" => "success")
        elseif request.target == "/api/delete"
            return HTTP.Response(200, "")
        elseif request.target == "/api/generate"
            Dict("done" => true, "response" => "")
        elseif request.target in ("/mcp", "/api.v2/mcp%20gateway")
            request.method == "DELETE" && return HTTP.Response(204)
            method = input["method"]
            method == "notifications/initialized" && return HTTP.Response(202)
            if method == "initialize"
                @test input["params"]["clientInfo"]["version"] ==
                      string(pkgversion(PerfChecker))
                return HTTP.Response(200, ["Content-Type" => "application/json"],
                    encode(Dict("jsonrpc" => "2.0", "id" => input["id"],
                        "result" => Dict("protocolVersion" => "2025-11-25",
                            "capabilities" => Dict("tools" => Dict()),
                            "serverInfo" => Dict(
                                "name" => "generic-fixture", "version" => "1")))))
            end
            if mcp_version[] == "2026-07-28"
                meta = input["params"]["_meta"]
                @test meta["io.modelcontextprotocol/protocolVersion"] == "2026-07-28"
                @test meta["io.modelcontextprotocol/clientInfo"] ==
                      Dict(
                    "name" => "PerfChecker", "version" => string(pkgversion(PerfChecker)))
                @test meta["io.modelcontextprotocol/clientCapabilities"] == Dict()
            else
                @test !haskey(input["params"], "_meta")
            end
            if method == "server/discover"
                capabilities = mcp_mode[] == :no_tools ? Dict("resources" => Dict()) :
                               Dict(
                    "tools" => Dict("listChanged" => false), "resources" => Dict())
                versions = mcp_mode[] == :wrong_version ? ["2025-11-25"] : ["2026-07-28"]
                return HTTP.Response(200, ["Content-Type" => "application/json"],
                    encode(Dict("jsonrpc" => "2.0", "id" => input["id"],
                        "result" => Dict("resultType" => "complete", "ttlMs" => 0,
                            "cacheScope" => "private", "supportedVersions" => versions,
                            "capabilities" => capabilities,
                            "_meta" => Dict("io.modelcontextprotocol/serverInfo" => Dict(
                                "name" => repeat("é", 400), "version" => "1",
                                "private" => "SERVER_PRIVATE"))))))
            end
            @test method == "tools/list"
            result = Dict{String, Any}("tools" => [
                Dict(
                "name" => "ask", "description" => "Advice <script>unsafe</script>",
                "inputSchema" => Dict("type" => "object", "required" => ["question"],
                    "properties" => Dict("question" => Dict("type" => "string"))))])
            if mcp_version[] == "2026-07-28"
                merge!(result,
                    Dict("resultType" => "complete", "ttlMs" => 0,
                        "cacheScope" => "private"))
            end
            Dict("jsonrpc" => "2.0", "id" => input["id"], "result" => result)
        else
            return HTTP.Response(401, "never expose this provider error")
        end
        HTTP.Response(200, ["Content-Type" => "application/json"], encode(body))
    end
    local_config = AdvisorConfig(
        protocol = :ollama, endpoint = "http://127.0.0.1:$port/api/chat",
        model = "tiny:latest", timeout = 60)
    try
        HTTP.get("http://127.0.0.1:$port/ready")
        @test advisor_setup(local_config; action = :validate)["config"]["protocol"] ==
              "ollama"
        @test_throws ArgumentError advisor_setup(
            local_config; action = :pull, model = "tiny:latest")
        @test_throws ArgumentError advisor_setup(
            local_config; action = :delete, model = "../secret", confirmed = true)
        remote = AdvisorConfig(
            protocol = :ollama, endpoint = "https://example.com/api/chat",
            allow_remote = true)
        @test_throws ArgumentError advisor_setup(
            remote; action = :pull, model = "tiny", confirmed = true)
        @test isempty(calls)
        result = advisor_setup(local_config)
        @test result["status"] == "complete"
        @test result["evidence_sent"] == false
        @test result["generation_tested"] == false
        @test result["selected_available"]
        @test result["models"][1]["size_bytes"] == 523000000
        @test only(calls).method == "GET"
        for action in (:pull, :delete, :unload)
            result = advisor_setup(
                local_config; action, model = "tiny:latest", confirmed = true)
            @test result["status"] == "complete"
        end
        @test calls[end].input["keep_alive"] == 0
        @test !haskey(calls[end].input, "prompt")
        @test calls[end - 1].method == "DELETE"
        draft = Dict("protocol" => "mcp_http",
            "endpoint" => "http://127.0.0.1:$port/mcp", "timeout" => 60)
        mcp = advisor_setup(draft)
        @test mcp["status"] == "complete"
        @test only(mcp["tools"])["name"] == "ask"
        @test !mcp["selected_available"]
        @test mcp["server"]["protocol_version"] == "2026-07-28"
        @test mcp["server"]["supported_versions"] == ["2026-07-28"]
        @test mcp["server"]["capabilities"] ==
              Dict("tools" => Dict("listChanged" => false), "resources" => Dict())
        @test length(mcp["server"]["server_info"]["name"]) == 256
        @test !occursin("SERVER_PRIVATE", string(mcp["server"]))
        @test [call.input["method"] for call in calls if call.target == "/mcp"] ==
              ["server/discover", "tools/list"]
        modern = AdvisorConfig(
            protocol = :mcp_http, endpoint = draft["endpoint"], mcp_tool = "ask")
        for mode in (:wrong_version, :no_tools)
            mcp_mode[] = mode
            before = length(calls)
            @test_throws ArgumentError Base.invokelatest(
                advisor_setup_transport, modern, :probe, "")
            @test length(calls) == before + 1
            @test last(calls).input["method"] == "server/discover"
        end
        mcp_mode[] = :valid
        mcp_version[] = "2025-11-25"
        legacy = AdvisorConfig(protocol = :mcp_http, endpoint = draft["endpoint"],
            mcp_tool = "ask", mcp_version = "2025-11-25")
        before = length(calls)
        old = Base.invokelatest(advisor_setup_transport, legacy, :probe, "")
        @test old["server"]["protocol_version"] == "2025-11-25"
        @test old["server"]["server_info"]["name"] == "generic-fixture"
        @test [call.input["method"] for call in calls[(before + 1):end]] ==
              ["initialize", "notifications/initialized", "tools/list"]
        mcp_version[] = "2026-07-28"
        encoded = AdvisorConfig(protocol = :mcp_http,
            endpoint = "http://127.0.0.1:$port/api.v2/mcp%20gateway", mcp_tool = "ask")
        before = length(calls)
        path_probe = Base.invokelatest(advisor_setup_transport, encoded, :probe, "")
        @test path_probe["status"] == "complete"
        @test [call.target for call in calls[(before + 1):end]] ==
              ["/api.v2/mcp%20gateway", "/api.v2/mcp%20gateway"]
        @test [call.input["method"] for call in calls[(before + 1):end]] ==
              ["server/discover", "tools/list"]
        @test_throws ArgumentError advisor_setup(draft; action = :validate)
        chat = AdvisorConfig(
            endpoint = "http://127.0.0.1:$port/v1/chat/completions", model = "tiny")
        @test Base.invokelatest(advisor_setup_transport, chat, :probe, "")["selected_available"]
        bad = AdvisorConfig(endpoint = "http://127.0.0.1:$port/other/chat/completions")
        failed = PerfChecker._advisor_setup_inprocess(
            bad, Dict("setup_action" => "probe", "setup_model" => ""))
        @test failed["status"] == "error"
        @test occursin("401", failed["message"])
        @test !occursin("never expose", failed["message"])
        # Cancellation is exercised while an owned server request is actually active.
        slow[] = true
        before = length(calls)
        job = launch_advisor_setup(local_config)
        deadline = time() + local_config.timeout
        while !active_request[] && time() < deadline &&
                  investigation_status(job; include_result = false)["status"] == "running"
            sleep(0.1)
        end
        reached_request = active_request[] && length(calls) > before
        reached_request ||
            @error "Advisor setup cancellation did not reach an active request" job=investigation_status(job) received_requests=copy(calls) controller_pid=getpid()
        @test reached_request
        cancel!(job)
        final = wait_investigation(job)
        reached_request ||
            @error "Advisor setup worker stopped without observed transport" job=final received_requests=copy(calls) controller_pid=getpid()
        @test final["status"] == "cancelled"
        @test istaskdone(job.task)
        @test all(call -> !haskey(call.input, "messages"), calls)
    finally
        slow[] = false
        close(server)
    end
end
