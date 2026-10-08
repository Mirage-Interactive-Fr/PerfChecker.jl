@testitem "Makie labels, attributes and safe real exports" tags=[:plots, :exports] begin
    using PerfChecker, PerfCheckerMakie, CairoMakie
    using PerfCheckerMakie: Makie
    CairoMakie.activate!()
    # Match to_table(Chairmarks.Benchmark): GC is a fraction and bytes_or_memory
    # is an alias of bytes, not a fifth independent metric.
    table = PerfChecker.Table(times = [1.0, 4.0, 2.0], gctimes = [0.0, 0.1, 0.0],
        bytes_or_memory = [10.0, 20.0, 15.0], bytes = [10.0, 20.0, 15.0], allocs = [
            1.0, 2.0, 1.0])
    result = PerfChecker.CheckerResult([table, table], nothing, [:small, :validated],
        [PerfChecker.PackageSpec(name = "Demo", version = v"1.0.0"),
            PerfChecker.PackageSpec(name = "Demo", version = v"1.0.1")])
    for (backend, tool) in ((:benchmark, "BenchmarkTools"), (:chairmark, "Chairmarks"))
        # Match to_table(BenchmarkTools.Trial): timing columns are ns and the
        # allocation totals are repeated scalars called memory and allocs.
        benchmark_table = PerfChecker.Table(times = [1.0e6, 4.0e6, 2.0e6],
            gctimes = [0.0, 1.0e5, 0.0], bytes_or_memory = fill(16, 3),
            memory = fill(16, 3), allocs = fill(2, 3))
        backend_result = backend === :benchmark ?
                         PerfChecker.CheckerResult(
            [benchmark_table, benchmark_table], nothing, result.tags, result.pkgs) : result
        figures = checkres_figures(backend_result, Val(backend))
        @test length(figures) == 5
        @test length(unique(first.(figures))) == 5
        expected = backend === :benchmark ?
                   ["Elapsed time (ns)", "GC time (ns)",
            "Allocated memory (bytes)", "Allocation count"] :
                   ["Elapsed time (s)", "GC fraction (unitless)",
            "Allocated memory (bytes)", "Allocation count"]
        @test [only(filter(item -> item isa Axis, last(pair).content)).ylabel[]
               for pair in figures[2:end]] == expected
        @test all(pair -> !occursin("bytes_or_memory", first(pair)), figures)
        for (_, figure) in figures
            axis = only(filter(item -> item isa Axis, figure.content))
            @test occursin(tool, axis.title[])
            @test axis.subtitle[] == "Tags: small, validated"
            @test axis.xticklabelrotation[] ≈ pi / 2
            @test length(unique(vec(Makie.colorbuffer(figure)))) > 20
        end
        mktempdir() do directory
            paths = saveplot(directory, figures; format = :png, px_per_unit = 1)
            @test length(paths) == 5
            @test length(unique(basename.(paths))) == 5
            for path in paths
                @test read(path)[1:8] ==
                      UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
                @test length(unique(vec(Makie.FileIO.load(path)))) > 20
            end
        end
        subset = checkres_figures(
            backend_result, Val(backend); kinds = [:distribution], metrics = [:allocs])
        @test length(subset) == 1
        @test endswith(first(only(subset)), "distribution_allocs")
        @test_throws ArgumentError checkres_figures(
            backend_result, Val(backend); metrics = [:times, :times])
        @test_throws ArgumentError checkres_figures(
            backend_result, Val(backend); metrics = [:bytes_or_memory])
        @test_throws ArgumentError checkres_figures(
            backend_result, Val(backend); metrics = Symbol[])
        @test_throws ArgumentError checkres_figures(
            backend_result, Val(backend); kinds = [:trajectory], metrics = [:times])
    end
    blue = checkres_to_scatterlines(result, Val(:chairmark);
        figure_kwargs = (size = (480, 320),),
        axis_kwargs = (backgroundcolor = :white, title = "Custom", subtitle = "Context"),
        plot_kwargs = (color = :blue, linewidth = 3))
    red = checkres_to_scatterlines(result, Val(:chairmark);
        figure_kwargs = Dict(:size => (480, 320)),
        axis_kwargs = (backgroundcolor = :white, title = "Custom", subtitle = "Context"),
        plot_kwargs = (color = :red, linewidth = 9))
    @test size(blue.scene) == (480, 320)
    blue_axis = only(filter(item -> item isa Axis, blue.content))
    @test blue_axis.title[] == "Custom · Chairmarks"
    @test blue_axis.subtitle[] == "Context · Tags: small, validated"
    @test size(red.scene) == (480, 320)
    blue_image, red_image = Makie.colorbuffer(blue), Makie.colorbuffer(red)
    @test count(blue_image .!= red_image) > 100
    axis = only(filter(item -> item isa Axis, red.content))
    curves = filter(item -> item isa Makie.ScatterLines, axis.scene.plots)
    @test all(curve -> curve.linewidth[] == 9, curves)
    @test_throws Exception checkres_to_scatterlines(result, Val(:benchmark);
        plot_kwargs = (this_attribute_does_not_exist = true,))
    @test_throws ArgumentError checkres_figures(result, Val(:benchmark); kinds = [:pie])
    @test_throws ArgumentError checkres_figures(
        result, Val(:benchmark); kinds = [:trajectory, :trajectory])
    @test_throws ArgumentError checkres_figures(result, Val(:benchmark)) # memory is absent
    selected = checkres_figures(
        result, Val(:chairmark); kinds = [:distribution], metrics = [:times])
    @test length(selected) == 1
    @test endswith(first(only(selected)), "distribution_times")
    allocation_table = PerfChecker.Table(filename = ["src/demo.jl", "src/demo.jl"],
        line = [1, 2], bytes = [80, 20])
    allocation = PerfChecker.CheckerResult([allocation_table], nothing, [:sites],
        [PerfChecker.PackageSpec(name = "Demo", version = v"1.0.0")])
    allocation_figures = checkres_figures(allocation, Val(:alloc);
        plot_kwargs = (color = :red,))
    @test length(allocation_figures) == 2
    for (_, figure) in allocation_figures
        allocation_axis = only(filter(item -> item isa Axis, figure.content))
        @test occursin("Julia allocation tracking", allocation_axis.title[])
        @test allocation_axis.subtitle[] == "Tags: sites"
        @test length(unique(vec(Makie.colorbuffer(figure)))) > 20
    end
    mktempdir() do directory
        svg = saveplot(joinpath(directory, "figure.svg"), red)
        @test startswith(read(svg, String), "<?xml")
        @test occursin("<svg", read(svg, String))
        png = saveplot(joinpath(directory, "figure.png"), red; px_per_unit = 1)
        @test read(png)[1:8] == UInt8[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]
        rendered = Makie.FileIO.load(png)
        @test size(rendered) == (320, 480)
        @test length(unique(vec(rendered))) > 20
        default_png = saveplot(joinpath(directory, "default.png"), red)
        @test size(Makie.FileIO.load(default_png)) == (640, 960)
        original = read(svg)
        @test_throws ArgumentError saveplot(svg, blue)
        @test read(svg) == original
        @test saveplot(svg, blue; overwrite = true) == svg
        @test read(svg) != original
        # The backend rejects this screen configuration during rendering, after temporary
        # output preparation. Preserve the existing destination and clean up.
        existing_files = readdir(directory)
        before_failure = read(svg)
        @test_throws MethodError saveplot(svg, red; overwrite = true,
            pt_per_unit = "invalid")
        @test readdir(directory) == existing_files
        @test read(svg) == before_failure
        named = ["../nested/name" => red, "CON" => blue]
        paths = saveplot(joinpath(directory, "collection"), named; format = :png)
        @test length(paths) == 2
        @test all(path -> dirname(path) == joinpath(directory, "collection"), paths)
        @test all(isfile, paths)
        @test basename(last(paths)) == "figure_CON.png"
        @test_throws ArgumentError saveplot(directory, ["a/b" => red, "a_b" => blue])
        @test_throws ArgumentError saveplot(directory, ["A" => red, "a" => blue])
        @test_throws ArgumentError saveplot(joinpath(directory, "bad.pdf"), red)
        @test_throws ArgumentError saveplot(directory, named; format = :pdf)
        # Preflight the whole collection: an existing later destination prevents
        # creating any earlier figure, and preserves the original bytes.
        blocked = joinpath(directory, "blocked")
        mkpath(blocked)
        existing = joinpath(blocked, "second.svg")
        write(existing, "preserve this file")
        @test_throws ArgumentError saveplot(blocked, ["first" => red, "second" => blue])
        @test readdir(blocked) == ["second.svg"]
        @test read(existing, String) == "preserve this file"
        if !Sys.iswindows()
            link = joinpath(directory, "link.svg")
            symlink(svg, link)
            @test_throws ArgumentError saveplot(link, red)
            @test islink(link)
            @test read(svg) == read(link)
            target_bytes = read(svg)
            saveplot(link, red; overwrite = true)
            @test !islink(link)
            @test read(svg) == target_bytes
            @test read(link) != target_bytes
        end
    end
end

@testitem "Empty, zero and nonfinite samples render safely" tags=[:plots] begin
    using PerfChecker, PerfCheckerMakie, CairoMakie
    using PerfCheckerMakie: Makie
    CairoMakie.activate!()
    packages = [PerfChecker.PackageSpec(name = "Demo", version = v"1.0.0"),
        PerfChecker.PackageSpec(name = "Demo", version = v"1.0.1")]
    for values in (Float64[], [NaN, Inf, -Inf], [0.0, 0.0], [NaN, 1.0, Inf, 2.0])
        table = PerfChecker.Table(
            times = values, gctimes = values, bytes = values, allocs = values)
        result = PerfChecker.CheckerResult([table, table], nothing, [:edge], packages)
        for backend in (:benchmark, :chairmark)
            for render in (checkres_to_scatterlines, checkres_to_boxplots)
                figure = render(result, Val(backend); figure_kwargs = (size = (480, 360),))
                @test figure isa Figure
                @test length(unique(vec(Makie.colorbuffer(figure)))) > 10
                axis = only(filter(item -> item isa Axis, figure.content))
                @test axis.xticklabelrotation[] ≈ pi / 2
                if !isempty(values) && all(iszero, values) &&
                   render === checkres_to_scatterlines
                    curves = filter(item -> item isa Makie.ScatterLines, axis.scene.plots)
                    @test length(curves) == 4
                    @test all(curve -> all(point -> point[2] == 1, curve[1][]), curves)
                end
            end
        end
    end
    empty = PerfChecker.Table(
        times = Float64[], gctimes = Float64[], bytes = Float64[], allocs = Float64[])
    finite = PerfChecker.Table(
        times = [1.0], gctimes = [0.0], bytes = [0.0], allocs = [0.0])
    result = PerfChecker.CheckerResult([empty, finite], nothing, nothing, packages)
    gap_figure = checkres_to_scatterlines(result, Val(:chairmark))
    axis = only(filter(item -> item isa Axis, gap_figure.content))
    curves = filter(item -> item isa Makie.ScatterLines, axis.scene.plots)
    @test length(curves) == 4
    @test all(curve -> isnan(first(curve[1][])[2]) && last(curve[1][])[2] == 1, curves)
    @test length(unique(vec(Makie.colorbuffer(gap_figure)))) > 10
    for bytes in (Float64[], [0.0, 0.0], [NaN, Inf])
        table = PerfChecker.Table(filename = fill("src/demo.jl", length(bytes)),
            line = collect(eachindex(bytes)), bytes = bytes)
        figure = table_to_pie(table, Val(:alloc); tags = [:empty])
        @test figure isa Figure
        @test length(unique(vec(Makie.colorbuffer(figure)))) > 10
    end
    for kind in (:version_series, :distribution)
        records = [Dict{String, Any}("version" => "1.0.0", "value" => value,
                       "target_kind" => "release") for value in [NaN, Inf, 2.0]]
        plot = PerfChecker.PerformancePlot("finite", kind, "Example", "samples",
            Dict{String, Any}(), records, Dict{String, Any}(
                "metric" => "julia.wall.time", "unit" => "s"))
        figure = performance_figure(plot; tool = "BenchmarkTools", tags = [:raw],
            figure_kwargs = (size = (480, 360),), plot_kwargs = (color = :red,))
        @test figure isa Figure
        @test length(unique(vec(Makie.colorbuffer(figure)))) > 10
        @test length(plot.data) == 3 # The input evidence remains untouched.
    end
end
