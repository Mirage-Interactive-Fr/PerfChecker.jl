@testitem "Core plot models retain collector identity in Makie" tags=[:plots] begin
    using PerfChecker, PerfCheckerMakie, CairoMakie
    using PerfCheckerMakie: Makie
    CairoMakie.activate!()
    observations = Dict{String, Any}[]
    for collector in ("benchmarktools-v1", "chairmarks-v1"),
        (metric, unit, value) in (("julia.wall.time", "s", 1.0),
            ("julia.alloc.bytes", "By", 100.0)),
        (version, scale) in (("1.0.0", 1), ("1.0.1", 2))

        for sample in (1, 2)
            push!(observations,
                Dict{String, Any}(
                    "case_id" => "Demo/parse/$collector", "target_id" => version,
                    "metric" => metric, "measurement_definition" => "$metric/$collector",
                    "unit" => unit, "comparison_key" => "parse/v1::$metric/$collector",
                    "value" => value * scale * sample,
                    "attributes" => Dict(
                        "package" => "Demo", "feature" => "parse", "workload" => "parse",
                        "version" => version, "target_kind" => "release")))
        end
    end
    push!(observations,
        Dict{String, Any}(
            "case_id" => "Demo/profile", "target_id" => "1.0.1",
            "metric" => "julia.cpu.samples", "measurement_definition" => "julia.cpu.samples/profile-v1",
            "unit" => "samples", "comparison_key" => "profile/v1::julia.cpu.samples/profile-v1",
            "value" => 10.0, "attributes" => Dict{String, Any}(
                "package" => "Demo", "feature" => "profile", "version" => "1.0.1",
                "target_kind" => "release", "stack" => ["root", "dynamic"],
                "runtime_dispatch" => [false, true], "gc_event" => [false, false],
                "inference_status" => ["concrete", "union"],
                "inferred_return_type" => ["Nothing", "Union{String, Nothing}"])))
    for (version, scale) in (("1.0.0", 1), ("1.0.1", 2)),
        (line, bytes) in ((1, 80.0), (2, 20.0))

        push!(observations,
            Dict{String, Any}(
                "case_id" => "Demo/alloc", "target_id" => version,
                "metric" => "julia.alloc.bytes", "measurement_definition" => "julia.alloc.bytes/line-tracking-v1",
                "unit" => "By", "comparison_key" => "alloc/v1::julia.alloc.bytes/line-tracking-v1",
                "value" => bytes * scale,
                "attributes" => Dict{String, Any}(
                    "package" => "Demo", "feature" => "alloc", "workload" => "alloc",
                    "version" => version, "target_kind" => "release",
                    "source_file" => "src/demo.jl", "source_line" => line,
                    "stack" => ["root", "allocate"])))
    end
    bundle = RunBundle(Dict{String, Any}("run_id" => "identity", "tags" => ["reviewed"]),
        Dict{String, Any}[], observations, Dict{String, Any}[], Dict{String, Any}[])
    evidence = deepcopy(observations)
    before = suite_version_series(bundle)
    catalog = plot_catalog(bundle)
    observed_kinds = Set{Symbol}()
    for entry in catalog
        model = performance_plot(bundle, entry["id"])
        push!(observed_kinds, model.kind)
        @test model.id == entry["id"]
        @test model.options["tags"] == ["reviewed"]
        definitions = get(
            model.options, "measurement_definitions", [get(model.options, "collector", "")])
        expected = any(definition -> occursin("chairmarks", definition), definitions) ?
                   "Chairmarks" :
                   any(definition -> occursin("benchmarktools", definition), definitions) ?
                   "BenchmarkTools" :
                   any(definition -> occursin("profile-v1", definition), definitions) ?
                   "Julia CPU profiler" :
                   "Julia allocation tracking"
        figure = performance_figure(model; figure_kwargs = (size = (640, 480),))
        axis = only(filter(item -> item isa Axis, figure.content))
        @test startswith(axis.title[], model.title)
        @test axis.subtitle[] == "$expected · Tags: reviewed"
        @test length(unique(vec(Makie.colorbuffer(figure)))) > 20
        if model.kind in (
            :version_series, :distribution, :version_delta, :normalized_metrics,
            :allocation_files, :allocation_heatmap)
            @test axis.xticklabelrotation[] ≈ pi / 2
        end
        if model.kind === :allocation_files
            red = performance_figure(model; plot_kwargs = (color = :red,))
            red_axis = only(filter(item -> item isa Axis, red.content))
            bars = only(filter(item -> item isa Makie.BarPlot, red_axis.scene.plots))
            @test Makie.to_color(bars.color[]) == Makie.to_color(:red)
            legend = only(filter(item -> item isa Legend, red.content))
            @test all(
                entry -> Makie.to_color(only(entry.elements).attributes[:polycolor][]) ==
                         Makie.to_color(:red),
                only(legend.entrygroups[])[2])
            rendered = Makie.colorbuffer(red)
            @test count(color -> begin
                    rgb = Makie.RGBf(color)
                    rgb.r > 0.9 && rgb.g < 0.1 && rgb.b < 0.1
                end, rendered) > 100
        elseif model.kind === :cpu_flamegraph
            custom = performance_figure(model; plot_kwargs = (color = :red,))
            @test any(
                item -> item isa Label &&
                    occursin("Colors do not encode diagnostics", item.text[]),
                custom.content)
            @test !any(item -> item isa Legend, custom.content)
            custom_axis = only(filter(item -> item isa Axis, custom.content))
            bars = only(filter(item -> item isa Makie.BarPlot, custom_axis.scene.plots))
            frame = findfirst(
                item -> get(item, "runtime_dispatch_value", 0) > 0, model.data)
            @test !isnothing(frame)
            @test occursin("Runtime dispatch", bars.inspector_label[](bars, frame, nothing))
            @test length(unique(vec(Makie.colorbuffer(custom)))) > 20
        end
    end
    @test all(kind -> kind in observed_kinds,
        (:version_series, :distribution, :version_delta, :normalized_metrics,
            :allocation_pie, :allocation_files, :allocation_lines,
            :allocation_heatmap, :allocation_flamegraph))
    @test observations == evidence
    @test suite_version_series(bundle) == before
    @test plot_catalog(bundle) == catalog
    times = filter(series -> series["metric"] == "julia.wall.time", before)
    @test all(
        series -> [point["median"] for point in series["points"]] == [1.5, 3.0], times)
end
