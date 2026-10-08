@testitem "WGL exports retain real Core collector and tags" tags=[:plots, :wgl] begin
    using PerfChecker, PerfCheckerMakie, WGLMakie
    observations = Dict{String, Any}[]
    for (metric, unit, value) in (
            ("julia.wall.time", "s", 1.0), ("julia.alloc.bytes", "By", 10.0)),
        (version, scale) in (("1.0.0", 1), ("1.0.1", 2))

        push!(observations,
            Dict{String, Any}("metric" => metric,
                "measurement_definition" => "$metric/chairmarks-v1", "value" => value *
                                                                                scale,
                "comparison_key" => "parse/v1::$metric/chairmarks-v1", "unit" => unit,
                "attributes" => Dict(
                    "package" => "Demo", "feature" => "parse", "workload" => "parse",
                    "version" => version, "target_kind" => "release")))
    end
    bundle = RunBundle(
        Dict{String, Any}("run_id" => "wgl-identity", "tags" => ["exact-source"]),
        Dict{String, Any}[], observations, Dict{String, Any}[], Dict{String, Any}[])
    normalized = performance_plot(bundle)
    html = performance_plot_html(normalized)
    @test normalized.kind === :normalized_metrics
    @test occursin("\"collector_label\":\"Chairmarks\"", html)
    @test occursin("exact-source", html)
    @test occursin("rotate(90", html)
    catalog = plot_catalog(bundle)
    distribution = only(filter(
        entry -> entry["kind"] == "distribution" && entry["metric"] == "julia.wall.time",
        catalog))
    model = performance_plot(bundle, distribution["id"])
    @test model.options["measurement_definitions"] == ["julia.wall.time/chairmarks-v1"]
    html = performance_plot_html(model)
    @test occursin("Chairmarks", html)
    @test occursin("exact-source", html)
    @test occursin("offline-figure", html)
end
