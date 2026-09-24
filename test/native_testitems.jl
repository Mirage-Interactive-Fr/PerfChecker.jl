@testitem "Test item tags have explicit symmetric roles" tags=[:unit, :v1] begin
    using PerfChecker
    item(tags) = (name = "example", tags = tags)
    @test testitem_filter()(item([]))
    @test testitem_filter(:test)(item([]))
    @test !testitem_filter(:test)(item([:perf_only]))
    @test testitem_filter()(item([:perf_only]))
    @test !testitem_filter(:test)(item([:check_only]))
    @test testitem_filter()(item([:check_only]))
    @test testitem_filter(; tags = [:check_only])(item([:perf_only]))
    @test testitem_filter(; tags = [:perf_only])(item([:check_only]))
    @test !testitem_filter(; exclude_tags = [:check_only])(item([:perf_only]))
    @test !testitem_filter(; exclude_tags = [:perf_only])(item([:check_only]))
    @test !testitem_filter()(item([:test_only]))
    @test testitem_filter(:test)(item([:test_only]))
    @test testitem_filter(; tags = [:fast])(item([:fast, :custom]))
    @test !testitem_filter(; tags = [:fast])(item([]))
    @test !testitem_filter(; exclude_tags = [:network])(item([:network]))
    @test_throws ArgumentError testitem_filter(:unknown)
    @test_throws ArgumentError testitem_filter()(item([:test_only, :perf_only]))
    @test_throws ArgumentError testitem_filter()(item([:test_only, :check_only]))
end

@testitem "Native TestItemRunner items are measured without duplicate workloads" tags=[
    :v1, :integration] begin
    using PerfChecker, TestItemRunner
    mktempdir() do root
        marker = joinpath(root, "executed.txt")
        check_marker = joinpath(root, "check-executed.txt")
        write(joinpath(root, "items.jl"), """
        using TestItems
        error("top level must never be included")
        @testmodule Shared begin
            const value = 42
        end
        @testitem "shared" setup=[Shared] begin
            open($(repr(marker)), "a") do io
                println(io, "once")
            end
            @testset "nested" begin
                @test Shared.value == 42
            end
        end
        @testitem "perf" tags=[:perf_only] begin
            @test 1 == 1
        end
        @testitem "check" tags=[:check_only] skip=(get(ENV, "PERFCHECKER_TESTITEM_MODE", "") != "performance") begin
            write($(repr(check_marker)), "ran")
            @test 1 == 1
        end
        @testitem "functional" tags=[:test_only] begin
            error("not selected for perf")
        end
        @testitem "invalid" tags=[:negative] begin
            @test false
        end
        @testitem "skipped" tags=[:negative] skip=true begin
            error("skipped")
        end
        """)
        found = discover_testitems(root; exclude_tags = [:negative])
        @test !isfile(marker)
        @test Set(i["name"] for i in found["items"]) == Set(["shared", "perf", "check"])
        @test Set(i["name"]
        for i in discover_testitems(root; mode = :test, exclude_tags = [:negative])["items"]) ==
              Set(["shared", "functional"])
        @test Set(i["name"] for i in discover_testitems(root; tags = [:check_only])["items"]) ==
              Set(["perf", "check"])
        TestItemRunner.run_tests(root; filter = item -> item.name == "check")
        @test !isfile(check_marker)
        check_id = only(filter(i -> i["name"] == "check", found["items"]))["id"]
        @test run_testitems(root; ids = [check_id], timeout = 90)["passed"]
        @test read(check_marker, String) == "ran"
        id = only(filter(i -> i["name"] == "shared", found["items"]))["id"]
        result = run_testitems(root; ids = [id], timeout = 90)
        @test result["passed"]
        @test readlines(marker) == ["once"]
        sample = only(only(result["runs"])["samples"])
        @test sample["passes"] == 1
        @test sample["seconds"] >= 0
        @test sample["bytes"] >= 0
        @test_throws ArgumentError run_testitems(root; ids = ["unknown"])
        @test_throws ArgumentError run_testitems(root; ids = String[])
        negative = run_testitems(root; tags = [:negative], timeout = 90)
        @test !negative["passed"]
        @test all(r -> r["status"] == "not_validated", negative["runs"])
        @test readlines(marker) == ["once"]
    end
end

@testitem "Native profiling plans preserve arguments and scope" tags=[:unit, :v1] begin
    using PerfChecker
    plan = native_tool_plan(:memcheck, "script with spaces.jl";
        project = "project with spaces", output = "trace")
    @test "--smc-check=all-non-file" in plan["arguments"]
    @test "--trace-children=yes" in plan["arguments"]
    @test last(plan["arguments"]) == "script with spaces.jl"
    @test !plan["executed"]
    @test plan["qualification"] == "not_tested"
    @test Sys.islinux() || plan["availability"] == "unsupported_platform"
    @test_throws ArgumentError native_tool_plan(:unknown, "case.jl")
end
