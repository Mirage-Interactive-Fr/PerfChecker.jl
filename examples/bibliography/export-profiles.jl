using PerfChecker, PerfCheckerMakie, WGLMakie, JSON, SHA

length(ARGS) == 4 ||
    error("Expected CPU, wall-time and allocation report directories, then an output directory")
output = abspath(ARGS[4])
mkpath(output)
for (directory, kind, name) in zip(ARGS[1:3],
    ("cpu_flamegraph", "wall_flamegraph", "allocation_flamegraph"),
    ("cpu", "wall", "allocations"))
    bundle_path = only(filter(isdir, readdir(joinpath(directory, "bundles"); join = true)))
    verify_run_bundle(bundle_path; require_integrity = true)
    bundle = read_run_bundle(bundle_path)
    bundle.manifest["suite"] == "bibliography" || error("Expected Bibliography")
    bundle.manifest["state"] == "complete" || error("Expected a completed run")
    entry = only(filter(plot_catalog(bundle)) do item
        get(item, "package", "") == "Bibliography" &&
            startswith(get(item, "feature", ""), "export_bibtex") && item["kind"] == kind
    end)
    model = performance_plot(bundle, entry["id"]; top = 40)
    isempty(model.data) && error("No attributed stacks for $name")
    projection = performance_plot_dict(model)
    # Stack labels use package-relative source locations. Refuse an export if
    # a collector unexpectedly passes an absolute workstation path through.
    serialized = JSON.json(projection)
    occursin(r"[A-Za-z]:[\\/]", serialized) && error("Absolute Windows path in plot")
    occursin(r"/(?:home|Users|mnt|tmp)/", serialized) &&
        error("Absolute local path in plot")
    write(joinpath(output, "$name.html"), performance_plot_html(model))
    runtime = bundle.manifest["runtime"]
    record = Dict(
        "description" => "Recorded Bibliography export profile; diagnostic evidence, not a timing or regression verdict",
        "run_id" => bundle.manifest["run_id"],
        "started_at" => bundle.manifest["started_at"],
        "runtime" => Dict(key => runtime[key] for key in ("language", "version", "threads")),
        "os" => get(bundle.manifest["environment"], "os", "unknown"),
        "sources" => [Dict(
                          "source_name" => source["path"] isa AbstractString ?
                                           basename(replace(source["path"], '\\' => '/')) :
                                           nothing,
                          "revision" => source["revision"],
                          "target_label" => source["target_label"],
                          "dirty" => source["dirty"])
                      for source in bundle.manifest["source_provenance"]],
        "input_manifest_sha256" => bytes2hex(sha256(read(joinpath(
            bundle_path, "manifest.json")))),
        "publication_scope" => "Plot frames and package-relative source labels; raw observations and local paths omitted",
        "top_stacks" => 40, "correctness" => "not_checked", "performance" => "not_compared",
        "plot" => projection)
    open(joinpath(output, "$name.json"), "w") do io
        JSON.print(io, record, 2)
    end
    println("Exported $name: $(length(model.data)) frames, weight $(model.options["total"])")
end
