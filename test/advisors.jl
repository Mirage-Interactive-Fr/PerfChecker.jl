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
    for arguments in ((endpoint = "http://example.com", allow_remote = true),
        (endpoint = "https://user:secret@example.com",),
        (max_tokens = 0,), (timeout = Inf,), (protocol = "code()",),
        (provider_package = "A.B",), (api_key_env = "a=b",))
        @test_throws ArgumentError AdvisorConfig(; arguments...)
    end
    good = Dict(
        "cards" => [Dict(
            "evidence_id" => "e1", "explanation" => "Vérifier les allocations.")],
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
