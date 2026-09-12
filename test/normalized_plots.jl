@testitem "Normalized benchmark overlays" tags=[:unit, :plots] begin
    using PerfChecker
    function fixture(collector; zero_latest = false, missing_latest = false)
        observations = Dict{String, Any}[]
        metrics = ("julia.wall.time",
            collector == "chairmarks-v1" ? "julia.gc.fraction" : "julia.gc.time",
            "julia.alloc.bytes", "julia.alloc.count")
        for (m, metric) in pairs(metrics),
            (version, scale) in (("0.2.10", 1), ("0.2.9", 2), ("0.1.0", 3))

            missing_latest && m == 4 && version == "0.2.10" && continue
            value = m == 2 ? 0.0 :
                    zero_latest && m == 3 && scale == 1 ? 0.0 : m * scale * 10.0
            push!(observations,
                Dict{String, Any}(
                    "metric" => metric, "measurement_definition" => "$metric/$collector",
                    "unit" => "1", "comparison_key" => "parse/v1::$metric/$collector", "value" => value,
                    "attributes" => Dict(
                        "package" => "Demo", "feature" => "parse", "workload" => "parse",
                        "version" => version, "target_kind" => "release")))
        end
        RunBundle(
            Dict{String, Any}("run_id" => "normalized"), Dict{String, Any}[], observations,
            Dict{String, Any}[], Dict{String, Any}[])
    end
    for collector in ("benchmarktools-v1", "chairmarks-v1")
        bundle = fixture(collector)
        plot = performance_plot(bundle)
        @test plot.kind == :normalized_metrics
        @test plot.options["reference_version"] == "minimum"
        @test performance_plot(bundle; reference_version = :latest).options["reference_version"] ==
              "0.2.10"
        @test plot.options["versions"] == ["0.1.0", "0.2.9", "0.2.10"]
        @test length(plot.data) == 12
        @test all(r -> r["ratio"] == 1, filter(r -> r["version"] == "0.2.10", plot.data))
        @test all(r -> r["ratio"] == 2,
            filter(r -> r["version"] == "0.2.9" && r["value"] != 0, plot.data))
        @test count(r -> r["normalization_status"] == "both_zero", plot.data) == 3
        alternate = performance_plot(bundle; reference_version = "0.1.0")
        @test all(r -> r["ratio"] ≈ 1 / 3,
            filter(r -> r["version"] == "0.2.10" && r["value"] != 0, alternate.data))
        @test_throws ArgumentError performance_plot(bundle; reference_version = "missing")
        zero = performance_plot(fixture(collector; zero_latest = true))
        @test count(
            r -> r["normalization_status"] == "zero_reference" && isnothing(r["ratio"]),
            zero.data) == 2
        missing = performance_plot(
            fixture(collector; missing_latest = true); reference_version = :latest)
        @test count(
            r -> r["normalization_status"] == "missing_reference" && isnothing(r["ratio"]),
            missing.data) == 2
    end
    a, b = fixture("benchmarktools-v1"), fixture("chairmarks-v1")
    combined = RunBundle(a.manifest, a.measurement_definitions,
        vcat(a.observations, b.observations), a.diagnostics, a.artifacts)
    @test count(e -> e["kind"] == "normalized_metrics", plot_catalog(combined)) == 2
    # Different metrics can have their optimum at different versions.
    optimum = fixture("benchmarktools-v1")
    for row in optimum.observations
        row["metric"] == "julia.alloc.count" && row["attributes"]["version"] == "0.2.9" &&
            (row["value"] = 1.0)
    end
    overlay = performance_plot(optimum)
    @test only(filter(r -> r["metric"] == "julia.alloc.count" && r["version"] == "0.2.9",
        overlay.data))["ratio"] == 1.0
    @test only(filter(r -> r["metric"] == "julia.alloc.count" && r["version"] == "0.2.10",
        overlay.data))["ratio"] == 40.0
end
