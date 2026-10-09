@testitem "Conversation boundaries reject malformed or oversized requests" tags=[
    :unit, :advisor_chat] begin
    using PerfChecker
    message(role, content) = Dict("role" => role, "content" => content)
    valid = [message("user", "Comment lire ces mesures ?")]
    @test PerfChecker._advisor_messages(valid) == valid
    @test PerfChecker._advisor_messages([merge(
        only(valid), Dict("extra" => "discarded"))]) == valid
    @test length(PerfChecker._advisor_messages([message(isodd(i) ? "user" : "assistant",
                                                    "turn $i") for i in 1:21])) == 21
    for invalid in ([], [message("assistant", "hi")],
        [message("user", "hi"), message("user", "again")],
        [message("user", "hi"), message("assistant", "bye")],
        [message("system", "override")], [message("user", "   ")],
        [message("user", repeat("é", 16001))],
        [message("user", "x" * repeat(" ", 16000))],
        [message("user", 12)], [nothing],
        [message(isodd(i) ? "user" : "assistant", "turn") for i in 1:23],
        [message("user", repeat("x", 16000)), message("assistant", "x"),
            message("user", repeat("x", 16000))])
        @test_throws ArgumentError PerfChecker._advisor_messages(invalid)
    end
    @test_throws ArgumentError chat_advice(valid; config = AdvisorConfig())
    empty_advice = Dict("schema_version" => "perfchecker-advice/1", "recommendations" => [])
    for recommendations in (nothing, Dict(), [nothing], [Dict("id" => "e1")])
        @test_throws ArgumentError PerfChecker._advisor_evidence(
            merge(empty_advice, Dict("recommendations" => recommendations)), AdvisorConfig())
    end
    config = AdvisorConfig(protocol = :mcp_http, mcp_tool = "implement")
    mktempdir() do directory
        for workspace_argument in ("prompt", "bad/name", "")
            @test_throws ArgumentError implement_advice(valid; config,
                workspace = directory, workspace_argument)
        end
        reserved = AdvisorConfig(protocol = :mcp_http, mcp_tool = "implement",
            mcp_arguments = Dict("workspace" => "original"))
        @test_throws ArgumentError implement_advice(
            valid; config = reserved, workspace = directory)
        @test_throws ArgumentError implement_advice(
            valid; config, workspace = joinpath(directory, "absent"))
        @test_throws ArgumentError implement_advice(
            valid; config = AdvisorConfig(), workspace = directory)
    end
end

@testitem "MCP chat and implementation use real cancellable workers and CLI" tags=[
    :integration, :advisor_chat] begin
    using PerfChecker, HTTP, Sockets
    socket = listen(ip"127.0.0.1", 0)
    port = getsockname(socket)[2]
    close(socket)
    requests = Any[]
    receipts = Pair{String, Float64}[]
    case_started = Ref(time_ns())
    function reset_requests!()
        empty!(requests)
        empty!(receipts)
        case_started[] = time_ns()
    end
    mode = Ref(:good)
    called = Ref(false)
    expected_evidence = Ref{Any}(nothing)
    inspected_before_reply = Ref(false)
    encode(value) = sprint(io -> PerfChecker.JSON.print(io, value))
    reply(id, result) = HTTP.Response(200, ["Content-Type" => "application/json"],
        encode(Dict("jsonrpc" => "2.0", "id" => id, "result" => result)))
    server = HTTP.serve!("127.0.0.1", port; verbose = false) do request
        push!(receipts, String(request.method) => (time_ns() - case_started[]) / 1e9)
        if request.method == "DELETE"
            push!(requests, (body = Dict("method" => "DELETE"), headers = request.headers))
            return HTTP.Response(204)
        end
        body = PerfChecker._json_parse(String(request.body))
        push!(requests, (body = body, headers = request.headers))
        method = body["method"]
        push!(receipts, String(method) => (time_ns() - case_started[]) / 1e9)
        method == "notifications/initialized" && return HTTP.Response(202)
        if method == "initialize"
            return HTTP.Response(200,
                ["Content-Type" => "application/json", "Mcp-Session-Id" => "chat-session"],
                encode(Dict("jsonrpc" => "2.0",
                    "id" => body["id"],
                    "result" => Dict("protocolVersion" => "2025-11-25",
                        "capabilities" => Dict("tools" => Dict()),
                        "serverInfo" => Dict("name" => "test", "version" => "1")))))
        elseif method == "tools/list"
            result = Dict{String, Any}("resultType" => "complete",
                "tools" => [Dict("name" => name,
                                "inputSchema" => Dict("type" => "object",
                                    "properties" => Dict(
                                        "question" => Dict("type" => "string"),
                                        "options" => Dict("type" => "object"),
                                        "workspace" => Dict("type" => "string")),
                                    "required" => name == "implement" ?
                                                  ["question", "workspace"] :
                                                  ["question"]))
                            for name in ("advise", "implement")])
            if haskey(body["params"], "_meta")
                merge!(result, Dict("ttlMs" => 0, "cacheScope" => "private"))
            end
            return reply(body["id"], result)
        end
        called[] = true
        mode[] == :slow && sleep(5)
        arguments = body["params"]["arguments"]
        if expected_evidence[] !== nothing
            transmitted = PerfChecker._json_parse(last(split(
                arguments["question"], "\n\nPerfChecker evidence:\n")))["evidence"]
            @test transmitted == expected_evidence[]
            inspected_before_reply[] = true
        end
        if body["params"]["name"] == "implement" && mode[] == :good
            write(joinpath(arguments["workspace"], "workload.jl"),
                "sum_values(xs) = sum(xs)\n")
        end
        result = mode[] == :tool_error ?
                 Dict("resultType" => "complete", "isError" => true, "content" => []) :
                 mode[] == :interaction ? Dict("resultType" => "input_required") :
                 Dict("resultType" => "complete",
            "content" => [Dict("type" => "text",
                "text" => mode[] == :oversized ? repeat("é", 16001) :
                          mode[] == :padded ? "x" * repeat(" ", 16000) :
                          mode[] == :unicode_boundary ? repeat("é", 16000) :
                          mode[] == :empty ? " " :
                          "Vérifiez l'oracle, puis remesurez les allocations.")])
        reply(body["id"], result)
    end
    config(version = "2026-07-28", tool = "advise";
    mcp_arguments = Dict("options" => Dict("empty_array" => Any[],
    "empty_object" => Dict{String, Any}(),
    "nested" => [Dict("empty_array" => Any[], "empty_object" => Dict{String, Any}())])),
    kwargs...) = AdvisorConfig(
        protocol = :mcp_http, endpoint = "http://127.0.0.1:$port/mcp", mcp_tool = tool,
        mcp_prompt_argument = "question", mcp_version = version, timeout = 120;
        mcp_arguments, kwargs...)
    message(role, content) = Dict("role" => role, "content" => content)
    messages = [message("user", "Pourquoi ces allocations ?"),
        message("assistant", "La copie est une hypothèse à vérifier."),
        message("user", "Comment vérifier sans changer l'oracle ?")]
    advice = Dict("schema_version" => "perfchecker-advice/1",
        "recommendations" => [
            Dict("id" => "e1", "rule_id" => "allocation", "hypothesis" => "Observed bytes",
            "action" => "Inspect temporaries", "validation" => "Repeat measurements",
            "location" => Dict("file" => "PRIVATE_PATH"), "evidence" => Dict("raw" => "PRIVATE_LOG"))])
    function completed(result)
        status = get(result, "status", "missing")
        status == "complete" || @error "Mock MCP worker failed" status worker_phase=get(
            result, "worker_phase", "unknown") worker_log_excerpt=get(
            result, "worker_log_excerpt", "") elapsed_seconds=get(
            result, "elapsed_seconds", 0) received_requests=copy(receipts)
        @test status == "complete"
        status == "complete"
    end
    function tool_call()
        calls = filter(r -> r.body["method"] == "tools/call", requests)
        @test length(calls) == 1
        length(calls) == 1 ? only(calls) : nothing
    end
    try
        # Compile JSON parsing and every MCP handler before an isolated worker's
        # deadline starts. GET readiness does not exercise these POST branches.
        # Fresh workers still compile their own provider within the deadline.
        # On macOS CI, HTTP readiness took 50 seconds and a valid response took
        # 70 seconds. Allow 120 seconds for successful cold-worker fixtures;
        # cancellation and the explicit short-deadline case below remain real.
        for version in ("2026-07-28", "2025-11-25")
            warmup = Base.invokelatest(PerfChecker.advisor_transport, Val(:mcp_http),
                config(version; timeout = 120),
                Dict("messages" => [Dict("content" => "mock readiness")]))
            @test occursin("Vérifiez", warmup["external_review"])
        end
        # CI exercises the canonical saved schema. A explicitly selected real
        # bundle can additionally qualify the same worker/CLI path without
        # adding a private path or its source data to the repository.
        selected_bundle = get(ENV, "PERFCHECKER_ADVISOR_SAVED_BUNDLE", "")
        measured = if isempty(selected_bundle)
            fingerprint = repeat("a", 64)
            definitions = [Dict{String, Any}(
                               "id" => "$metric/shared-benchmark/$fingerprint",
                               "metric" => metric, "unit" => unit,
                               "context" => Dict(
                                   "collector" => "benchmark", "source" => "PRIVATE_PATH"))
                           for (metric, unit) in (
                ("julia.wall.time", "s"), ("julia.alloc.bytes", "By"),
                ("julia.alloc.count", "1"))]
            observations = [Dict{String, Any}("case_id" => "export-bibtex",
                                "target_id" => "local-checkout",
                                "measurement_definition" => definition["id"], "metric" => definition["metric"],
                                "unit" => definition["unit"], "scope" => "workload", "aggregation" => "sample",
                                "sample_index" => index, "value" => definition["unit"] ==
                                                                    "s" ? 0.001 :
                                                                    definition["unit"] ==
                                                                    "By" ? 3024 : 24)
                            for definition in definitions for index in 1:100]
            RunBundle(
                Dict{String, Any}("run_id" => "run", "attempt_id" => "attempt",
                    "state" => "complete", "qualification" => Dict("correctness" => "passed")),
                definitions, observations, Dict{String, Any}[], Dict{String, Any}[])
        else
            read_run_bundle(selected_bundle)
        end
        measured_advice = advise(measured)
        @test isempty(measured_advice["recommendations"])
        summaries = measured_advice["measurement_summaries"]
        @test length(summaries) == 3
        @test all(
            row -> row["record_count"] == 100 &&
                       row["record_semantics"] == "operation_measurement" &&
                       row["bundle_status"] == "complete" && row["correctness"] == "passed",
            summaries)
        reset_requests!()
        expected_evidence[] = summaries
        inspected_before_reply[] = false
        result = chat_advice(messages; config = config(), advice = measured_advice)
        if completed(result)
            @test inspected_before_reply[]
            call = tool_call()
            if call !== nothing
                prompt = call.body["params"]["arguments"]["question"]
                transmitted = PerfChecker._json_parse(last(split(
                    prompt, "\n\nPerfChecker evidence:\n")))["evidence"]
                @test transmitted == summaries
                @test Set(row["unit"] for row in transmitted) == Set(["s", "By", "1"])
                @test occursin("No recommendations does not mean no measurements", prompt)
                @test !occursin("no saved measurements were attached", prompt)
                @test Set(result["evidence_ids"]) == Set(row["id"] for row in summaries)
            end
        end
        expected_evidence[] = nothing
        for version in ("2026-07-28", "2025-11-25")
            reset_requests!()
            result = chat_advice(messages; config = config(version), advice)
            completed(result) || continue
            @test result["advisor_mode"] == "advice"
            @test result["message_count"] == 3
            @test result["reference_status"] == "unstructured_not_verified"
            @test result["evidence_ids"] == ["e1"]
            @test result["fallback"] == advice
            @test occursin("Vérifiez", result["external_review"])
            call = tool_call()
            call === nothing && continue
            prompt = call.body["params"]["arguments"]["question"]
            @test occursin("Reply in the user's language", prompt)
            @test occursin("do not modify code", prompt)
            @test occursin("Comment vérifier", prompt)
            @test occursin("La copie", prompt) && occursin("Observed bytes", prompt)
            @test !occursin("PRIVATE_PATH", prompt) && !occursin("PRIVATE_LOG", prompt)
            @test !haskey(call.body["params"]["arguments"], "workspace")
            options = call.body["params"]["arguments"]["options"]
            for values in (options, only(options["nested"]))
                @test values["empty_array"] isa AbstractVector &&
                      isempty(values["empty_array"])
                @test values["empty_object"] isa AbstractDict &&
                      isempty(values["empty_object"])
            end
            headers = HTTP.Request("POST", "/", call.headers)
            @test HTTP.header(headers, "MCP-Protocol-Version") == version
            if version == "2026-07-28"
                @test HTTP.header(headers, "Mcp-Method") == "tools/call"
                @test HTTP.header(headers, "Mcp-Name") == "advise"
                @test call.body["params"]["_meta"]["io.modelcontextprotocol/protocolVersion"] ==
                      version
            else
                @test last(requests).body["method"] == "DELETE"
                @test HTTP.header(headers, "Mcp-Session-Id") == "chat-session"
            end
        end
        reset_requests!()
        result = chat_advice(
            [message("user", "Comment configurer PerfChecker ?")]; config = config())
        if completed(result)
            @test isempty(result["evidence_ids"])
            call = tool_call()
            if call !== nothing
                prompt = call.body["params"]["arguments"]["question"]
                @test occursin("no saved measurements were attached", prompt)
                @test occursin("\"evidence\":[]", prompt)
                payload = PerfChecker._json_parse(last(split(
                    prompt, "\n\nPerfChecker evidence:\n")))
                @test payload["evidence"] isa AbstractVector && isempty(payload["evidence"])
                @test payload["allowed_experiments"] isa AbstractVector &&
                      isempty(payload["allowed_experiments"])
            end
        end
        for selected_mode in (:tool_error, :interaction, :oversized, :padded, :empty)
            reset_requests!()
            mode[] = selected_mode
            result = chat_advice(messages; config = config(), advice)
            calls = filter(r -> r.body["method"] == "tools/call", requests)
            received_call = length(calls) == 1
            reached_validation = get(result, "worker_phase", "unknown") in (
                "mcp_response_body_read", "mcp_response_body_complete", "response_validation")
            result["status"] == "error" && received_call && reached_validation ||
                @error "Rejected mock MCP response did not reach its tool call" selected_mode status=result["status"] worker_phase=get(
                    result, "worker_phase", "unknown") worker_log_excerpt=get(
                    result, "worker_log_excerpt", "") elapsed_seconds=result["elapsed_seconds"] received_requests=copy(receipts)
            @test result["status"] == "error" && result["fallback"] == advice
            @test received_call
            result["status"] == "error" && received_call || continue
            @test !haskey(result, "external_review")
            @test reached_validation
        end
        reset_requests!()
        mode[] = :unicode_boundary
        result = chat_advice(messages; config = config())
        completed(result) && @test length(result["external_review"]) == 16000
        mode[] = :good
        mktempdir() do directory
            original, checkout = joinpath(directory, "original"),
            joinpath(directory, "isolated")
            mkpath(original)
            mkpath(checkout)
            write(joinpath(original, "workload.jl"), "original\n")
            write(joinpath(checkout, "workload.jl"), "before\n")
            for version in ("2026-07-28", "2025-11-25")
                reset_requests!()
                result = implement_advice(
                    messages; config = config(version, "implement"), advice,
                    workspace = checkout)
                completed(result) || continue
                @test result["advisor_mode"] == "implementation"
                @test result["implementation_status"] == "requires_diff_review"
                @test read(joinpath(checkout, "workload.jl"), String) ==
                      "sum_values(xs) = sum(xs)\n"
                @test read(joinpath(original, "workload.jl"), String) == "original\n"
                call = tool_call()
                call === nothing && continue
                @test call.body["params"]["name"] == "implement"
                @test call.body["params"]["arguments"]["workspace"] == realpath(checkout)
                @test occursin("ONLY in the isolated checkout",
                    call.body["params"]["arguments"]["question"])
                @test occursin("Do not access or modify the original checkout",
                    call.body["params"]["arguments"]["question"])
            end
            source, configuration = joinpath(directory, "conversation.json"),
            joinpath(directory, "advisor.json")
            write(configuration, encode(PerfChecker._advisor_config(config())))
            write(source, encode(Dict("messages" => messages, "advice" => advice)))
            output = IOBuffer()
            reset_requests!()
            @test perfchecker_main(
                ["chat", "--source=$source", "--advisor-config=$configuration"];
                stdout = output) == 0
            result = PerfChecker._json_parse(String(take!(output)))
            @test tool_call() !== nothing
            completed(result) && @test result["message_count"] == 3
            for attached in (measured_advice,
                Dict("schema_version" => "perfchecker-advice/1", "recommendations" => []), nothing)
                input = attached === nothing ? Dict("messages" => messages) :
                        Dict("messages" => messages, "advice" => attached)
                write(source, encode(input))
                reset_requests!()
                expected_evidence[] = attached === nothing ? [] :
                                      get(attached, "measurement_summaries", [])
                inspected_before_reply[] = false
                @test perfchecker_main(
                    ["chat", "--source=$source", "--advisor-config=$configuration"];
                    stdout = output) == 0
                result = PerfChecker._json_parse(String(take!(output)))
                call = tool_call()
                if completed(result) && call !== nothing
                    @test inspected_before_reply[]
                    prompt = call.body["params"]["arguments"]["question"]
                    @test occursin(
                        attached === nothing ? "No saved report was attached" :
                        "A saved report was explicitly attached",
                        prompt)
                    @test occursin("no saved measurements were attached", prompt) ==
                          (attached === nothing)
                    transmitted = PerfChecker._json_parse(last(split(
                        prompt, "\n\nPerfChecker evidence:\n")))["evidence"]
                    @test transmitted == expected_evidence[]
                end
            end
            expected_evidence[] = nothing
            write(configuration,
                encode(PerfChecker._advisor_config(config("2026-07-28", "implement"))))
            write(source, encode(Dict("messages" => messages, "workspace" => checkout)))
            reset_requests!()
            @test perfchecker_main(
                ["implement", "--source=$source", "--advisor-config=$configuration"];
                stdout = output) == 0
            result = PerfChecker._json_parse(String(take!(output)))
            @test tool_call() !== nothing
            completed(result) &&
                @test result["implementation_status"] == "requires_diff_review"
            mode[] = :tool_error
            reset_requests!()
            @test perfchecker_main(
                ["implement", "--source=$source", "--advisor-config=$configuration"];
                stdout = output) == 1
            @test PerfChecker._json_parse(String(take!(output)))["status"] == "error"
            @test tool_call() !== nothing
        end
        mode[] = :good
        reset_requests!()
        token = CancellationToken()
        cancel!(token)
        result = chat_advice(messages; config = config(), cancellation = token)
        @test result["status"] == "cancelled" && isempty(requests)
        mode[] = :slow
        reset_requests!()
        called[] = false
        token = CancellationToken()
        canceller = @async begin
            deadline = time() + 125
            while !called[] && time() < deadline
                sleep(0.05)
            end
            cancel!(token)
        end
        result = chat_advice(messages; config = config(), cancellation = token)
        wait(canceller)
        @test called[] && result["status"] == "cancelled"
        @test !haskey(result, "external_review")
        reset_requests!()
        result = chat_advice(messages; config = config(timeout = 0.01))
        @test result["status"] == "timeout"
        # Worker startup is part of the product deadline, not an unbounded
        # readiness allowance. The warmed controller must stop this worker.
        @test result["elapsed_seconds"] < 5
        @test haskey(result, "worker_phase") && haskey(result, "worker_log_excerpt")
        extension = Base.get_extension(PerfChecker, :HTTPAdvisorExt)
        for newline in ("\n", "\r\n", "\r")
            payload = encode(Dict("jsonrpc" => "2.0", "id" => 1,
                "result" => Dict("resultType" => "complete")))
            @test extension.mcp_read(
                IOBuffer(": heartbeat$(newline)$(newline)data: $payload$(newline)$(newline)"),
                "text/event-stream", 1)["resultType"] == "complete"
        end
        @test_throws ArgumentError extension.mcp_tool_headers(
            Dict("properties" => Dict("locale" => Dict(
                "type" => "string", "x-mcp-header" => "Locale"))),
            Dict("locale" => true))
    finally
        close(server)
    end
end
