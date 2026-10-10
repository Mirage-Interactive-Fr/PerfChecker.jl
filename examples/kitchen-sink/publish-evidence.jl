using JSON, SHA
isempty(ARGS) || ARGS == ["--interactive"] || ARGS == ["--interactive-normalized"] ||
    error("Usage: julia --project=<prepared-environment> publish-evidence.jl [--interactive | --interactive-normalized]")
interactive = !isempty(ARGS)
normalized_only = ARGS == ["--interactive-normalized"]
root = normpath(joinpath(@__DIR__, "../../website/src/public/examples/real-packages"))
if normalized_only
    using PerfChecker, PerfCheckerMakie, WGLMakie
    include(joinpath(@__DIR__, "replay.jl"))
    source_root = normpath(joinpath(@__DIR__, "../.."))
    realpath(pkgdir(PerfChecker)) == realpath(source_root) &&
        realpath(pkgdir(PerfCheckerMakie)) ==
        realpath(joinpath(source_root, "packages", "PerfCheckerMakie")) ||
        error("Normalized publication must load the renderer from this checkout")
    run(`git -C $source_root diff --exit-code HEAD -- Project.toml src packages examples/kitchen-sink/publish-evidence.jl examples/kitchen-sink/replay.jl`)
    revision = strip(read(`git -C $source_root rev-parse HEAD`, String))
    tree = strip(read(Cmd(["git", "-C", source_root, "rev-parse", "HEAD^{tree}"]), String))
    println("Normalized renderer source ", revision, " / tree ", tree)
    directories = [joinpath(root, package)
                   for package in (
        "datastructures", "containers", "oxygen", "oxygen-features")]
    push!(directories, normpath(joinpath(root, "../bibliography/history")))
    for directory in directories
        catalog_path = joinpath(directory, "catalog.json")
        catalog_hash = bytes2hex(sha256(read(catalog_path)))
        catalog = JSON.parsefile(catalog_path)
        entry = only(filter(
            view -> view["kind"] == "normalized_metrics" &&
                haskey(view, "html"),
            catalog["views"]))
        source = joinpath(directory, get(entry, "json", get(entry, "evidence", "")))
        input_hash = bytes2hex(sha256(read(source)))
        get(entry, "html_input_sha256", input_hash) == input_hash ||
            error("Normalized input differs from its published fingerprint")
        model = saved_plot(source)
        model.kind === :normalized_metrics || error("Expected a normalized model")
        before = deepcopy(performance_plot_dict(model))
        html = performance_plot_html(model)
        performance_plot_dict(model) == before || error("Rendering changed the model")
        bytes2hex(sha256(read(source))) == input_hash ||
            error("Rendering changed the serialized plot")
        bytes2hex(sha256(read(catalog_path))) == catalog_hash ||
            error("Rendering changed the catalogue")
        destination = joinpath(directory, entry["html"])
        write(destination, html)
        println(relpath(destination, source_root), " input_sha256=", input_hash,
            " html_sha256=", bytes2hex(sha256(html)))
    end
elseif interactive
    # Optional rendering belongs to the prepared plots controller, not core setup.
    using PerfChecker, PerfCheckerMakie, WGLMakie
    include(joinpath(@__DIR__, "replay.jl"))
    assets = normpath(joinpath(root, "../plot-assets"))
    # Keep one coherent, visibly changing workload per comparison gallery.
    # The complete catalogue remains available as SVG, terminal plots and JSON.
    features = Dict("datastructures" => "heap_2048_benchmark",
        "containers" => "SortedSet_lookup_benchmark", "oxygen" => "heap_benchmark",
        "oxygen-features" => "html_benchmark")
    function guided_views(package, catalog)
        if haskey(features, package)
            return [only(filter(catalog["views"]) do view
                        view["kind"] == kind && view["feature"] == features[package] &&
                            (!(kind in ("distribution", "version_delta", "version_series")) ||
                             view["metric"] == "julia.wall.time")
                    end)
                    for kind in ("normalized_metrics", "distribution",
                "time_allocation_tradeoff", "version_delta", "version_series")]
        end
        allocation_feature = package == "datastructures-profiles" ?
                             "heap_32768_alloc" : "heap_profile_alloc"
        return [only(filter(catalog["views"]) do view
                    view["kind"] == kind &&
                        (!(kind in ("allocation_files", "allocation_lines",
                            "allocation_heatmap", "allocation_pie")) ||
                         view["feature"] == allocation_feature)
                end)
                for kind in ("allocation_files", "allocation_lines", "allocation_heatmap",
            "allocation_pie", "allocation_flamegraph", "cpu_flamegraph",
            "wall_flamegraph")]
    end
    prepared = []
    for package in ("datastructures", "containers", "oxygen", "oxygen-features",
        "datastructures-profiles", "oxygen-profiles")
        directory = joinpath(root, package)
        catalog_path = joinpath(directory, "catalog.json")
        catalog = JSON.parsefile(catalog_path)
        selected = guided_views(package, catalog)
        selected_ids = Set(view["id"] for view in selected)
        for view in catalog["views"]
            for entry in [view; get(view, "patch_windows", Any[])]
                keep = entry === view && view["id"] in selected_ids
                previous = get(entry, "html", nothing)
                for key in ("html", "html_input_sha256", "html_sha256")
                    delete!(entry, key)
                end
                if previous !== nothing && !keep
                    # Only remove the generator's normalized/flame exports. Preserve
                    # historical SVG/JSON and other pre-existing public HTML.
                    expected = splitext(entry["json"])[1] * ".html"
                    previous == expected &&
                        view["kind"] in ("normalized_metrics", "cpu_flamegraph",
                            "wall_flamegraph", "allocation_flamegraph") &&
                        rm(joinpath(directory, previous); force = true)
                end
                keep || continue
                entry["html"] = splitext(entry["json"])[1] * ".html"
                entry["html_input_sha256"] = bytes2hex(sha256(read(joinpath(directory,
                    entry["json"]))))
            end
        end
        catalog["interactive_export"] = Dict(
            "renderer" => "PerfChecker.performance_plot_html",
            "companion_version" => string(pkgversion(PerfCheckerMakie)),
            "input_kind" => "published_serialized_plot",
            "selection" => "guided_examples",
            "selected_views" => length(selected),
            "asset_layout" => "shared_relative",
            "recipe" => "examples/kitchen-sink/replay.jl:saved_plot",
            "recipe_sha256" => bytes2hex(sha256(read(joinpath(@__DIR__, "replay.jl")))))
        open(io -> JSON.print(io, catalog, 2), catalog_path, "w")
        push!(prepared, (; package, directory, catalog, selected))
    end
    # Write catalogues first: legacy tradeoff replay records the catalogue hash.
    # Adding HTML hashes afterwards would invalidate that recorded provenance.
    for item in prepared
        for entry in item.selected
            source = joinpath(item.directory, entry["json"])
            model = saved_plot(source)
            before = deepcopy(performance_plot_dict(model))
            if haskey(features, item.package)
                field = model.kind === :version_delta ? "candidate_version" : "version"
                length(unique(row[field] for row in model.data)) >= 2 ||
                    error("The guided comparison needs distinct recorded versions")
            end
            html = performance_plot_html(model; asset_directory = assets,
                html_directory = item.directory)
            performance_plot_dict(model) == before || error("Rendering changed the model")
            bytes2hex(sha256(read(source))) == entry["html_input_sha256"] ||
                error("Rendering changed the serialized plot")
            write(joinpath(item.directory, entry["html"]), html)
        end
        println("Rendered ", length(item.selected), " saved views for ", item.package)
        flush(stdout)
    end
    bibliography = normpath(joinpath(root, "../bibliography/history"))
    history = JSON.parsefile(joinpath(bibliography, "catalog.json"))
    length(history["views"]) == 6 || error("Expected the six measured Bibliography views")
    for entry in history["views"]
        source = joinpath(bibliography, entry["evidence"])
        input_hash = bytes2hex(sha256(read(source)))
        model = saved_plot(source)
        before = deepcopy(performance_plot_dict(model))
        html = performance_plot_html(model; asset_directory = assets,
            html_directory = bibliography)
        performance_plot_dict(model) == before || error("Rendering changed the model")
        bytes2hex(sha256(read(source))) == input_hash ||
            error("Rendering changed the Bibliography evidence")
        write(joinpath(bibliography, entry["html"]), html)
    end
    println("Rendered the six measured Bibliography views")
end
for package in ("datastructures", "oxygen")
    directory = joinpath(root, package)
    catalog = JSON.parsefile(joinpath(directory, "catalog.json"))
    entry = only(filter(catalog["views"]) do row
        row["kind"] == "normalized_metrics" &&
            get(row, "workload", "") in ("heap_2048", "heap_request") &&
            startswith(get(row, "collector", ""), "benchmarktools-v1")
    end)
    if interactive
        cp(joinpath(directory, entry["html"]),
            joinpath(directory, "normalized.html"); force = true)
    else
        for format in ("json", "svg")
            cp(joinpath(directory, entry[format]),
                joinpath(directory, "normalized." * format); force = true)
        end
    end
end
if !interactive
    cp(joinpath(@__DIR__, "notebook.jl"), joinpath(root, "notebook.jl"); force = true)
    for name in ("datastructures-notebook.jl", "oxygen-notebook.jl")
        cp(joinpath(@__DIR__, name), joinpath(root, name); force = true)
    end
end
println(normalized_only ? "Published the normalized views and HTML aliases" :
        interactive ? "Published the interactive views and HTML aliases" :
        "Published the overlay aliases and the three downloadable notebooks")
