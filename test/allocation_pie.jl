@testitem "Allocation pie groups small shares" tags=[:unit, :plots, :allocation_pie] begin
    using PerfChecker
    @test PerfChecker._short_source_path("/tmp/depot/packages/HTTP/abc12/src/parse.jl") == "HTTP/src/parse.jl"
    @test PerfChecker._short_source_path(raw"C:\depot\packages\Oxygen\abc12\src\handlers.jl") == "Oxygen/src/handlers.jl"
    @test PerfChecker._short_source_path("packages/Oxygen/src/handlers.jl") == "Oxygen/src/handlers.jl"
    records = [Dict{String, Any}("label" => "site $i", "bytes" => bytes,
        "version" => "1.0.0") for (i, bytes) in enumerate([80, 5, 4, 4, 4, 3])]
    grouped = PerfChecker._group_allocation_pie(records)
    @test [item["bytes"] for item in grouped] == [80, 5, 15]
    @test last(grouped)["label"] == "Other allocation sites"
    @test last(grouped)["grouped_sites"] == 4
    @test sum(item["percentage"] for item in grouped) ≈ 100
    @test all(!haskey(item, "percentage") for item in records)
    @test length(PerfChecker._group_allocation_pie(records; min_percentage=0)) == 6
    @test [item["bytes"] for item in PerfChecker._group_allocation_pie(records; top=2)] == [80, 20]
    small = [Dict{String, Any}("label" => "site $i", "bytes" => 1) for i in 1:21]
    @test only(PerfChecker._group_allocation_pie(small))["percentage"] == 100
    @test isempty(PerfChecker._group_allocation_pie(Dict{String, Any}[]))
    @test only(PerfChecker._group_allocation_pie([Dict{String, Any}("label" => "zero", "bytes" => 0)]))["percentage"] == 0
    for invalid in (-1, 101, NaN, Inf)
        @test_throws ArgumentError PerfChecker._group_allocation_pie(records; min_percentage=invalid)
    end
end
