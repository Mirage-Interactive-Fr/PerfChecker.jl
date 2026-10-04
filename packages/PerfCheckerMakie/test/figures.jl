@testitem "Makie consumes the shared plot contract" begin
    using PerfChecker, PerfCheckerMakie, Makie
    plot = PerfChecker.PerformancePlot("empty", :allocation_flamegraph,
        "Allocations", "No captured allocations", Dict{String, Any}(),
        Dict{String, Any}[], Dict{String, Any}(
            "selected_version" => "demo", "value_label" => "bytes"))
    @test performance_figure(plot) isa Makie.Figure
end
