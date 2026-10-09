@testitem "Allocation palettes render the real Oxygen sources beyond eight colors" tags=[:plots] begin
    using PerfChecker, PerfCheckerMakie, Makie
    palette = PerfCheckerMakie.make_colors(9)
    @test length(unique(palette)) == 9
    @test palette[1:8] == Makie.RGBf.(Makie.to_color.(PerfCheckerMakie._PLOT_PALETTE))
    path = joinpath(pkgdir(PerfChecker), "website", "src", "public", "examples",
        "real-packages", "oxygen-profiles", "allocation-lines-cdd3342245e37dc1.json")
    record = PerfChecker.JSON.parsefile(path)["plot"]
    model = PerfChecker.PerformancePlot(record["id"], Symbol(record["kind"]),
        record["title"], record["description"], record["encoding"], record["data"], record["options"])
    before = deepcopy(performance_plot_dict(model))
    @test length(unique(item["file"] for item in model.data)) == 9
    figure = performance_figure(model)
    axis = only(filter(item -> item isa Axis, figure.content))
    bars = only(filter(item -> item isa Makie.BarPlot, axis.scene.plots))
    @test length(bars[1][]) == length(model.data) == 31
    rectangles = only(filter(item -> item isa Makie.Poly, bars.plots))[1][]
    mesh = only(filter(item -> item isa Makie.Mesh, Makie.collect_atomic_plots([bars])))
    vertices = Makie.GeometryBasics.coordinates(mesh[1][])
    @test length(vertices) == 4length(model.data)
    for (index, row) in pairs(model.data)
        corners = vertices[(4index - 3):(4index)]
        @test minimum(last, corners) == 0
        @test maximum(last, corners) == row["bytes"]
        @test (minimum(first, corners) + maximum(first, corners)) / 2 ≈ index
        @test Makie.widths(rectangles[index])[2] == row["bytes"]
    end
    @test performance_plot_dict(model) == before

    edge_data = deepcopy(model.data)
    edge_data[1]["bytes"] = 0.0
    edge_data[2]["bytes"] = NaN
    edge = PerfChecker.PerformancePlot(model.id, model.kind, model.title,
        model.description, model.encoding, edge_data, model.options)
    finite = PerfCheckerMakie._finite_plot(edge)
    @test length(finite.data) == 30
    @test first(finite.data)["bytes"] == 0
    @test finite.data[2]["label"] == model.data[3]["label"]
    edge_figure = performance_figure(edge)
    edge_axis = only(filter(item -> item isa Axis, edge_figure.content))
    edge_bars = only(filter(item -> item isa Makie.BarPlot, edge_axis.scene.plots))
    edge_rectangles = only(filter(item -> item isa Makie.Poly, edge_bars.plots))[1][]
    @test length(edge_rectangles) == 30
    @test Makie.widths(first(edge_rectangles))[2] == 0
end
