@testitem "Legacy allocation pies share the grouping threshold" tags=[:plots, :allocation_pie] begin
    using PerfChecker, PerfCheckerMakie
    using PerfCheckerMakie: Makie
    table = PerfChecker.Table(filename=fill("src/example.jl", 6), line=collect(1:6),
        bytes=[80, 5, 4, 4, 4, 3])
    for (threshold, count) in ((5, 3), (0, 6))
        figure = table_to_pie(table, Val(:alloc); min_percentage=threshold)
        axis = only(filter(item -> item isa Makie.Axis, figure.content))
        pie = only(filter(item -> item isa Makie.Pie, axis.scene.plots))
        @test length(pie[3][]) == count
        @test sum(pie[3][]) == 100
    end
    result = PerfChecker.CheckerResult([table], nothing, nothing,
        [PerfChecker.PackageSpec(name="Demo", version=v"1.0.0")])
    figure = last(only(checkres_to_pie(result, Val(:alloc); min_percentage=0)))
    axis = only(filter(item -> item isa Makie.Axis, figure.content))
    @test length(only(filter(item -> item isa Makie.Pie, axis.scene.plots))[3][]) == 6
end
