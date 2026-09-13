using PerfChecker, PerfCheckerMakie, CairoMakie, JSON, SHA
include(joinpath(@__DIR__, "replay.jl"))
length(ARGS) in (2, 3) || error("Pass a report directory, an export directory and optionally --primary")
reports, output = abspath.(ARGS[1:2])
bundle = example_bundle(reports)
result = JSON.parsefile(joinpath(reports, "suite-result.json"))
history = JSON.parsefile(joinpath(@__DIR__, "release-history.json"))
package_name = first(result["runs"])["package"]
release_dates = Dict(version => history["packages"][package_name][version]["date"]
    for version in unique(run["version"] for run in result["runs"]))
release_date_kinds = Dict(version => get(history["packages"][package_name][version], "date_kind", history["date_kind"])
    for version in keys(release_dates))
all(run["status"] == "pass" for run in result["runs"]) || error("Export only a successful campaign")
mkpath(output)
runtime = bundle.manifest["runtime"]
catalog = plot_catalog(bundle)
if length(ARGS) == 3
    ARGS[3] == "--primary" || error("The optional export mode is --primary")
    catalog = filter(entry -> entry["kind"] == "normalized_metrics", catalog)
end
views = Dict{String, Any}[]
skipped = Dict{String, Any}[]
for entry in catalog
    model = performance_plot(bundle, entry["id"])
    if isempty(model.data)
        push!(skipped, Dict("id" => entry["id"], "reason" => "No observations for this view"))
        continue
    end
    # Numeric projections contain no host identifiers or absolute worker paths.
    record = Dict("plot" => performance_plot_dict(model),
        "run_id" => bundle.manifest["run_id"], "release_dates" => release_dates,
        "date_kind" => history["date_kind"], "release_date_kinds" => release_date_kinds,
        "started_at" => bundle.manifest["started_at"],
        "runtime" => Dict(k => runtime[k] for k in ("language", "version", "threads")),
        "os" => get(bundle.manifest["environment"], "os", "unknown"),
        "correctness" => "passed", "performance" => "not_compared",
        "worker_environments" => [Dict(k => env[k] for k in ("manifest_sha256", "project_sha256"))
            for env in bundle.manifest["environment_provenance"]],
        "scope" => "One local machine; illustrative history, not a package regression verdict")
    name = entry["id"]
    open(io -> JSON.print(io, record, 2), joinpath(output, name * ".json"), "w")
    # Static figures use the same PerfChecker renderer as the other interfaces.
    figure = performance_figure(model)
    versions = get(model.options, "versions", String[])
    if model.kind == :normalized_metrics && length(versions) > 20
        indices = unique(vcat(collect(1:cld(length(versions), 14):length(versions)), [length(versions)]))
        for content in figure.content
            content isa Axis && (content.xticks = (indices, versions[indices]))
        end
    end
    save(joinpath(output, name * ".svg"), figure)
    terminal = sprint(show, MIME"text/plain"(), terminal_plot(model); context = :color => false)
    write(joinpath(output, name * ".txt"), replace(terminal, r"[ \t]+(?=\r?$)"m => ""))
    if entry["kind"] == "normalized_metrics" &&
       get(entry, "workload", "") in ("heap_2048", "heap_request") &&
       startswith(get(entry, "collector", ""), "benchmarktools-v1")
        cp(joinpath(output, name * ".json"), joinpath(output, "normalized.json"); force = true)
        cp(joinpath(output, name * ".svg"), joinpath(output, "normalized.svg"); force = true)
    end
    windows = Any[]
    if model.kind == :normalized_metrics && package_name == "Oxygen"
        for minor in unique([(VersionNumber(v).major, VersionNumber(v).minor) for v in versions])
            selected = filter(v -> (VersionNumber(v).major, VersionNumber(v).minor) == minor, versions)
            length(selected) > 1 || continue
            window_name = name * "-$(minor[1]).$(minor[2])"
            projection = PerfChecker.PerformancePlot(window_name, model.kind,
                model.title * " — $(minor[1]).$(minor[2]) patches", model.description,
                copy(model.encoding), filter(row -> row["version"] in selected, model.data),
                merge(copy(model.options), Dict("versions" => selected)))
            save(joinpath(output, window_name * ".svg"), performance_figure(projection))
            open(io -> JSON.print(io, merge(record, Dict("plot" => performance_plot_dict(projection),
                "reference_scope" => "Ratios retain the minimum across the complete campaign")), 2), joinpath(output, window_name * ".json"), "w")
            push!(windows, Dict("label" => "$(minor[1]).$(minor[2]) patches", "svg" => window_name * ".svg", "json" => window_name * ".json"))
        end
    end
    push!(views, merge(Dict(entry), Dict("json" => name * ".json", "svg" => name * ".svg", "terminal" => name * ".txt", "patch_windows" => windows)))
    if length(views) % 10 == 0
        println("Rendered ", length(views), "/", length(catalog), " catalogue views")
        flush(stdout)
    end
end
record = Dict("views" => views, "skipped" => skipped, "release_dates" => release_dates, "release_date_kinds" => release_date_kinds,
    "resolved_environments" => [Dict("version" => run["version"],
        "manifest_sha256" => run["qualification"]["environment_provenance"]["manifest_sha256"],
        "packages" => get(run["qualification"]["environment_provenance"], "resolved_packages", Any[]))
        for run in result["runs"] if run["feature"] == first(result["runs"])["feature"]],
    "versions" => sort!(unique(run["version"] for run in result["runs"]); by = VersionNumber),
    "runs" => [Dict(k => run[k] for k in ("package", "feature", "version", "status")) for run in result["runs"]],
    "runtime" => Dict(k => runtime[k] for k in ("language", "version", "threads")),
    "correctness" => "passed", "performance" => "not_compared")
open(io -> JSON.print(io, record, 2), joinpath(output, "catalog.json"), "w")
println("Exported ", length(views), " plots from ", length(result["runs"]), " successful runs")
