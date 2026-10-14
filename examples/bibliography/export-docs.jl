using PerfChecker, PerfCheckerMakie, WGLMakie, JSON, TOML, SHA

length(ARGS) == 2 ||
    error("Expected a bundle directory and a documentation output directory")
bundle_path, output = abspath.(ARGS)
bundle = read_run_bundle(bundle_path)
verify_run_bundle(bundle_path; require_integrity = true)
bundle.manifest["suite"] == "bibliography" || error("Expected the Bibliography suite")
bundle.manifest["state"] == "complete" || error("Expected a completed run")
mkpath(output)

entry = only(filter(plot_catalog(bundle)) do entry
    get(entry, "package", "") == "Bibliography" &&
        get(entry, "feature", "") == "export_bibtex" &&
        get(entry, "metric", "") == "julia.wall.time" &&
        entry["kind"] == "distribution"
end)
model = performance_plot(bundle, entry["id"])

# Publish an explicit projection; full local manifests contain workstation paths.
runtime = bundle.manifest["runtime"]
record = Dict(
    "description" => "Bibliography tutorial: measured timing samples, not a regression verdict",
    "run_id" => bundle.manifest["run_id"],
    "started_at" => bundle.manifest["started_at"],
    "finished_at" => bundle.manifest["finished_at"],
    "runtime" => Dict(key => runtime[key] for key in ("language", "version", "threads")),
    "sources" => TOML.parsefile(joinpath(@__DIR__, "sources.toml")),
    "input_manifest_sha256" => bytes2hex(sha256(read(joinpath(
        bundle_path, "manifest.json")))),
    "publication_scope" => "Numeric series and plot data only; local paths, host identifiers and logs omitted",
    "correctness" => "not_checked", "performance" => "not_compared",
    "series" => suite_version_series(bundle),
    "plot" => performance_plot_dict(model))
open(joinpath(output, "timing-evidence.json"), "w") do io
    JSON.print(io, record, 2)
end
normalized_entry = only(filter(plot_catalog(bundle)) do item
    get(item, "package", "") == "Bibliography" &&
        get(item, "feature", "") == "export_bibtex" &&
        item["kind"] == "normalized_metrics"
end)
normalized_model = performance_plot(bundle, normalized_entry["id"])
write(joinpath(output, "export-normalized.html"), performance_plot_html(normalized_model))
normalized_record = merge(filter(pair -> first(pair) != "series", record),
    Dict("plot" => performance_plot_dict(normalized_model),
        "description" => "Four recorded BenchmarkTools minima overlaid; one source revision, not a version comparison",
        "source_projection" => "timing-evidence.json",
        "source_projection_sha256" => bytes2hex(sha256(read(joinpath(
            output, "timing-evidence.json"))))))
open(io -> JSON.print(io, normalized_record, 2),
    joinpath(output, "export-normalized.json"), "w")
println("Exported measured Bibliography plot and evidence to ", output)
