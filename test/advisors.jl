@testitem "Advisor evidence boundaries and provider contracts" tags=[:unit, :advisor] begin
    using PerfChecker
    @test AdvisorConfig().allow_remote == false
    @test AdvisorConfig(
        protocol = "ollama", endpoint = "http://localhost:11434/api/chat").protocol ==
          :ollama
    @test AdvisorConfig(
        protocol = :custom, provider_package = "MyProvider").provider_package ==
          "MyProvider"
    @test_throws ArgumentError AdvisorConfig(endpoint = "https://example.com/v1/chat/completions")
    @test AdvisorConfig(endpoint = "https://example.com/v1/chat/completions",
        allow_remote = true).allow_remote
    for path in ("/v1.0/mcp", "/mcp%20gateway/%CF%80", "/tools%2Fask",
        raw"/!$&'()*+,;=:@-._~/mcp")
        endpoint = "http://127.0.0.1:8081" * path
        @test AdvisorConfig(endpoint = endpoint).endpoint == endpoint
    end
    @test AdvisorConfig(endpoint = "http://[::1]:8081/api.v2/mcp%20gateway").allow_remote ==
          false
    for endpoint in ("http://127.0.0.1:0/mcp", "http://127.0.0.1:65536/mcp",
        "http://127.0.0.1:999999/mcp", "http://127.0.0.1/mcp%",
        "http://127.0.0.1/mcp%2", "http://127.0.0.1/mcp%GG",
        "http://127.0.0.1/mcp%0aInjected", "http://127.0.0.1/mcp%0DInjected",
        "http://127.0.0.1/mcp%00", "http://127.0.0.1/mcp%7f",
        "http://127.0.0.1/mcp%5Cescape", raw"http://127.0.0.1/mcp\escape",
        "http://127.0.0.1/mcp with space", "http://127.0.0.1/mcp?token=secret",
        "http://127.0.0.1/mcp#fragment", "http://localhost@remote.example/mcp",
        "https://user:secret@example.com/api.v2/mcp")
        @test_throws ArgumentError AdvisorConfig(endpoint = endpoint, allow_remote = true)
    end
    @test_throws ArgumentError AdvisorConfig(endpoint = "https://example.com/api.v2/mcp%20gateway")
    @test_throws ArgumentError AdvisorConfig(
        endpoint = "http://example.com/api.v2/mcp%20gateway", allow_remote = true)
    @test AdvisorConfig(endpoint = "https://example.com/api.v2/mcp%20gateway",
        allow_remote = true).allow_remote
    for arguments in ((endpoint = "http://example.com", allow_remote = true),
        (endpoint = "https://user:secret@example.com",),
        (max_tokens = 0,), (timeout = Inf,), (protocol = "code()",),
        (provider_package = "A.B",), (api_key_env = "a=b",))
        @test_throws ArgumentError AdvisorConfig(; arguments...)
    end
    good = Dict(
        "cards" => [Dict(
            "evidence_id" => "e1", "explanation" => "Check allocations.")],
        "experiment_id" => "x1")
    @test PerfChecker._validate_narrative(good, ["e1"]; allowed_experiments = ["x1"])["experiment_id"] ==
          "x1"
    @test_throws ArgumentError PerfChecker._validate_narrative(good, ["e1"])
    @test_throws ArgumentError PerfChecker._validate_narrative(
        good, ["other"]; allowed_experiments = ["x1"])
    @test_throws ArgumentError PerfChecker._validate_narrative(
        Dict("cards" => [Dict("evidence_id" => "e1", "explanation" => " ")]), ["e1"])
    advice = Dict("schema_version" => "perfchecker-advice/1",
        "recommendations" => [
            Dict("id" => "e1", "rule_id" => "allocation",
            "hypothesis" => "Observed allocations", "action" => "Inspect copy",
            "validation" => "Repeat oracle and measurement", "location" => Dict("file" => "private-path"),
            "evidence" => Dict("raw" => "secret-log"))])
    bounded = PerfChecker._advisor_evidence(advice, AdvisorConfig())
    @test length(bounded) == 1
    @test !occursin("private-path", string(bounded)) &&
          !occursin("secret-log", string(bounded))
    @test_throws ArgumentError advisor_transport(Val(:absent), AdvisorConfig(), Dict())
    empty_advice = Dict("schema_version" => "perfchecker-advice/1", "recommendations" => [])
    @test narrate_advice(empty_advice)["status"] == "not_needed"
    @test_throws ArgumentError narrate_advice(empty_advice;
        experiments = [
            Dict("id" => "x", "purpose" => "a"), Dict("id" => "x", "purpose" => "b")])
    result = evaluate_advisors([Dict(
        "id" => "healthy", "advice" => empty_advice, "expected_rules" => String[])])
    @test only(result["results"])["false_positives"] == 0
    @test only(result["results"])["prose_truth"] == "requires_human_review"
    envelope = agent_evidence(narrate_advice(empty_advice))
    @test envelope["narrative_authority"] == "unverified_narrative"
    @test isempty(envelope["recommendations"])
end

@testitem "Bounded investigation preserves configured MCP decisions and limits" tags=[
    :integration, :advisor, :bounded_advisor] begin
    using PerfChecker, HTTP, Sockets
    project = dirname(Base.active_project())
    socket = listen(ip"127.0.0.1", 0)
    port = getsockname(socket)[2]
    close(socket)
    requests = Any[]
    calls = Ref(0)
    stop_after_first = Ref(false)
    instructions = "Select the second declared experiment; never invent an experiment."
    arguments = Dict("locale" => "English",
        "options" => Dict(
            "nested" => [Dict("enabled" => true)], "empty" => Any[]))
    encode(value) = sprint(io -> PerfChecker.JSON.print(io, value))
    server = HTTP.serve!("127.0.0.1", port; verbose = false) do request
        request.method == "DELETE" && return HTTP.Response(204)
        body = PerfChecker._json_parse(String(request.body))
        push!(requests, (body = body, headers = request.headers))
        method = body["method"]
        method == "notifications/initialized" && return HTTP.Response(202)
        result = if method == "initialize"
            Dict("protocolVersion" => "2025-11-25",
                "capabilities" => Dict("tools" => Dict()),
                "serverInfo" => Dict("name" => "bounded-test", "version" => "1"))
        elseif method == "tools/list"
            Dict("tools" => [Dict("name" => "choose_experiment",
                "inputSchema" => Dict("type" => "object",
                    "properties" => Dict(
                        "question" => Dict("type" => "string"),
                        "locale" => Dict("type" => "string"),
                        "options" => Dict("type" => "object")),
                    "required" => ["question", "locale", "options"]))])
        else
            calls[] += 1
            prompt = body["params"]["arguments"]["question"]
            evidence = PerfChecker._json_parse(last(split(
                prompt, "\n\nPerfChecker evidence:\n")))
            selection = stop_after_first[] && calls[] > 1 ? "stop" :
                        last(evidence["allowed_experiments"])["id"]
            Dict("structuredContent" => Dict("cards" => [], "experiment_id" => selection))
        end
        if method == "tools/list" && haskey(body["params"], "_meta")
            result = merge(Dict{String, Any}(result),
                Dict("resultType" => "complete", "ttlMs" => 0,
                    "cacheScope" => "private"))
        end
        headers = ["Content-Type" => "application/json"]
        method == "initialize" && push!(headers, "Mcp-Session-Id" => "bounded-session")
        HTTP.Response(200, headers,
            encode(Dict(
                "jsonrpc" => "2.0", "id" => body["id"], "result" => result)))
    end
    config(version) = AdvisorConfig(protocol = :mcp_http,
        endpoint = "http://127.0.0.1:$port/mcp", mcp_tool = "choose_experiment",
        mcp_prompt_argument = "question", mcp_arguments = arguments,
        mcp_version = version, mcp_response = :structured, instructions = instructions,
        model = "configured-model", max_tokens = 237, max_evidence_chars = 4321,
        timeout = 120)
    try
        # Compile the real POST handlers before measuring isolated worker deadlines.
        for version in ("2026-07-28", "2025-11-25")
            Base.invokelatest(advisor_transport, Val(:mcp_http), config(version),
                Dict("messages" => [Dict("content" => instructions),
                    Dict("content" => encode(Dict("evidence" => [],
                        "allowed_experiments" => [Dict(
                            "id" => "experiment-2", "purpose" => "readiness")])))]))
        end
        mktempdir() do root
            source = joinpath(root, "cases.jl")
            write(source,
                """
  make_case(p) = (prepare=()->2,
      operation=x->(write(p["marker"], string(getpid())); sleep(get(p, "delay", 0)); x*x),
      verify=(x,result)->result==4)
  function make_timeout_case(p)
      write(p["factory_marker"], string(getpid()))
      return make_case(p)
  end
  """)
            first_marker, chosen_marker = joinpath(root, "first"), joinpath(root, "chosen")
            catalog = ScenarioCatalog(root,
                [ScenarioSpec(id; source, factory = "make_case",
                     parameters = Dict("marker" => marker), collectors = [:benchmark])
                 for (id, marker) in (("first", first_marker), ("chosen", chosen_marker))])
            for version in ("2026-07-28", "2025-11-25")
                empty!(requests)
                calls[] = 0
                selected = config(version)
                before = deepcopy(PerfChecker._advisor_config(selected))
                result = investigate(
                    catalog; project, advisor = selected, tools = Symbol[],
                    samples = 1, max_experiments = 1, budget_seconds = 120)
                @test result["status"] == "budget_exhausted"
                @test result["limits"] ==
                      Dict("max_experiments" => 1, "budget_seconds" => 120)
                @test length(result["experiments"]) == length(result["runs"]) == 1
                @test only(result["experiments"])["id"] == "experiment-2"
                @test only(result["experiments"])["status"] == "complete"
                @test only(result["runs"])["scenario"]["id"] == "chosen"
                @test only(result["runs"])["qualification"]["correctness"] == "passed"
                @test only(result["decisions"])["status"] == "complete"
                @test only(result["decisions"])["experiment_id"] == "experiment-2"
                @test only(result["unexecuted"])["id"] == "experiment-1"
                @test isfile(chosen_marker) && !isfile(first_marker)
                @test PerfChecker._advisor_config(selected) == before
                tool_calls = filter(r -> r.body["method"] == "tools/call", requests)
                @test length(tool_calls) == 1
                call = only(tool_calls)
                @test call.body["params"]["name"] == selected.mcp_tool
                received = call.body["params"]["arguments"]
                @test received["locale"] == arguments["locale"]
                @test received["options"] == arguments["options"]
                @test startswith(received["question"], instructions)
                @test !haskey(received, "prompt")
                @test HTTP.header(HTTP.Request("POST", "/", call.headers),
                    "MCP-Protocol-Version") == version
                @test length(PerfChecker._json_parse(last(split(received["question"],
                    "\n\nPerfChecker evidence:\n")))["allowed_experiments"]) == 2
            end

            empty!(requests)
            calls[] = 0
            stop_after_first[] = true
            stopped = investigate(catalog; project, advisor = config("2026-07-28"),
                tools = Symbol[], samples = 1, max_experiments = 2, budget_seconds = 120)
            @test stopped["status"] == "advisor_stopped"
            @test length(stopped["experiments"]) == 1 && calls[] == 2
            @test last(stopped["decisions"])["experiment_id"] == "stop"
            @test !isfile(first_marker)

            empty!(requests)
            calls[] = 0
            stop_after_first[] = false
            rm(chosen_marker)
            factory_marker = joinpath(root, "chosen-factory")
            slow = ScenarioCatalog(root,
                [catalog.scenarios[1],
                    ScenarioSpec("chosen";
                        source, factory = "make_timeout_case",
                        parameters = Dict("marker" => chosen_marker,
                            "factory_marker" => factory_marker, "delay" => 120),
                        # BenchmarkTools execution is covered above; this case
                        # isolates the deadline on a sleeping operation via stdlib Profile.
                        collectors = [:profile])])
            bounded = investigate(slow; project, advisor = config("2026-07-28"),
                tools = Symbol[], samples = 1, max_experiments = 2,
                budget_seconds = 45, timeout = 120)
            @test bounded["status"] == "budget_exhausted"
            @test bounded["elapsed_seconds"] < 65
            @test only(bounded["decisions"])["status"] == "complete"
            @test only(bounded["experiments"])["status"] == "incomplete"
            @test only(bounded["runs"])["qualification"]["availability"] == "timeout"
            if !isfile(chosen_marker)
                phase = isfile(factory_marker) ? "factory entered; operation not entered" :
                        "factory not entered"
                @info "Bounded investigation did not enter its sleeping operation" phase elapsed_seconds=bounded["elapsed_seconds"] experiment_elapsed_seconds=only(bounded["experiments"])["elapsed_seconds"]
            end
            @test isfile(chosen_marker) && !isfile(first_marker)
            @test isfile(factory_marker)
            @test calls[] == 1 && length(bounded["unexecuted"]) == 1
            # Assert the actual worker has exited before mktempdir removes the fixture.
            # A missing marker remains a failed assertion, without a secondary ENOENT.
            worker_marker = isfile(chosen_marker) ? chosen_marker : factory_marker
            if isfile(worker_marker)
                pid = parse(Int, read(worker_marker, String))
                if isfile(chosen_marker) && isfile(factory_marker)
                    @test read(chosen_marker, String) == read(factory_marker, String)
                end
                if Sys.iswindows()
                    process_list = read(
                        ignorestatus(`tasklist /FI $("PID eq $pid") /FO CSV /NH`), String)
                    @test !occursin(",\"$pid\",", process_list)
                else
                    @test isempty(strip(read(ignorestatus(`ps -p $pid -o stat=`), String)))
                end
            end
        end
    finally
        close(server)
    end
end

@testitem "Unavailable scenarios and nonexecuting catalogue tools" tags=[:unit, :advisor] begin
    using PerfChecker
    Runtime = PerfChecker.SharedScenarioRuntime
    mktempdir() do root
        marker = joinpath(root, "executed")
        source = joinpath(root, "case.jl")
        write(source, "write($(repr(marker)), \"bad\")")
        spec = Dict("source" => source, "factory" => "case",
            "requirements" => ["PerfCheckerDeliberatelyAbsentDependency"])
        @test_throws Runtime.ScenarioUnavailable Runtime.load_case(spec)
        @test !isfile(marker)
        write(source,
            "make(p)=(prepare=()->1,operation=identity,verify=(s,r)->true,availability=()->(available=false,reason=\"No device\"))")
        @test_throws Runtime.ScenarioUnavailable Runtime.load_case(Dict(
            "source" => source, "factory" => "make"))
        path = joinpath(root, ".github", "workflows", "perf.yml")
        @test isfile(write_scenario_workflow(path))
        @test_throws ArgumentError write_scenario_workflow(path)
        discovered = discover(root)
        @test length(only(discovered["ci"])["configurations"]) == 3
        synced = scenario_sync(root)
        @test synced["authority"] == "proposal_only"
        @test !isfile(marker)
        tools = tool_catalog()
        @test length(tools["tools"]) >= 40
        @test all(t -> t["qualification"] == "not_checked", tools["tools"])
        @test !isempty(sprint(show, MIME"text/html"(), investigation_view(tools)))
        @test wait_investigation(launch_investigation(:tools; root))["status"] == "complete"
        @test wait_investigation(launch_investigation(:sync; root))["status"] == "complete"
        catalog = ScenarioCatalog(root,
            [ScenarioSpec(
                "available"; source, factory = "make", collectors = [:benchmark])])
        @test_throws ArgumentError investigate(catalog; max_experiments = 0)
        @test_throws ArgumentError investigate(catalog; budget_seconds = Inf)
        token = CancellationToken()
        cancel!(token)
        stopped = investigate(catalog; cancellation = token)
        @test stopped["status"] == "cancelled"
        @test isempty(stopped["experiments"]) && !isempty(stopped["unexecuted"])
        @test stopped["code_modified"] == false
    end
end
