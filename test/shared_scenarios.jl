@testitem "Shared scenario lifecycle" tags=[:unit, :shared_scenarios] begin
    using PerfChecker
    const Runtime = PerfChecker.SharedScenarioRuntime
    prepared, cleaned = Ref(0), Ref(0)
    case = (prepare = () -> (prepared[] += 1; [3, 1, 2]),
        operation = x -> (x[1] == 3 || error("state reused"); sort!(x)),
        verify = (x, result) -> result === x && result == [1, 2, 3],
        cleanup = x -> (cleaned[] += 1))
    for _ in 1:3
        Runtime.once(case)
    end
    @test prepared[] == cleaned[] == 3
    bad = merge(case, (operation = x -> error("operation failed"),))
    @test_throws Runtime.ScenarioFailure Runtime.once(bad)
    @test prepared[] == cleaned[] == 4
    bad = merge(case, (verify = (x, result) -> false,))
    @test_throws Runtime.ScenarioFailure Runtime.once(bad)
    @test prepared[] == cleaned[] == 5
    async_case = (prepare = () -> Ref(0), operation = x -> (@async (yield(); x[] = 42)),
        synchronize = (x, task) -> wait(task), verify = (x, task) -> istaskdone(task) &&
            x[] == 42)
    Runtime.once(async_case)
    @test true
end

@testitem "Discovery is static and tracks drift" tags=[:unit, :shared_scenarios] begin
    using PerfChecker
    mktempdir() do root
        mkpath(joinpath(root, "test"))
        marker = joinpath(root, "executed")
        file = joinpath(root, "test", "runtests.jl")
        write(joinpath(root, "test", "fixture.txt"), "fixture")
        write_property_corpus(joinpath(root, "test", "corpus.json"), [1, 2, 3])
        write(file, """
        write($(repr(marker)), "bad")
        using Test
        input = read("fixture.txt", String)
        corpus = "corpus.json"
        @testset "parser" begin
            @test parse(Int, "42") == 42
            @test_throws ArgumentError parse(Int, "no")
        end
        include(ENV["UNTRUSTED_PATH"])
        """)
        first = discover(root)
        @test !isfile(marker)
        @test length(first["candidates"]) == 2
        @test all(c -> c["status"] == "proposed", first["candidates"])
        @test !isempty(first["warnings"])
        @test haskey(first["fixtures"], "test/fixture.txt")
        @test only(first["corpora"])["count"] == 3
        @test occursin("parse", first["candidates"][1]["operation_candidate"])
        write(joinpath(root, "test", "fixture.txt"), "changed")
        second = discover(root; previous = first)
        @test any(c -> c["file"] == "test/fixture.txt" && c["status"] == "changed",
            second["changes"])
        @test length(only(filter(
            c -> c["file"] == "test/fixture.txt", second["changes"]))["affected_candidates"]) ==
              2
        @test_throws ArgumentError discover(
            root; previous = Dict("schema_version" => "unknown"))
        output = joinpath(root, "reports")
        paths = write_investigation_report(second, output)
        @test all(isfile, paths)
        @test_throws ArgumentError write_investigation_report(second, output)
    end
end

@testitem "Literal CI matrix and unresolved workflows" tags=[:unit, :shared_scenarios] begin
    using PerfChecker
    mktempdir() do root
        directory = joinpath(root, ".github", "workflows")
        mkpath(directory)
        write(joinpath(directory, "ci.yml"), """
        jobs:
          tests:
            runs-on: ubuntu-latest
            strategy:
              matrix:
                os: [ubuntu-latest, windows-latest]
                julia: ['1.10', '1']
                exclude:
                  - os: windows-latest
                    julia: '1.10'
                include:
                  - os: macos-latest
                    julia: '1'
          remote:
            uses: someone/workflow@main
          dynamic:
            strategy:
              matrix: \${{ fromJSON(needs.prepare.outputs.matrix) }}
        """)
        result = discover(root)
        testjob = only(filter(c -> c["job"] == "tests", result["ci"]))
        @test length(testjob["configurations"]) == 4
        @test length(result["warnings"]) == 2
    end
end

@testitem "Shared measurement collectors reset mutable inputs" tags=[
    :integration, :shared_scenarios] begin
    using PerfChecker
    using BenchmarkTools
    using Chairmarks
    const Runtime = PerfChecker.SharedScenarioRuntime
    prepared, cleaned = Ref(0), Ref(0)
    case = (prepare = () -> (prepared[] += 1; [3, 1, 2]),
        operation = x -> (x[1] == 3 || error("state reused"); sort!(x)),
        verify = (x, result) -> result == [1, 2, 3],
        cleanup = x -> (cleaned[] += 1))
    for collector in ("benchmark", "chairmark", "profile_alloc", "profile")
        result = Runtime.execute_loaded(case, collector, 3)
        @test result["status"] == "complete"
        @test prepared[] == cleaned[]
        collector in ("benchmark", "chairmark") && @test length(result["samples"]) == 3
    end
end

@testitem "Deterministic advice preserves uncertainty" tags=[:unit, :shared_scenarios] begin
    using PerfChecker
    record = Dict{String, Any}(
        "scenario" => "sum", "implementation" => "cpu", "tool" => "jet",
        "status" => "complete", "findings" => [Dict(
            "rule_id" => "inference.runtime_dispatch",
            "message" => "runtime dispatch")])
    diagnosis = Dict("schema_version" => "perfchecker-diagnosis/1", "records" => [record])
    report = advise(diagnosis)
    @test length(report["recommendations"]) == 1
    item = only(report["recommendations"])
    @test item["predicted_gain"] == "not_measured"
    @test occursin("Mesurer", item["action"])
    @test report == advise(diagnosis)
    record["findings"] = []
    @test isempty(advise(diagnosis)["recommendations"])
    record["status"] = "unavailable"
    @test only(advise(diagnosis)["recommendations"])["rule_id"] == "evidence.analyzer"
    @test agent_evidence(diagnosis)["authority"] == "advisory_only"
end

@testitem "Scenario catalog rejects ambiguous identities" tags=[:unit, :shared_scenarios] begin
    using PerfChecker
    source = joinpath(pkgdir(PerfChecker), "examples", "shared-scenarios", "cases.jl")
    first = ScenarioSpec("sort"; source, factory = "SharedCases.sorting")
    second = ScenarioSpec(
        "sort"; source, factory = "SharedCases.sorting", implementation = "other")
    @test length(ScenarioCatalog(dirname(source), [first, second]).scenarios) == 2
    @test_throws ArgumentError ScenarioCatalog(dirname(source), [first, first])
    @test_throws ArgumentError ScenarioSpec("sort"; source, factory = "eval(1)")
    @test_throws ArgumentError ScenarioSpec("sort"; source, collectors = [:unknown])
    catalog = load_scenario_catalog(joinpath(dirname(source), "scenarios.toml"))
    @test length(catalog.scenarios) == 3
    token = CancellationToken()
    cancel!(token)
    result = PerfChecker._scenario_process(Dict(); project = pkgdir(PerfChecker),
        timeout = 1, cancellation = token)
    @test result["status"] == "cancelled"
end
