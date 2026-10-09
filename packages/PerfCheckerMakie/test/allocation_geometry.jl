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

@testitem "Allocation heatmaps preserve observed cells and leave absent pairs unmeasured" tags=[:plots] begin
    using PerfChecker, PerfCheckerMakie, Makie
    path = joinpath(pkgdir(PerfChecker), "website", "src", "public", "examples",
        "real-packages", "oxygen-profiles", "allocation-heatmap-fd88b8007532c93e.json")
    record = PerfChecker.JSON.parsefile(path)["plot"]
    model = PerfChecker.PerformancePlot(record["id"], Symbol(record["kind"]),
        record["title"], record["description"], record["encoding"], record["data"], record["options"])
    before = deepcopy(performance_plot_dict(model))
    @test length(model.data) == 31
    figure = performance_figure(model)
    axis = only(filter(item -> item isa Axis, figure.content))
    heat = only(filter(item -> item isa Makie.Heatmap, axis.scene.plots))
    matrix = heat[3][]
    @test size(matrix) ==
          (length(model.options["versions"]), length(model.options["labels"]))
    @test count(isfinite, matrix) == 31
    for row in model.data
        x = findfirst(==(row["version"]), model.options["versions"])
        y = findfirst(==(row["label"]), model.options["labels"])
        @test matrix[x, y] ≈ row["bytes"]
    end
    @test performance_plot_dict(model) == before

    options = merge(model.options,
        Dict("versions" => ["1.0.0", "1.1.0"],
            "labels" => ["src/a.jl:10", "src/b.jl:20"], "missing_cell_policy" => "not_observed"))
    data = [
        Dict{String, Any}("version" => "1.0.0", "label" => "src/a.jl:10", "bytes" => 120.0),
        Dict{String, Any}("version" => "1.1.0", "label" => "src/b.jl:20", "bytes" => 0.0)]
    for reversed in (false, true)
        ordered_options = reversed ?
                          merge(options,
            Dict("versions" => reverse(options["versions"]),
                "labels" => reverse(options["labels"]))) : options
        ordered_data = reversed ? reverse(data) : data
        sparse = PerfChecker.PerformancePlot(model.id, model.kind, model.title,
            model.description, model.encoding, ordered_data, ordered_options)
        saved = deepcopy(performance_plot_dict(sparse))
        sparse_figure = performance_figure(sparse)
        sparse_axis = only(filter(item -> item isa Axis, sparse_figure.content))
        sparse_heat = only(filter(item -> item isa Makie.Heatmap, sparse_axis.scene.plots))
        values = sparse_heat[3][]
        @test size(values) == (2, 2)
        @test count(isfinite, values) == 2
        @test count(isnan, values) == 2
        @test Makie.to_color(sparse_heat.nan_color[]) == Makie.to_color(:transparent)
        for row in ordered_data
            x = findfirst(==(row["version"]), ordered_options["versions"])
            y = findfirst(==(row["label"]), ordered_options["labels"])
            @test values[x, y] == row["bytes"]
            @test isnan(values[3 - x, y])
        end
        @test performance_plot_dict(sparse) == saved
    end
    duplicated = PerfChecker.PerformancePlot(model.id, model.kind, model.title,
        model.description, model.encoding, [data; [first(data)]], options)
    @test_throws ArgumentError performance_figure(duplicated)
end

@testitem "Stacked allocation files retain recorded rows and native segment bounds" tags=[:plots] begin
    using PerfChecker, PerfCheckerMakie, Makie
    path = joinpath(pkgdir(PerfChecker), "website", "src", "public", "examples",
        "real-packages", "oxygen-profiles", "allocation-files-b8a643aada0ef878.json")
    record = PerfChecker.JSON.parsefile(path)["plot"]
    model = PerfChecker.PerformancePlot(record["id"], Symbol(record["kind"]),
        record["title"], record["description"], record["encoding"], record["data"], record["options"])
    before = deepcopy(performance_plot_dict(model))
    @test length(model.data) == 9
    # Reverse the real records to verify that stack order does not replace row identity.
    for data in (model.data, reverse(model.data))
        variant = PerfChecker.PerformancePlot(model.id, model.kind, model.title,
            model.description, model.encoding, data, model.options)
        figure = performance_figure(variant)
        axis = only(filter(item -> item isa Axis, figure.content))
        Makie.update_state_before_display!(figure)
        @test axis.yscale[] === identity
        @test minimum(axis.finallimits[])[2] == 0
        bars = only(filter(item -> item isa Makie.BarPlot, axis.scene.plots))
        rectangles = only(filter(item -> item isa Makie.Poly, bars.plots))[1][]
        mesh = only(filter(item -> item isa Makie.Mesh, Makie.collect_atomic_plots([bars])))
        vertices = Makie.GeometryBasics.coordinates(mesh[1][])
        @test length(vertices) == 4length(data)
        @test length(rectangles) == length(data)
        for (index, row) in pairs(data)
            lower = sum(
                (item["bytes"]
                for item in data
                if item["version"] == row["version"] && item["file"] < row["file"]);
                init = 0.0)
            corners = vertices[(4index - 3):(4index)]
            @test minimum(last, corners) ≈ lower
            @test maximum(last, corners) ≈ lower + row["bytes"]
            @test Makie.widths(rectangles[index])[2] ≈ row["bytes"]
            @test (minimum(first, corners) + maximum(first, corners)) / 2 ≈ 1
        end
    end
    @test performance_plot_dict(model) == before
    edge_data = deepcopy(model.data)
    edge_data[1]["bytes"] = 0.0
    edge_data[2]["bytes"] = NaN
    edge = PerfChecker.PerformancePlot(model.id, model.kind, model.title,
        model.description, model.encoding, edge_data, model.options)
    finite = PerfCheckerMakie._finite_plot(edge)
    @test length(finite.data) == 8
    @test first(finite.data)["bytes"] == 0
    @test finite.data[2]["file"] == model.data[3]["file"]
    figure = performance_figure(edge)
    axis = only(filter(item -> item isa Axis, figure.content))
    bars = only(filter(item -> item isa Makie.BarPlot, axis.scene.plots))
    rectangles = only(filter(item -> item isa Makie.Poly, bars.plots))[1][]
    @test length(rectangles) == 8
    @test Makie.widths(first(rectangles))[2] == 0
end
