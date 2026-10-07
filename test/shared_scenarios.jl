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

@testitem "Discovery ignores strings that are not filesystem paths" tags=[
    :unit, :shared_scenarios] begin
    using PerfChecker, SHA
    mktempdir() do parent
        root = joinpath(parent, "package")
        directory = joinpath(root, "test")
        mkpath(directory)
        fixture = joinpath(directory, "fixture.txt")
        write(fixture, "real fixture")
        outside = joinpath(parent, "outside.txt")
        write(outside, "outside the discovery root")
        source = joinpath(directory, "runtests.jl")
        descriptions = (repeat("x", 300), repeat("é", 200), "embedded\0NUL")
        write(source,
            join(
                ["description_$i = $(repr(text))" for (i, text) in enumerate(descriptions)],
                '\n') * "\n" * """
             fixture = "fixture.txt"
             outside = $(repr(relpath(outside, directory)))
             @test 1 == 1
             """)
        result = discover(root)
        @test length(result["candidates"]) == 1
        @test collect(keys(result["fixtures"])) == ["test/fixture.txt"]
        @test result["fixtures"]["test/fixture.txt"] == bytes2hex(sha256(read(fixture)))
        @test isempty(result["warnings"])
        @test scenario_sync(root)["schema_version"] == "perfchecker-scenario-sync/1"

        # A long complete path remains valid when its individual components are
        # valid; do not impose a guessed byte limit on Julia string literals.
        if Sys.isunix()
            nested = joinpath(directory, repeat("a", 90), repeat("b", 90), repeat("c", 90))
            mkpath(nested)
            long_fixture = joinpath(nested, "fixture.txt")
            write(long_fixture, "long valid path")
            open(source, "a") do io
                println(io, "long_fixture = ", repr(relpath(long_fixture, directory)))
            end
            result = discover(root)
            relative = replace(relpath(long_fixture, root), '\\' => '/')
            @test haskey(result["fixtures"], relative)
            @test result["fixtures"][relative] == bytes2hex(sha256(read(long_fixture)))

            # Preserve useful failures such as filesystem loops, rather than
            # treating every I/O error as a string that was not a filename.
            symlink("cycle", joinpath(directory, "cycle"))
            open(source, "a") do io
                println(io, "cycle = \"cycle\"")
            end
            failure = try
                discover(root)
                nothing
            catch error
                error
            end
            @test failure isa Base.IOError
            @test failure.code == Base.UV_ELOOP
            @test occursin(joinpath(directory, "cycle"), sprint(showerror, failure))
        end
    end
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
    @test occursin("Benchmark", item["action"])
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
