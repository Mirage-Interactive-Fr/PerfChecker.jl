@testitem "Makie consumes the shared plot contract" begin
    using PerfChecker, PerfCheckerMakie, Makie
    plot = PerfChecker.PerformancePlot("empty", :allocation_flamegraph,
        "Allocations", "No captured allocations", Dict{String, Any}(),
        Dict{String, Any}[], Dict{String, Any}(
            "selected_version" => "demo", "value_label" => "bytes"))
    @test performance_figure(plot) isa Makie.Figure
end

@testitem "Flame frames preserve recorded geometry and shared diagnostic colors" tags=[
    :plots, :flamegraph] begin
    using PerfChecker, PerfCheckerMakie, Makie
    for (filename, count) in (("cpu-flamegraph-0bf86e14522bb509.json", 86),
        ("wall-flamegraph-1d1ccc603e7534c8.json", 64),
        ("allocation-flamegraph-762692b0102f2fc2.json", 350))
        path = joinpath(pkgdir(PerfChecker), "website", "src", "public", "examples",
            "real-packages", "oxygen-profiles", filename)
        record = PerfChecker.JSON.parsefile(path)["plot"]
        model = PerfChecker.PerformancePlot(
            record["id"], Symbol(record["kind"]), record["title"],
            record["description"], record["encoding"], record["data"], record["options"])
        before = deepcopy(performance_plot_dict(model))
        figure = performance_figure(model)
        axis = only(filter(item -> item isa Axis, figure.content))
        bars = only(filter(item -> item isa Makie.BarPlot, axis.scene.plots))
        rectangles = only(filter(item -> item isa Makie.Poly, bars.plots))[1][]
        colors = PerfCheckerMakie._flame_colors(model)
        @test length(rectangles) == length(colors) == count
        for (index, row) in pairs(model.data)
            rectangle = rectangles[index]
            @test minimum(rectangle)[1]≈100row["x0"] atol=1e-5
            @test maximum(rectangle)[1]≈100row["x1"] atol=1e-5
            @test Makie.widths(rectangle)[1]≈100(row["x1"] - row["x0"]) atol=1e-5
            tooltip = PerfCheckerMakie._flame_tooltip(row, model)
            @test occursin(string(row["value"]), tooltip)
            @test occursin(join(row["path"], " → "), tooltip)
            if haskey(PerfCheckerMakie._FLAME_STATUS_COLORS, row["status"])
                @test colors[index] == PerfCheckerMakie._FLAME_STATUS_COLORS[row["status"]]
            end
        end
        @test performance_plot_dict(model) == before
    end
end

@testitem "Flame labels fit native pixel bounds and actual bar colors" tags=[
    :plots, :flamegraph] begin
    using PerfChecker, PerfCheckerMakie, Makie
    source = joinpath(pkgdir(PerfChecker),
        "website/src/public/examples/real-packages/oxygen-profiles/allocation-flamegraph-762692b0102f2fc2.json")
    record = PerfChecker.JSON.parsefile(source)["plot"]
    model = PerfChecker.PerformancePlot(
        record["id"], Symbol(record["kind"]), record["title"],
        record["description"], record["encoding"], record["data"], record["options"])
    before = deepcopy(performance_plot_dict(model))
    @test length(model.data) == 350
    figure = performance_figure(model)
    axis = only(filter(item -> item isa Axis, figure.content))
    bars = only(filter(item -> item isa Makie.BarPlot, axis.scene.plots))
    rectangles = only(filter(item -> item isa Makie.Poly, bars.plots))[1][]
    geometry = deepcopy(rectangles)
    labels = filter(item -> item isa Makie.Text, axis.scene.plots)
    @test length(labels) == 350
    function check_labels()
        visible = 0
        for (index, label) in pairs(labels)
            @test only(label.text[]) == model.data[index]["label"]
            label.visible[] || continue
            visible += 1
            bounds = Makie.full_boundingbox(label, :pixel)
            first_corner = Makie.project(
                axis.scene, :data, :pixel, minimum(rectangles[index]))
            last_corner = Makie.project(
                axis.scene, :data, :pixel, maximum(rectangles[index]))
            lower, upper = min.(first_corner, last_corner), max.(first_corner, last_corner)
            for dimension in 1:2
                @test minimum(bounds)[dimension] >= max(0, lower[dimension]) + 2 - 1e-5
                @test maximum(bounds)[dimension] <=
                      min(
                    Makie.widths(axis.scene.viewport[])[dimension], upper[dimension]) - 2 +
                      1e-5
            end
        end
        return visible
    end
    default_labels = check_labels()
    @test 0 < default_labels < 350
    resize!(figure.scene, (900, 480))
    @test 0 <= check_labels() < default_labels
    xlims!(axis, 20, 80)
    ylims!(axis, 10, 20)
    @test 0 < check_labels() < 350
    @test only(filter(item -> item isa Makie.Poly, bars.plots))[1][] == geometry
    for (fill, background, expected) in ((:black, :white, RGBf(1, 1, 1)),
        (:white, :black, RGBf(0, 0, 0)), (RGBAf(1, 1, 1, 0.1), :black, RGBf(1, 1, 1)))
        custom = performance_figure(model; plot_kwargs = (; color = fill),
            axis_kwargs = (; backgroundcolor = background),
            figure_kwargs = (; size = (900, 480)))
        @test size(custom.scene) == (900, 480)
        custom_axis = only(filter(item -> item isa Axis, custom.content))
        custom_labels = filter(item -> item isa Makie.Text, custom_axis.scene.plots)
        @test all(label -> RGBf(label.color[]) == expected, custom_labels)
        custom_bars = only(filter(item -> item isa Makie.BarPlot, custom_axis.scene.plots))
        @test only(filter(item -> item isa Makie.Poly, custom_bars.plots))[1][] == geometry
        if fill === :black
            custom_bars.color = :white
            @test all(label -> RGBf(label.color[]) == RGBf(0, 0, 0), custom_labels)
            custom_bars.color = :black
            @test all(label -> RGBf(label.color[]) == RGBf(1, 1, 1), custom_labels)
            custom_bars.alpha = 0.05
            @test all(label -> RGBf(label.color[]) == RGBf(0, 0, 0), custom_labels)
        end
    end
    mapped = performance_figure(model;
        plot_kwargs = (; color = collect(1:350),
            colormap = [:black, :white], colorrange = (1, 350)))
    mapped_axis = only(filter(item -> item isa Axis, mapped.content))
    mapped_bars = only(filter(item -> item isa Makie.BarPlot, mapped_axis.scene.plots))
    mapped_labels = filter(item -> item isa Makie.Text, mapped_axis.scene.plots)
    @test RGBf(first(mapped_labels).color[]) == RGBf(1, 1, 1)
    @test RGBf(last(mapped_labels).color[]) == RGBf(0, 0, 0)
    mapped_bars.colormap = [:white, :black]
    @test RGBf(first(mapped_labels).color[]) == RGBf(0, 0, 0)
    @test RGBf(last(mapped_labels).color[]) == RGBf(1, 1, 1)
    @test performance_plot_dict(model) == before
end
