# Generate the browser regression fixture through the production Core/WGL API.
using PerfChecker, PerfCheckerMakie, WGLMakie

observations = Dict{String, Any}[]
for (metric, unit, value) in (("julia.wall.time", "s", 1.0),
        ("julia.alloc.bytes", "By", 100.0)),
    (version, scale) in (
        ("1.0.0", 1), ("1.0.1", 2), ("dev@6d742e35a516c7324af4ad14f58ce1780aa28728", 3)),
    sample in (1, 2, 3)

    push!(observations,
        Dict{String, Any}("metric" => metric,
            "measurement_definition" => "$metric/chairmarks-v1", "value" => value * scale *
                                                                            sample,
            "comparison_key" => "parse/v1::$metric/chairmarks-v1", "unit" => unit,
            "attributes" => Dict("package" => "Demo", "feature" => "parse",
                "workload" => "parse", "version" => version, "target_kind" => "release")))
end
bundle = RunBundle(
    Dict{String, Any}("run_id" => "browser-render-fixture", "tags" => ["exact-source"]),
    Dict{String, Any}[], observations, Dict{String, Any}[], Dict{String, Any}[])
model = performance_plot(bundle)
model.kind === :normalized_metrics || error("Expected a normalized model")
write(only(ARGS), performance_plot_html(model))
