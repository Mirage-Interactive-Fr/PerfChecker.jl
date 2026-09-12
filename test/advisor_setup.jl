@testitem "Advisor setup and explicit model lifecycle" tags=[:integration, :advisor_setup] begin
    using PerfChecker, HTTP, Sockets
    listener = listen(ip"127.0.0.1", 0)
    port = getsockname(listener)[2]
    close(listener)
    calls = Any[]
    slow = Ref(false)
    encode(value) = sprint(io -> PerfChecker.JSON.print(io, value))
    server = HTTP.serve!("127.0.0.1", port; verbose = false) do request
        request.target == "/ready" && return HTTP.Response(200, "ready")
        input = request.method == "GET" || request.body === nothing ||
                isempty(request.body) ? Dict() :
                PerfChecker._json_parse(String(request.body))
        push!(calls, (method = request.method, target = request.target, input = input))
        slow[] && sleep(20)
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
        elseif request.target == "/mcp"
            @test input["method"] == "tools/list"
            Dict("jsonrpc" => "2.0",
                "id" => input["id"],
                "result" => Dict("tools" => [
                    Dict(
                    "name" => "ask", "description" => "Advice <script>unsafe</script>",
                    "inputSchema" => Dict("type" => "object", "required" => ["question"],
                        "properties" => Dict("question" => Dict("type" => "string"))))]))
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
        deadline = time() + 40
        while length(calls) == before && time() < deadline
            sleep(0.1)
        end
        @test length(calls) > before
        cancel!(job)
        @test wait_investigation(job)["status"] == "cancelled"
        @test all(call -> !haskey(call.input, "messages"), calls)
    finally
        slow[] = false
        close(server)
    end
end
