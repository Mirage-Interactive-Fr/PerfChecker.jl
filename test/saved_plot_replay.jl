@testitem "Saved tradeoff replay resolves units from unchanged published series" tags=[
    :unit, :plots] begin
    using PerfChecker, JSON, SHA
    include(joinpath(pkgdir(PerfChecker), "examples", "kitchen-sink", "replay.jl"))
    root = joinpath(
        pkgdir(PerfChecker), "website", "src", "public", "examples", "real-packages")
    examples = [("datastructures", "time-allocation-tradeoff-0f659878d93e0277.json"),
        ("oxygen-features", "time-allocation-tradeoff-d82dcc6c45ddfbd5.json")]
    for (owner, filename) in examples
        path = joinpath(root, owner, filename)
        before = read(path)
        original = JSON.parse(String(copy(before)))
        model = saved_plot(path)
        @test model.data == original["plot"]["data"]
        @test model.options["time_unit"] == "ns"
        @test model.options["allocation_unit"] == "By"
        @test model.options["unit_source"] == "published_series_replay"
        @test model.options["unit_resolution"] == "unique matching published series"
        provenance = model.options["unit_provenance"]
        @test provenance["saved_model_sha256"] == bytes2hex(sha256(before))
        @test provenance["catalog_sha256"] ==
              bytes2hex(sha256(read(joinpath(dirname(path), "catalog.json"))))
        @test length(provenance["sources"]) == 2
        for source in provenance["sources"]
            @test source["sha256"] ==
                  bytes2hex(sha256(read(joinpath(dirname(path), source["json"]))))
            @test source["series_id"] in (
                model.options["time_series_id"], model.options["allocation_series_id"])
            @test source["source_collector"] === nothing
            @test "collector" ∉ source["verified_shared_fields"]
        end
        @test read(path) == before
    end

    path = joinpath(root, first(examples)...)
    resolved = saved_plot(path)
    sources = Dict(source["metric"] => source["json"]
    for source in resolved.options["unit_provenance"]["sources"])
    function rewrite(change, path)
        content = JSON.parsefile(path)
        change(content)
        open(io -> JSON.print(io, content), path, "w")
    end
    rewrite(path::AbstractString, change::Function) = rewrite(change, path)
    function negative_case(change; reason = nothing)
        mktempdir() do directory
            for filename in [basename(path), "catalog.json", collect(values(sources))...]
                cp(joinpath(dirname(path), filename), joinpath(directory, filename))
            end
            change(directory)
            local_path = joinpath(directory, basename(path))
            before = read(local_path)
            model = saved_plot(local_path)
            @test !haskey(model.options, "time_unit")
            @test !haskey(model.options, "allocation_unit")
            @test PerfChecker._tradeoff_plot_units(model.options) ==
                  ("unit unspecified", "unit unspecified")
            reason === nothing || @test model.options["unit_resolution"] == reason
            @test read(local_path) == before
        end
    end
    negative_case(directory -> rm(joinpath(directory, "catalog.json")))
    negative_case() do directory
        rewrite(joinpath(directory, sources["julia.wall.time"]),
            record -> record["run_id"] = "another run")
    end
    negative_case() do directory
        rewrite(joinpath(directory, sources["julia.wall.time"]),
            record -> record["plot"]["data"][1]["value"] += 1)
    end
    negative_case(; reason = "incompatible published series units") do directory
        filename = sources["julia.alloc.bytes"]
        rewrite(joinpath(directory, filename),
            record -> record["plot"]["options"]["unit"] = "s")
        rewrite(joinpath(directory, "catalog.json")) do catalog
            only(filter(view -> view["json"] == filename, catalog["views"]))["unit"] = "s"
        end
    end
    negative_case() do directory
        filename = sources["julia.wall.time"]
        rewrite(joinpath(directory, filename),
            record -> record["plot"]["options"]["comparison_key"] = "another comparison")
        rewrite(joinpath(directory, "catalog.json")) do catalog
            only(filter(view -> view["json"] == filename, catalog["views"]))["comparison_key"] = "another comparison"
        end
    end
    negative_case(; reason = "incompatible published series identities") do directory
        for (metric, collector) in (("julia.wall.time", "benchmarktools-v1"),
            ("julia.alloc.bytes", "chairmarks-v1"))
            rewrite(joinpath(directory, sources[metric]),
                record -> record["plot"]["options"]["measurement_definition"] = "$metric/$collector")
        end
    end
    negative_case(; reason = "incompatible published series identities") do directory
        rewrite(joinpath(directory, sources["julia.alloc.bytes"])) do record
            for row in record["plot"]["data"]
                row["aggregation"] = "mean"
            end
        end
    end
    negative_case(; reason = "ambiguous published series") do directory
        filename = sources["julia.wall.time"]
        duplicate = "duplicate-time.json"
        cp(joinpath(directory, filename), joinpath(directory, duplicate))
        rewrite(
            joinpath(directory, duplicate), record -> record["plot"]["id"] *= "-duplicate")
        rewrite(joinpath(directory, "catalog.json")) do catalog
            view = deepcopy(only(filter(
                view -> view["json"] == filename, catalog["views"])))
            view["id"] *= "-duplicate"
            view["json"] = duplicate
            push!(catalog["views"], view)
        end
    end
end
