@testitem "Optional HTTP model providers and rejected output" tags=[
    :integration, :advisor_http] begin
    using PerfChecker, HTTP, Sockets
    socket = listen(ip"127.0.0.1", 0)
    port = getsockname(socket)[2]
    close(socket)
    requested = Dict{String, Any}[]
    mode = Ref(:good)
    server = HTTP.serve!("127.0.0.1", port; verbose = false) do request
        body = PerfChecker._json_parse(String(request.body))
        push!(requested, body)
        if mode[] == :slow
            sleep(3)
        end
        id = mode[] == :unknown ? "invented" : "e1"
        content = sprint(io -> PerfChecker.JSON.print(io,
            Dict(
                "cards" => [Dict(
                    "evidence_id" => id, "explanation" => "Observation et vérification.")],
                "experiment_id" => "stop")))
        payload = request.target == "/api/chat" ?
                  Dict("message" => Dict("content" => content)) :
                  Dict("choices" => [Dict("message" => Dict("content" => content))])
        HTTP.Response(200, sprint(io -> PerfChecker.JSON.print(io, payload)))
    end
    advice = Dict("schema_version" => "perfchecker-advice/1",
        "recommendations" => [
            Dict("id" => "e1", "rule_id" => "allocation", "hypothesis" => "Observed bytes",
            "action" => "Inspect temporaries", "validation" => "Repeat measurements")])
    try
        # Compile the Julia mock handler before testing isolated client deadlines.
        # The adapter tests exercise the provider protocol, not mock-server startup.
        warmup = HTTP.post("http://127.0.0.1:$port/v1/chat/completions",
            ["Content-Type" => "application/json"], "{}";
            readtimeout = 120, connect_timeout = 120, retry = false)
        @test warmup.status == 200
        empty!(requested)
        for (protocol, path) in (
            (:chat_completions, "/v1/chat/completions"), (
                :chat_completions_schema, "/v1/chat/completions"), (:ollama, "/api/chat"))
            result = narrate_advice(advice;
                config = AdvisorConfig(;
                    protocol, endpoint = "http://127.0.0.1:$port$path", timeout = 45))
            result["status"] == "complete" ||
                @error "Mock advisor request failed" protocol status=result["status"] message=get(
                    result, "message", "") elapsed_seconds=result["elapsed_seconds"]
            @test result["status"] == "complete"
            @test only(result["cards"])["evidence_id"] == "e1"
            @test isempty(result["usage"])
            if protocol == :chat_completions_schema
                schema = last(requested)["response_format"]["json_schema"]["schema"]
                @test schema["properties"]["cards"]["items"]["properties"]["evidence_id"]["enum"] ==
                      ["e1"]
                @test schema["properties"]["experiment_id"]["enum"] == ["stop"]
            end
        end
        mode[] = :unknown
        result = narrate_advice(advice;
            config = AdvisorConfig(
                endpoint = "http://127.0.0.1:$port/v1/chat/completions", timeout = 45))
        @test result["status"] == "error" && isempty(result["cards"])
        @test result["fallback"] == advice
        @test !any(haskey(body, "tools") for body in requested)
        token = CancellationToken()
        cancel!(token)
        result = narrate_advice(advice;
            cancellation = token,
            config = AdvisorConfig(endpoint = "http://127.0.0.1:$port/v1/chat/completions"))
        @test result["status"] == "cancelled"
        result = narrate_advice(advice;
            config = AdvisorConfig(provider_package = "PerfCheckerNoSuchProvider",
                protocol = :custom, timeout = 45))
        @test result["status"] == "unavailable"
    finally
        close(server)
    end
end
