using Test
using PerfChecker

root = pkgdir(PerfChecker)
example = joinpath(root, "examples", "shared-scenarios")
project = dirname(Base.active_project())
catalog = load_scenario_catalog(joinpath(example, "scenarios.toml"))
output = get(ENV, "PERFCHECKER_SHARED_REPORTS", mktempdir())

@testset "Shared cases from tests to isolated measurements" begin
    include(joinpath(example, "test", "runtests.jl"))
    discovery = discover(example)
    @test length(discovery["declared"]) == 3
    @test !isempty(discovery["candidates"])
    write_investigation_report(discovery, joinpath(output, "discovery"); force = true)
    bundles = run_scenarios(catalog; project, samples = 3, timeout = 180,
        reports = joinpath(output, "bundles"))
    @test length(bundles) == 7
    for bundle in bundles
        @test bundle_passed(bundle)
        @test bundle.manifest["qualification"]["correctness"] == "passed"
        path = joinpath(output, "bundles", bundle.manifest["run_id"])
        @test verify_run_bundle(path)["verified"]
        @test read_run_bundle(path).observations == bundle.observations
    end
    comparisons = compare_scenarios(bundles, bundles; min_samples = 3)
    @test length(comparisons["configurations"]) == 7
    missing = compare_scenarios(bundles, bundles[1:1])
    @test count(r -> r["status"] == "not_tested", missing["configurations"]) == 6
    write_investigation_report(
        advise(first(bundles)), joinpath(output, "advice"); force = true)
    io = IOBuffer()
    @test perfchecker_main(
        ["advise",
            "--bundle=" * joinpath(output, "bundles", first(bundles).manifest["run_id"])];
        stdout = io) == 0
    @test perfchecker_main(
        ["advise", "--source=" * joinpath(output, "bundles")]; stdout = IOBuffer()) == 0
    comparison_io = IOBuffer()
    @test perfchecker_main(
        ["compare", "--scenarios", "--baseline=" * joinpath(output, "bundles"),
            "--candidate=" * joinpath(output, "bundles"), "--min-samples=3"];
        stdout = comparison_io) == 0
    @test length(PerfChecker._json_parse(String(take!(comparison_io)))["configurations"]) ==
          7
    run_report = Dict("schema_version" => "perfchecker-scenario-run/1",
        "runs" => PerfChecker._scenario_run_record.(bundles))
    @test all(r -> r["collector"] != "unknown", run_report["runs"])
    write_investigation_report(run_report, joinpath(output, "run"); force = true)
    @test occursin("median", read(joinpath(output, "run", "run.md"), String))
end

@testset "Worker failure, timeout and cancellation" begin
    mktempdir() do directory
        source = joinpath(directory, "cases.jl")
        write(source, """
        make_case(p) = (prepare=()->[1], operation=x->(sleep(30); x), verify=(x,r)->true)
        """)
        slow = ScenarioCatalog(example, [ScenarioSpec("slow"; source)])
        for _ in 1:3
            result = run_scenarios(slow; project, timeout = 0.5, samples = 1)
            @test only(result).manifest["qualification"]["availability"] == "timeout"
        end
        token = CancellationToken()
        timer = Timer(0.5) do _
            cancel!(token)
        end
        try
            result = run_scenarios(
                slow; project, timeout = 30, cancellation = token, samples = 1)
            @test only(result).manifest["qualification"]["availability"] == "cancelled"
        finally
            close(timer)
        end
        write(source,
            "make_case(p) = (prepare=()->[1], operation=identity, verify=(x,r)->false)\n")
        invalid = run_scenarios(slow; project, timeout = 60, samples = 1)
        @test !bundle_passed(only(invalid))
        @test only(invalid).manifest["qualification"]["correctness"] == "failed"
    end
end

if get(ENV, "PERFCHECKER_TEST_ANALYZERS", "false") == "true"
    @testset "Real optional analyzers" begin
        selected = ScenarioCatalog(example, catalog.scenarios[1:1])
        diagnosis = diagnose(selected; project, timeout = 300)
        write_investigation_report(diagnosis, joinpath(output, "diagnosis"); force = true)
        @test length(diagnosis["records"]) == 5
        for record in diagnosis["records"]
            @test record["status"] == "complete"
        end
        write_investigation_report(
            advise(diagnosis), joinpath(output, "diagnostic-advice"); force = true)
    end
end
