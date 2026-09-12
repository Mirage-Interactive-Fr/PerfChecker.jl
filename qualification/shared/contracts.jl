using Test, PerfChecker, TestItemRunner, JSON

@testset "Shared collection: discovery and CLI use the same items" begin
    mktempdir() do directory
        cp(joinpath(@__DIR__, "items.jl"), joinpath(directory, "items.jl"))
        api = discover_testitems(directory)
        @test api["executed"] === false
        @test sort([i["name"] for i in api["items"]]) ==
              ["Only performance", "Shared assertion"]
        functional = discover_testitems(directory; mode = :test)
        @test sort([i["name"] for i in functional["items"]]) ==
              ["Only correctness", "Shared assertion"]
        output = joinpath(directory, "catalog.json")
        @test perfchecker_main([
            "testitems", "--root=$directory", "--list", "--output=$output"]) == 0
        cli = JSON.parsefile(output)
        @test [(i["id"], i["name"]) for i in cli["items"]] ==
              [(i["id"], i["name"]) for i in api["items"]]
        @test_throws ArgumentError run_testitems(directory; ids = ["unknown"])
        @test !testitem_filter(:test)((name = "only", tags = [:perf_only]))
        @test !testitem_filter(:performance)((name = "only", tags = [:test_only]))
    end
end
