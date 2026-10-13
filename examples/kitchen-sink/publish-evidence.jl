using JSON, SHA
isempty(ARGS) || ARGS == ["--interactive"] || ARGS == ["--interactive-normalized"] ||
    ARGS == ["--interactive-documentation"] ||
    error("Usage: julia --project=<prepared-environment> publish-evidence.jl [--interactive | --interactive-normalized | --interactive-documentation]")
interactive = !isempty(ARGS)
normalized_only = ARGS == ["--interactive-normalized"]
documentation_only = ARGS == ["--interactive-documentation"]
root = normpath(joinpath(@__DIR__, "../../website/src/public/examples/real-packages"))
if documentation_only
    # Replay every view reachable through the timing atlases and profile tabs.
    # Captured frontend provenance stays intact; replay provenance is separate.
    using PerfChecker, PerfCheckerMakie, WGLMakie
    include(joinpath(@__DIR__, "replay.jl"))
    source_root = normpath(joinpath(@__DIR__, "../.."))
    realpath(pkgdir(PerfChecker)) == realpath(source_root) &&
        realpath(pkgdir(PerfCheckerMakie)) ==
        realpath(joinpath(source_root, "packages", "PerfCheckerMakie")) ||
        error("Documentation replay must load this checkout's renderer")
    source_files = ["examples/kitchen-sink/replay.jl",
        "examples/kitchen-sink/publish-evidence.jl",
        "packages/PerfCheckerMakie/Project.toml",
        "packages/PerfCheckerMakie/src/performance.jl",
        "packages/PerfCheckerMakie/src/assets/normalized.html",
        "packages/PerfCheckerMakie/ext/WGLMakieExt.jl"]
    source_hashes = Dict(file => bytes2hex(sha256(read(joinpath(source_root, file))))
    for file in source_files)
    assets = normpath(joinpath(root, "../plot-assets"))
    for package in ("datastructures", "containers", "oxygen", "oxygen-features",
        "datastructures-profiles", "oxygen-profiles")
        directory = joinpath(root, package)
        catalog_path = joinpath(directory, "catalog.json")
        catalog = JSON.parsefile(catalog_path)
        timing = !endswith(package, "-profiles")
        selected = [entry
                    for view in catalog["views"]
                    if !timing || view["kind"] == "normalized_metrics"
                    for entry in [view; get(view, "patch_windows", Any[])]]
        for entry in selected
            source = joinpath(directory, entry["json"])
            input_hash = bytes2hex(sha256(read(source)))
            model = saved_plot(source)
            timing && model.kind !== :normalized_metrics &&
                error("A timing atlas must replay only normalized metrics")
            before = deepcopy(performance_plot_dict(model))
            entry["html"] = splitext(entry["json"])[1] * ".html"
            destination = joinpath(directory, entry["html"])
            # Existing non-timing exports retain their original bytes.
            if timing || !isfile(destination) ||
               model.kind in (:allocation_lines, :allocation_pie)
                html = performance_plot_html(model; asset_directory = assets,
                    html_directory = directory)
                performance_plot_dict(model) == before || error("Replay changed the model")
                bytes2hex(sha256(read(source))) == input_hash ||
                    error("Replay changed the recorded source")
                write(destination, html)
            end
            entry["html_input_sha256"] = input_hash
            delete!(entry, "html_sha256")
        end
        catalog["documentation_interactive_export"] = Dict(
            "renderer" => "PerfChecker.performance_plot_html",
            "companion_version" => string(pkgversion(PerfCheckerMakie)),
            "selection" => timing ? "all_normalized_views_and_patch_windows" :
                           "all_profile_views",
            "selected_views" => length(selected),
            "source_revision" => strip(read(`git -C $source_root rev-parse HEAD`, String)),
            "working_tree_source_sha256" => source_hashes)
        open(io -> JSON.print(io, catalog, 2), catalog_path, "w")
        println("Replayed ", length(selected), " documentation views for ", package)
        flush(stdout)
    end
elseif normalized_only
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
        entries = [entry
                   for view in catalog["views"]
                   if view["kind"] == "normalized_metrics"
                   for entry in [view; get(view, "patch_windows", Any[])]
                   if haskey(entry, "html")]
        isempty(entries) && error("No published normalized exports in $directory")
        for entry in entries
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
    end
elseif interactive
    # Optional rendering belongs to the prepared plots controller, not core setup.
    using PerfChecker, PerfCheckerMakie, WGLMakie
    include(joinpath(@__DIR__, "replay.jl"))
    assets = normpath(joinpath(root, "../plot-assets"))
    # Every saved view, including patch windows and profile totals, uses the
    # public renderer. Shared assets avoid embedding the WGL runtime per view.
    prepared = []
    for package in ("datastructures", "containers", "oxygen", "oxygen-features",
        "datastructures-profiles", "oxygen-profiles")
        directory = joinpath(root, package)
        catalog_path = joinpath(directory, "catalog.json")
        catalog = JSON.parsefile(catalog_path)
        selected = Any[]
        for view in catalog["views"]
            for entry in [view; get(view, "patch_windows", Any[])]
                # The catalogue is itself used for legacy unit provenance.
                # Keep HTML hashes outside it to avoid circular fingerprints.
                delete!(entry, "html_sha256")
                entry["html"] = splitext(entry["json"])[1] * ".html"
                entry["html_input_sha256"] = bytes2hex(sha256(read(joinpath(directory,
                    entry["json"]))))
                push!(selected, entry)
            end
        end
        catalog["interactive_export"] = Dict(
            "renderer" => "PerfChecker.performance_plot_html",
            "companion_version" => string(pkgversion(PerfCheckerMakie)),
            "input_kind" => "published_serialized_plot",
            "selection" => "all_saved_views",
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
    include(joinpath(@__DIR__, "observation-export.jl"))
    export_documentation_observations(root)
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
