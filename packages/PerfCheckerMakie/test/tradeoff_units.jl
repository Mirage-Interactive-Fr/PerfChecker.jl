@testitem "Tradeoff renderers use verified dimensions or mark legacy units unknown" tags=[:plots] begin
    using PerfChecker, PerfCheckerMakie, Makie, UnicodePlots
    data = [Dict{String, Any}("version" => "1.0.0", "bytes" => 2048.0, "time" => 400.0),
        Dict{String, Any}("version" => "1.1.0", "bytes" => 4096.0, "time" => 800.0)]
    for unit in ("ns", "s", nothing)
        options = Dict{String, Any}("unit" => "s+By")
        if unit !== nothing
            options["time_unit"] = unit
            options["allocation_unit"] = "By"
        end
        model = PerfChecker.PerformancePlot("units", :time_allocation_tradeoff,
            "Recorded tradeoff", "Unit regression fixture", Dict{String, Any}(), data, options)
        before = deepcopy(performance_plot_dict(model))
        figure = performance_figure(model)
        axis = only(filter(item -> item isa Axis, figure.content))
        expected_time = isnothing(unit) ? "unit unspecified" : unit
        expected_allocation = isnothing(unit) ? "unit unspecified" : "By"
        @test axis.ylabel[] == "wall time ($expected_time)"
        @test axis.xlabel[] == "allocation ($expected_allocation)"
        terminal = sprint(show, MIME"text/plain"(), terminal_plot(model))
        @test occursin("time ($expected_time)", terminal)
        @test performance_plot_dict(model) == before
    end
end

@testitem "Tradeoff annotations group coincident versions without changing points" tags=[:plots] begin
    using PerfChecker, PerfCheckerMakie, Makie
    data = [Dict{String, Any}("version" => version, "bytes" => bytes, "time" => time)
            for (version, bytes, time) in (("1.0.0", 100.0, 400.0),
        ("1.1.0", 100.0, 400.0), ("1.2.0", 200.0, 300.0))]
    model = PerfChecker.PerformancePlot("coincident", :time_allocation_tradeoff,
        "Coincident observations", "Regression fixture", Dict{String, Any}(), data,
        Dict{String, Any}("time_unit" => "ns", "allocation_unit" => "By"))
    before = deepcopy(performance_plot_dict(model))
    figure = performance_figure(model)
    axis = only(filter(item -> item isa Axis, figure.content))
    annotations = only(filter(item -> item isa Makie.Annotation, axis.scene.plots))
    labels = annotations.text[]
    @test length(labels) == 2
    @test "2 versions" in labels
    @test "1.2.0" in labels
    curve = only(filter(item -> item isa Makie.ScatterLines, axis.scene.plots))
    @test length(curve[1][]) == 3
    @test performance_plot_dict(model) == before
end

@testitem "Tradeoff labels fit the real Oxygen evidence without moving observations" tags=[:plots] begin
    using PerfChecker, PerfCheckerMakie, Makie
    path = joinpath(pkgdir(PerfChecker), "website", "src", "public", "examples",
        "real-packages", "oxygen-features", "time-allocation-tradeoff-d82dcc6c45ddfbd5.json")
    record = PerfChecker.JSON.parsefile(path)["plot"]
    model = PerfChecker.PerformancePlot(record["id"], Symbol(record["kind"]),
        record["title"], record["description"], record["encoding"], record["data"], record["options"])
    before = deepcopy(performance_plot_dict(model))
    figure = performance_figure(model)
    axis = only(filter(item -> item isa Axis, figure.content))
    annotations = only(filter(item -> item isa Makie.Annotation, axis.scene.plots))
    curve = only(filter(item -> item isa Makie.ScatterLines, axis.scene.plots))
    points = copy(curve[1][])
    @test length(points) == 14
    for (size, fontsize) in (((1100, 620), 12), ((760, 480), 16))
        resize!(figure.scene, size)
        annotations.fontsize = fontsize
        boxes = annotations.text_bbs[] .+ annotations.offsets[]
        extent = Makie.widths(axis.scene.viewport[])
        @test all(box -> all(minimum(box) .>= 0) && all(maximum(box) .<= extent), boxes)
        @test all(
            ((i, j),) -> !all(
                d -> minimum(boxes[i])[d] < maximum(boxes[j])[d] &&
                    minimum(boxes[j])[d] < maximum(boxes[i])[d],
                1:2),
            ((i, j) for i in eachindex(boxes) for j in (i + 1):length(boxes)))
        @test curve[1][] == points
        @test performance_plot_dict(model) == before
    end
end

@testitem "Tradeoff Core compatibility includes the required unit contract" tags=[:plots] begin
    using PerfChecker, PerfCheckerMakie
    project = PerfChecker.Pkg.Types.read_project(joinpath(
        pkgdir(PerfCheckerMakie), "Project.toml"))
    compatible = project.compat["PerfChecker"].val
    @test v"1.0.0" ∉ compatible
    @test v"1.0.1" in compatible
    @test pkgversion(PerfChecker) in compatible
    @test isdefined(PerfChecker, :_tradeoff_plot_units)
end
