@testitem "Fresh-state profile collectors retain graphical evidence" tags=[:unit, :plots] begin
    using PerfChecker
    for (definition, metric, unit, kind) in (
        ("julia.alloc.bytes/profile-allocs-v1",
            "julia.alloc.bytes", "By", "allocation_flamegraph"),
        ("julia.cpu.samples/profile-v1", "julia.cpu.samples", "1", "cpu_flamegraph"),
        ("julia.wall.samples/profile-walltime-v1",
            "julia.wall.samples", "1", "wall_flamegraph"))
        fresh = definition * "/fresh-state-evals1-v1"
        observation = Dict{String, Any}(
            "case_id" => "demo/Demo/export", "target_id" => "1.0.0",
            "comparison_key" => "export/v1::$fresh", "measurement_definition" => fresh,
            "metric" => metric, "unit" => unit, "value" => 12.0,
            "attributes" => Dict{String, Any}("package" => "Demo", "feature" => "export",
                "version" => "1.0.0", "target_kind" => "release",
                "source_file" => "src/export.jl", "source_line" => 4,
                "stack" => ["export (src/export.jl:1)", "write (src/export.jl:4)"]))
        bundle = RunBundle(
            Dict{String, Any}(
                "run_id" => "fresh-profile", "suite" => "demo", "state" => "complete"),
            [Dict{String, Any}("id" => fresh, "metric" => metric, "unit" => unit)],
            [observation], Dict{String, Any}[], Dict{String, Any}[])
        catalog = plot_catalog(bundle)
        entry = only(filter(item -> item["kind"] == kind, catalog))
        model = performance_plot(bundle, entry["id"])
        @test length(model.data) == 2
        @test model.options["total"] == 12.0
        @test all(item -> item["kind"] != "distribution", catalog)
        @test only(bundle.observations)["measurement_definition"] == fresh
        @test only(suite_version_series(bundle))["comparison_key"] == "export/v1::$fresh"
        if kind != "allocation_flamegraph"
            reused = deepcopy(observation)
            reused["measurement_definition"] = definition
            reused["comparison_key"] = "export/v1::$definition"
            reused["value"] = 99.0
            push!(bundle.observations, reused)
            entries = filter(item -> item["kind"] == kind, plot_catalog(bundle))
            @test length(unique(item["id"] for item in entries)) == 2
            @test Set(performance_plot(bundle, item["id"]).options["total"]
            for item in entries) == Set([12.0, 99.0])
        end
    end
end
