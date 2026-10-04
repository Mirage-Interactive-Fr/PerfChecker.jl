using PerfChecker, PerfCheckerMakie, WGLMakie, JSON, TOML, SHA

length(ARGS) == 2 || error("Expected a history report directory and an output directory")
reports, output = abspath.(ARGS)
bundle_path = only(filter(isdir, readdir(joinpath(reports, "bundles"); join = true)))
verify_run_bundle(bundle_path; require_integrity = true)
bundle = read_run_bundle(bundle_path)
bundle.manifest["suite"] == "bibliography" || error("Expected Bibliography evidence")
catalog = plot_catalog(bundle)
sources = TOML.parsefile(joinpath(reports, "sources.toml"))
versions = [target["version"] for target in sources["targets"]]
length(versions) >= 5 || error("The history gallery needs several measured versions")
mkpath(output)
views = Dict{String, Any}[]
for (slug, feature, metric, kind, label) in (
    ("normalized", "export_bibtex", "benchmark metrics",
        "normalized_metrics", "Export · four metrics / minimum"),
    ("export-time", "export_bibtex", "julia.wall.time", "version_series", "Export · time"),
    ("export-memory", "export_bibtex", "julia.alloc.bytes",
        "version_series", "Export · allocated bytes"),
    ("import-time", "import_bibtex", "julia.wall.time", "version_series", "Import · time"),
    ("export-samples", "export_bibtex", "julia.wall.time",
        "distribution", "Export · sample distribution"),
    ("export-delta", "export_bibtex", "julia.wall.time",
        "version_delta", "Export · change from 0.1.0"))
    entry = only(filter(
        entry -> get(entry, "feature", "") == feature &&
                     get(entry, "metric", "") == metric && entry["kind"] == kind,
        catalog))
    model = performance_plot(bundle, entry["id"])
    kind == "version_delta" || length(unique(row["version"] for row in model.data)) >= 5 ||
        error("Insufficient multi-version observations for $slug")
    write(joinpath(output, slug * ".html"), performance_plot_html(model))
    evidence = Dict("plot" => performance_plot_dict(model), "sources" => sources,
        "run_id" => bundle.manifest["run_id"],
        "runtime" => Dict(key => bundle.manifest["runtime"][key]
        for key in ("language", "version", "threads")),
        "os" => get(bundle.manifest["environment"], "os", "unknown"),
        "input_manifest_sha256" => bytes2hex(sha256(read(joinpath(
            bundle_path, "manifest.json")))),
        "correctness" => "not_checked", "performance" => "not_compared")
    open(io -> JSON.print(io, evidence, 2), joinpath(output, slug * ".json"), "w")
    push!(views,
        Dict("id" => slug, "label" => label, "kind" => kind,
            "html" => slug * ".html", "evidence" => slug * ".json"))
end
result = PerfChecker._json_parsefile(joinpath(reports, "suite-result.json"))
availability = [Dict(key => run[key] for key in ("workload", "version", "status"))
                for run in result["runs"]]
record = Dict("views" => views, "versions" => versions, "sources" => sources,
    "os" => get(bundle.manifest["environment"], "os", "unknown"),
    "availability" => availability, "started_at" => bundle.manifest["started_at"],
    "finished_at" => bundle.manifest["finished_at"],
    "runtime" => Dict(key => bundle.manifest["runtime"][key]
    for key in ("language", "version", "threads")))
open(io -> JSON.print(io, record, 2), joinpath(output, "catalog.json"), "w")
println(
    "Exported ", length(views), " historical views across ", length(versions), " versions")
