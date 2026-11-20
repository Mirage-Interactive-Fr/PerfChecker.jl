# Shared, reproducible frontend exports from the published observations. These
# functions are used by the capture exporters and by publish-evidence.jl.
using PerfChecker, PerfCheckerMakie, WGLMakie, CairoMakie, JSON, SHA, Statistics

# Project already-published numeric minima into the public normalized model.
# Keep one collector and one workload per view; never turn implementations into
# released package versions or infer an absent GC observation from other minima.
function export_normalized_projection(directory, name, observations;
        title, collector, scope, sources, metadata = Dict(),
        xlabel = "Package version", target_label = "version", json_name = name *
                                                                          ".plot.json",
        reference_target = nothing)
    metrics = unique(String(row["metric"]) for row in observations)
    expected_gc = "julia.gc.fraction" in metrics ? "julia.gc.fraction" : "julia.gc.time"
    Set(metrics) == Set(("julia.wall.time", expected_gc,
        "julia.alloc.bytes", "julia.alloc.count")) ||
        error("A normalized timing view requires four recorded metrics, including GC")
    versions = unique(String(row["version"]) for row in observations)
    reference = isnothing(reference_target) ? "minimum" : String(reference_target)
    isnothing(reference_target) || reference in versions ||
        error("Unknown recorded reference target")
    records = Dict{String, Any}[]
    for metric in ("julia.wall.time", expected_gc, "julia.alloc.bytes", "julia.alloc.count")
        rows = filter(row -> row["metric"] == metric, observations)
        length(rows) == length(versions) ||
            error("Missing or duplicate normalized observation")
        length(unique(row["version"] for row in rows)) == length(versions) ||
            error("Duplicate normalized target")
        unit = only(unique(row["unit"] for row in rows))
        all(
            row -> row["value"] isa Real && isfinite(row["value"]) &&
                       row["value"] >= 0, rows) ||
            error("Normalized minima must be recorded finite values")
        denominator = isnothing(reference_target) ? minimum(row["value"] for row in rows) :
                      only(filter(row -> row["version"] == reference, rows))["value"]
        for row in rows
            value = row["value"]
            ratio = iszero(denominator) ? (iszero(value) ? 1.0 : nothing) :
                    value / denominator
            status = iszero(denominator) ?
                     (iszero(value) ? "both_zero" : "zero_reference") : "ratio"
            push!(records,
                merge(deepcopy(row),
                    Dict("metric" => metric, "unit" => unit,
                        "target_kind" => get(row, "target_kind", "recorded"),
                        "reference_version" => reference, "reference_value" => denominator,
                        "statistic" => "minimum", "ratio" => ratio,
                        "normalization_status" => status)))
        end
    end
    hashes = Dict(basename(source) => bytes2hex(sha256(read(source))) for source in sources)
    options = Dict{String, Any}("collector" => collector, "versions" => versions,
        "reference_version" => reference, "statistic" => "minimum", "unit" => "ratio",
        "xlabel" => xlabel, "target_label" => target_label,
        "zero_reference_policy" => "equal zeros = 1 (unchanged); nonzero / zero = unavailable",
        "metadata" => merge(
            Dict("source_sha256" => hashes, "scope" => scope,
                "projection" => "Recorded metric minima; reference=$reference for each metric"),
            metadata))
    model = PerfChecker.PerformancePlot(name, :normalized_metrics, title,
        scope * "; minimum per recorded target / $reference reference for each metric. " *
        (length(versions) == 1 ?
         "Single recorded target; ratios do not establish an improvement." :
         "Targets retain their recorded identity."),
        Dict{String, Any}("x" => "version", "y" => "ratio", "color" => "metric"), records, options)
    before = deepcopy(performance_plot_dict(model))
    html = performance_plot_html(model)
    performance_plot_dict(model) == before ||
        error("Rendering changed normalized measurements")
    for source in sources
        bytes2hex(sha256(read(source))) == hashes[basename(source)] ||
            error("Rendering changed $source")
    end
    mkpath(directory)
    write(joinpath(directory, name * ".html"), html)
    open(io -> JSON.print(io, Dict("plot" => before), 2),
        joinpath(directory, json_name), "w")
    return model
end

function observation_panel(id, title, xlabel, xunit, ylabel, unit;
        categories = nothing, yscale = "linear")
    panel = Dict{String, Any}("id" => id, "title" => title, "xlabel" => xlabel,
        "xunit" => xunit, "ylabel" => ylabel, "unit" => unit,
        "xkind" => categories === nothing ? "numeric" : "categorical", "yscale" => yscale)
    categories === nothing || (panel["categories"] = categories)
    return panel
end

function export_observation_model(directory, name, rows, panels;
        title, collector, scope, sources, metadata = Dict(), static = true)
    hashes = Dict(basename(source) => bytes2hex(sha256(read(source))) for source in sources)
    model = observation_plot(name, rows; title, panels, collector, scope,
        metadata = merge(Dict("source_sha256" => hashes), metadata))
    before = deepcopy(performance_plot_dict(model))
    html = performance_plot_html(model)
    performance_plot_dict(model) == before || error("Rendering changed observations")
    for source in sources
        bytes2hex(sha256(read(source))) == hashes[basename(source)] ||
            error("Rendering changed $source")
    end
    write(joinpath(directory, name * ".html"), html)
    open(io -> JSON.print(io, Dict("plot" => before), 2),
        joinpath(directory, name * ".plot.json"), "w")
    if static
        CairoMakie.activate!()
        saveplot(
            joinpath(directory, name * ".svg"), performance_figure(model); overwrite = true)
    end
    return model
end

function export_saved_oxygen_diagnostics(directory; static = true)
    for tool in ("latency", "memory")
        sources = [joinpath(directory, "$tool-$version.json")
                   for version in ("1.10.2", "1.11.0")]
        reports = JSON.parsefile.(sources)
        rows = Dict{String, Any}[]
        provenance = Dict{String, Any}[]
        specs = tool == "latency" ?
                [("load", "load_seconds"), ("first operation", "first_case_seconds"),
            ("warm operation", "warm_case_seconds")] :
                [
            ("state_before_bytes", "State before"), ("state_after_bytes", "State after"),
            ("state_and_result_bytes", "State and result"),
            ("process_before", "Process memory before"), (
                "process_after", "Process memory after")]
        panels = tool == "latency" ?
                 [observation_panel(
            "time", "Source loading and operation latency", "Phase", "",
            "Elapsed time", "s"; categories = first.(specs), yscale = "log10")] :
                 [observation_panel(key, label, "Diagnostic operation", "", label, "By")
                  for (key, label) in specs]
        for report in reports
            record = only(report["records"])
            package = only(filter(package -> package["name"] == "Oxygen",
                record["environment_provenance"]["resolved_packages"]))
            version = package["version"]
            push!(provenance,
                Dict("version" => version, "performance" => record["performance"],
                    "runtime" => record["runtime"], "source_provenance" => report["source_provenance"],
                    "environment_provenance" => record["environment_provenance"],
                    "input_fingerprints" => record["input_fingerprints"]))
            if tool == "latency"
                for (phase, key) in specs
                    push!(rows,
                        Dict(
                            "panel" => "time", "series" => "Latency", "version" => version,
                            "x" => phase, "value" => record["measurements"][key],
                            "label" => key, "style" => "scatterline"))
                end
            else
                for (index, sample) in pairs(record["measurements"]["samples"]),
                    (key, label) in specs

                    value = get(sample, key, nothing)
                    if value isa AbstractDict
                        for (field, metric) in (("rss_bytes", "RSS"),
                            ("private_bytes", "Private bytes"), (
                                "peak_rss_bytes", "Peak RSS"))
                            haskey(value, field) || continue
                            push!(rows,
                                Dict("panel" => key, "series" => metric,
                                    "version" => version,
                                    "x" => index, "value" => value[field],
                                    "label" => "Recorded operation $index · $(get(value, "provider", "unspecified provider"))",
                                    "style" => "scatterline"))
                        end
                    else
                        push!(rows,
                            Dict("panel" => key, "series" => label, "version" => version,
                                "x" => index, "value" => value, "label" => "Recorded operation $index",
                                "style" => "scatterline"))
                    end
                end
            end
        end
        export_observation_model(directory, tool, rows, panels;
            title = "Saved Oxygen $tool diagnostics", collector = "Julia $tool diagnostic",
            scope = "Separate recorded diagnostic sessions; performance=not_compared. These observations are not a controlled release comparison.",
            sources, static,
            metadata = Dict(
                "performance" => "not_compared", "records" => provenance))
    end
end

function export_network_observations(directory; static = true)
    latest_path = joinpath(directory, "latest.json")
    latest = JSON.parsefile(latest_path)
    history_path = joinpath(directory, "history.json")
    history = JSON.parsefile(history_path)["versions"]
    specs = (("latency", "Round-trip latency", "s", sample -> sample["workload_seconds"]),
        ("throughput", "Application throughput (both bodies)", "MiB/s", nothing),
        ("bytes", "Loopback transmit bytes", "By", sample -> sample["bytes_sent"]),
        ("packets", "Loopback transmit packets",
            "packets", sample -> sample["packets_sent"]))
    function project(records, payload = nothing)
        categories = [record["version"] for record in records]
        panels = [observation_panel(id, title,
                      payload === nothing ? "Request body" : "Oxygen release",
                      payload === nothing ? "By" : "", title, unit;
                      categories = payload === nothing ? nothing : categories)
                  for (id, title, unit, _) in specs]
        rows = Dict{String, Any}[]
        for record in records, request in record["records"]
            payload !== nothing && request["payload_bytes"] != payload && continue
            x = payload === nothing ? request["payload_bytes"] : record["version"]
            for (id, _, _, extract) in specs
                values = [id == "throughput" ?
                          2request["payload_bytes"] / sample["workload_seconds"] / 2^20 :
                          extract(sample) for sample in request["samples"]]
                for (index, value) in pairs(values)
                    push!(rows,
                        Dict("panel" => id, "series" => "Samples",
                            "version" => record["version"],
                            "x" => x, "value" => value,
                            "label" => "$(request["payload_bytes"])-byte body · sample $index",
                            "style" => "scatter"))
                end
                push!(rows,
                    Dict(
                        "panel" => id, "series" => "Median", "version" => record["version"],
                        "x" => x, "value" => median(values),
                        "label" => "Median of $(length(values)) recorded exchanges",
                        "style" => "scatterline"))
            end
        end
        return rows, panels
    end
    rows, panels = project([latest])
    scope = latest["scope"] * "; " * latest["counter_note"]
    export_observation_model(directory, "network", rows, panels;
        title = "Oxygen $(latest["version"]): real loopback exchanges", collector = "PerfChecker network runner",
        scope, sources = [latest_path], static,
        metadata = Dict("throughput_definition" => "2 * request_body_bytes / workload_seconds / 2^20; application bodies, not wire traffic"))
    for payload in [request["payload_bytes"] for request in first(history)["records"]]
        rows, panels = project(history, payload)
        export_observation_model(directory, "history-$payload", rows, panels;
            title = "Oxygen patch history: $payload-byte echo", collector = "PerfChecker network runner",
            scope, sources = [history_path], static,
            metadata = Dict("payload_bytes" => payload,
                "throughput_definition" => "2 * request_body_bytes / workload_seconds / 2^20"))
    end
end

function export_diagnostic_observations(directory; static = true)
    source = joinpath(directory, "diagnosis.json")
    records = JSON.parsefile(source)["records"]
    tool(name) = only(filter(record -> record["tool"] == name, records))
    function publish(name, rows, panels, record, title)
        export_observation_model(directory, name, rows, panels; title,
            collector = "Julia $(record["tool"]) diagnostic",
            scope = get(record, "analysis_scope",
                "Recorded $name observations; this source report does not include analysis_scope"),
            sources = [source], static,
            metadata = Dict("tool_version" => get(record, "tool_version", nothing),
                "runtime" => get(record, "runtime", nothing), "correctness" => record["correctness"]))
    end
    latency = tool("latency")
    phases = [("load", "load_seconds"), ("first operation", "first_case_seconds"),
        ("warm operation", "warm_case_seconds")]
    rows = [Dict("panel" => "time", "series" => "Latency", "x" => phase,
                "value" => latency["measurements"][key], "label" => key, "style" => "scatterline")
            for (phase, key) in phases]
    publish("latency",
        rows,
        [observation_panel("time", "Loading, first and warm operation",
            "Phase", "", "Elapsed time", "s"; categories = first.(phases), yscale = "log10")],
        latency,
        "Source loading and operation latency")
    for (name, specs) in (
        ("gc",
            [("allocated_bytes", "Allocation activity", "By"),
                ("gc_seconds", "Garbage-collection time", "s")]),
        ("memory",
            [("state_before_bytes", "State before", "By"),
                ("state_after_bytes", "State after", "By"),
                ("state_and_result_bytes", "State and result", "By"),
                ("process_before", "Process memory before", "By"),
                ("process_after", "Process memory after", "By")]),
        ("locks", [("lock_conflicts", "Observed lock conflicts", "conflicts")]))
        record = tool(name)
        panels = [observation_panel(key, title, "Diagnostic operation", "", title, unit)
                  for (key, title, unit) in specs]
        rows = Dict{String, Any}[]
        for (index, sample) in pairs(record["measurements"]["samples"]),
            (key, title, _) in specs

            value = get(sample, key, nothing)
            if value isa AbstractDict
                for (field, metric) in (("rss_bytes", "RSS"),
                    ("private_bytes", "Private bytes"), ("peak_rss_bytes", "Peak RSS"))
                    haskey(value, field) || continue
                    push!(rows,
                        Dict("panel" => key, "series" => metric, "x" => index,
                            "value" => value[field],
                            "label" => "Recorded operation $index · $(get(value, "provider", "unspecified provider"))",
                            "style" => "scatterline"))
                end
            else
                push!(rows,
                    Dict("panel" => key, "series" => title, "x" => index,
                        "value" => value, "label" => "Recorded operation $index", "style" => "scatterline"))
            end
        end
        publish(name, rows, panels, record, "Recorded $(name) observations")
    end
end

function export_heap_observations(directory; static = true)
    source = joinpath(directory, "heap-types.json")
    record = JSON.parsefile(source)
    categories = [row["type"] for row in record["types"]]
    panels = [
        observation_panel("bytes", "Shallow GC-object sizes", "Object category", "",
            "Shallow bytes", "By"; categories),
        observation_panel("objects", "GC-object count", "Object category",
            "", "Objects", "objects"; categories)]
    rows = [Dict("panel" => panel, "series" => label,
                "x" => row["type"], "value" => row[key],
                "label" => row["type"], "style" => "bar")
            for row in record["types"]
            for (panel, key, label) in (
        ("bytes", "shallow_bytes", "Shallow bytes"), ("objects", "objects", "Objects"))]
    export_observation_model(directory, "heap-types", rows, panels;
        title = "GC-managed object categories in the worker", collector = "Julia heap snapshot",
        scope = record["scope"], sources = [source], static,
        metadata = Dict("artifact_sha256" => record["artifact_sha256"]))
end

function export_massif_observations(directory; static = true)
    for file in filter(name -> occursin(r"^massif-\d+\.json$", name), readdir(directory))
        source = joinpath(directory, file)
        record = JSON.parsefile(source)
        name = splitext(file)[1]
        rows = [Dict("panel" => "memory", "series" => label,
                    "x" => row["time"], "value" => row[key],
                    "label" => "Snapshot $index", "style" => "scatterline")
                for (index, row) in pairs(record["observations"])
                for (key, label) in (("heap_bytes", "Native heap"),
            ("allocator_overhead_bytes", "Allocator overhead"), (
                "stack_bytes", "Tracked stacks"))]
        export_observation_model(directory, name, rows,
            [observation_panel("memory", "Native process memory", "Massif timeline",
                record["time_unit"], "Memory", "By")];
            title = "Massif native heap — process $(split(name, '-')[end])", collector = "Valgrind Massif",
            scope = record["scope"], sources = [source], static)
    end
end

function export_collector_observations(directory)
    catalog_path = joinpath(directory, "catalog.json")
    catalog = JSON.parsefile(catalog_path)
    for view in catalog["views"]
        source = joinpath(directory, view["json"])
        record = JSON.parsefile(source)
        observations = record["records"]
        operations = unique(row["workload"] for row in observations)
        children = Dict{String, Any}[]
        for operation in operations, collector in ("BenchmarkTools", "Chairmarks")
            rows = filter(
                row -> row["workload"] == operation && row["collector"] == collector,
                observations)
            slug = view["id"] * "-" * lowercase(operation) * "-" * lowercase(collector)
            export_normalized_projection(directory, slug, rows;
                title = "$operation · $collector · DataStructures $(record["version"])",
                collector, scope = record["scope"], sources = [source],
                metadata = Dict(
                    "run_ids" => [record["run_ids"][collector == "BenchmarkTools" ? 1 : 2]],
                    "workload" => operation,
                    "single_version" => true))
            push!(children,
                Dict("id" => slug, "operation" => operation,
                    "collector" => collector, "kind" => "normalized_metrics",
                    "html" => slug * ".html", "plot" => slug * ".plot.json",
                    "json" => view["json"]))
        end
        view["normalized_views"] = children
        view["kind"] = "normalized_metrics"
        view["html"] = first(children)["html"]
        view["plot"] = first(children)["plot"]
    end
    open(io -> JSON.print(io, catalog, 2), catalog_path, "w")
end

function export_first_comparison(directory)
    source = joinpath(directory, "source.json")
    capture = JSON.parsefile(source)
    capture["schema_version"] == "perfchecker-legacy-first-comparison/1" ||
        error("Unexpected first-comparison capture schema")
    rows = Dict{String, Any}[]
    for measurement in capture["measurements"]
        samples = measurement["samples"]
        length(samples) == capture["samples_per_version"] ||
            error("Missing native table samples")
        for (field, metric, unit) in (("times", "julia.wall.time", "ns"),
            ("gctimes", "julia.gc.time", "ns"), ("memory", "julia.alloc.bytes", "By"),
            ("allocs", "julia.alloc.count", "1"))
            capture["units"][field] == unit || error("The original collector unit changed")
            push!(rows,
                Dict("version" => measurement["version"], "target_kind" => "release",
                    "metric" => metric, "unit" => unit, "samples" => length(samples),
                    "value" => minimum(sample[field] for sample in samples),
                    "capture_id" => measurement["capture_id"]))
        end
    end
    metadata = Dict(key => capture[key]
    for key in keys(capture)
    if key ∉ ("measurements", "source_sha256"))
    metadata["case_source_sha256"] = capture["source_sha256"]
    metadata["capture_ids"] = [measurement["capture_id"]
                               for measurement in capture["measurements"]]
    return export_normalized_projection(directory, "normalized", rows;
        title = "Bibliography export · first comparison", collector = "BenchmarkTools",
        scope = capture["comparison_scope"] * "; " * capture["state_policy"],
        sources = [source, joinpath(directory, "check-source.jl")], metadata,
        json_name = "normalized.json")
end

# Project one explicitly authorized native capture; this function never measures.
function export_counter_allocation(capture_directory, directory)
    bundle_directory = only(filter(isdir,
        readdir(joinpath(capture_directory, "bundles"); join = true)))
    verify_run_bundle(bundle_directory; require_integrity = true)
    captured = read_run_bundle(bundle_directory)
    raw = captured.manifest["scenario_evidence"]
    raw["status"] == "complete" && raw["correctness"] == "passed" ||
        error("Only a completed counter allocation capture may be projected")
    environment = raw["environment_provenance"]
    target = only(filter(package -> package["name"] == "DataStructures",
        environment["resolved_packages"]))
    target["version"] == "0.19.6" || error("Unexpected captured DataStructures release")
    summary = raw["allocation_profile"]
    summary["profile_evaluations"] == 1 && summary["sample_rate"] == 1.0 ||
        error("The counter example preserves its one native profile evaluation")
    sites = raw["allocation_sites"]
    sum(site["bytes"] for site in sites) == summary["retained_sampled_bytes"] ||
        error("Exclusive allocation events must conserve the sampled byte weight")
    feature = "counter_32768_profile_alloc"
    definitions = [
        Dict("id" => "julia.alloc.bytes/profile-allocs-v1",
            "metric" => "julia.alloc.bytes", "unit" => "By"),
        Dict("id" => "julia.alloc.count/profile-allocs-v1",
            "metric" => "julia.alloc.count", "unit" => "1")]
    observations = Dict{String, Any}[]
    for (index, site) in pairs(sites)
        # Retain native leaf attribution. Ancestor stack weights are never summed.
        frames = site["stack"]
        boundary = findfirst(frame -> frame["function"] == "count_events", frames)
        boundary === nothing && error("The native stack lacks the recorded workload")
        stack = ["$(frame["function"]) ($(PerfChecker._short_source_path(frame["file"])):$(frame["line"]))"
                 for frame in reverse(frames[1:boundary])]
        for (metric, unit, value) in (("julia.alloc.bytes", "By", site["bytes"]),
            ("julia.alloc.count", "1", 1))
            push!(observations,
                Dict("case_id" => feature, "target_id" => "0.19.6",
                    "metric" => metric, "unit" => unit, "value" => value,
                    "sample_index" => index, "measurement_definition" => "$metric/profile-allocs-v1",
                    "scope" => "exclusive_native_leaf", "attributes" => Dict(
                        "package" => "DataStructures", "feature" => feature,
                        "version" => "0.19.6", "target_kind" => "release",
                        "source_file" => site["file"], "source_line" => site["line"],
                        "stack" => stack)))
        end
    end
    projection = RunBundle(deepcopy(captured.manifest), definitions, observations,
        deepcopy(captured.diagnostics), deepcopy(captured.artifacts))
    source_name = "counter-allocation-source.json"
    source = Dict("run_id" => captured.manifest["run_id"],
        "scenario" => captured.manifest["scenario"], "scenario_evidence" => raw,
        "input_fingerprints" => captured.manifest["input_fingerprints"],
        "raw_manifest_sha256" => bytes2hex(sha256(read(joinpath(
            bundle_directory, "manifest.json")))),
        "worker_budget_seconds" => 120, "exclusive_observations" => observations,
        "warmup_operations" => 1,
        "environment_files" => Dict(
            "counter-allocation-project.toml" => environment["project_sha256"],
            "counter-allocation-manifest.toml" => environment["manifest_sha256"]),
        "projection_source_sha256" => bytes2hex(sha256(read(@__FILE__))),
        "weight_semantics" => "raw sampled bytes at native leaf sites; not scaled to independently measured operation totals")
    open(io -> JSON.print(io, source, 2), joinpath(directory, source_name), "w")
    for name in ("Project.toml", "Manifest.toml")
        cp(joinpath(capture_directory, "worker", name),
            joinpath(directory, "counter-allocation-" * lowercase(name)); force = true)
    end
    catalog_path = joinpath(directory, "catalog.json")
    catalog = JSON.parsefile(catalog_path)
    filter!(view -> get(view, "feature", "") != feature, catalog["views"])
    filter!(run -> get(run, "feature", "") != feature, catalog["runs"])
    push!(catalog["runs"],
        Dict("package" => "DataStructures", "feature" => feature,
            "version" => "0.19.6", "status" => "pass", "run_id" => captured.manifest["run_id"]))
    for entry in plot_catalog(projection)
        entry["kind"] in ("allocation_flamegraph", "allocation_pie", "allocation_lines") ||
            continue
        model = performance_plot(projection, entry["id"])
        model = PerfChecker.PerformancePlot(model.id, model.kind, model.title,
            "DataStructures 0.19.6; 32,768-event counter; one native allocation profile. Raw sampled bytes, not independent operation totals.",
            model.encoding, model.data,
            merge(model.options,
                Dict("metadata" => Dict(
                    "run_id" => captured.manifest["run_id"], "allocation_profile" => summary,
                    "source_sha256" => Dict(source_name => bytes2hex(sha256(read(joinpath(
                        directory, source_name)))))))))
        name = "counter-" * string(model.kind)
        json_name, html_name = name * ".json", name * ".html"
        open(
            io -> JSON.print(io,
                Dict("plot" => performance_plot_dict(model),
                    "allocation_profile" => summary, "runtime" => raw["runtime"],
                    "correctness" => raw["correctness"], "performance" => "not_compared"),
                2),
            joinpath(directory, json_name), "w")
        write(joinpath(directory, html_name),
            performance_plot_html(model;
                asset_directory = normpath(joinpath(directory, "../../plot-assets")),
                html_directory = directory))
        push!(catalog["views"],
            merge(entry,
                Dict("json" => json_name,
                    "html" => html_name, "evidence" => source_name,
                    "capture_note" => "One native counter profile: $(summary["retained_sampled_bytes"]) sampled bytes across $(summary["retained_allocations"]) events; independently measured whole-operation totals are $(summary["total_bytes"]) bytes and $(summary["total_allocations"]) allocations. The sampled pie is not rescaled to those totals.",
                    "capture_conditions" => Dict("Fixture" => "32,768 events; seed 42",
                        "Correctness oracle" => raw["correctness"],
                        "Julia" => raw["runtime"]["version"], "Worker threads" => raw["runtime"]["threads"],
                        "Sampling rate" => summary["sample_rate"],
                        "Profile evaluations" => summary["profile_evaluations"],
                        "Pairing" => "Independent totals and sampled events come from separate evaluations; matching allocation counts do not establish a pairing."),
                    "html_input_sha256" => bytes2hex(sha256(read(joinpath(
                        directory, json_name)))))))
    end
    open(io -> JSON.print(io, catalog, 2), catalog_path, "w")
    return summary
end

function export_documentation_observations(root)
    bibliography = normpath(joinpath(root, "../bibliography"))
    export_first_comparison(joinpath(bibliography, "first-comparison"))
    quick_source = joinpath(bibliography, "export-normalized.json")
    quick_hash = bytes2hex(sha256(read(quick_source)))
    quick = saved_plot(quick_source)
    quick.kind === :normalized_metrics ||
        error("Bibliography timing must use the canonical normalized plot")
    quick_before = deepcopy(performance_plot_dict(quick))
    write(joinpath(bibliography, "export-normalized.html"), performance_plot_html(quick))
    performance_plot_dict(quick) == quick_before ||
        error("Rendering changed Bibliography measurements")
    bytes2hex(sha256(read(quick_source))) == quick_hash ||
        error("Rendering changed Bibliography source")
    for campaign in ("chairmarks-history", "chairmarks-quick", "first-comparison")
        chair_source = joinpath(bibliography, campaign, "normalized.json")
        isfile(chair_source) ||
            error("The documented timing campaign needs its authentic recorded model")
        chair_hash = bytes2hex(sha256(read(chair_source)))
        chair = saved_plot(chair_source)
        chair.kind === :normalized_metrics ||
            error("Timing collectors must use normalized metrics")
        chair_before = deepcopy(performance_plot_dict(chair))
        write(joinpath(dirname(chair_source), "normalized.html"),
            performance_plot_html(chair))
        performance_plot_dict(chair) == chair_before ||
            error("Rendering changed timing measurements")
        bytes2hex(sha256(read(chair_source))) == chair_hash ||
            error("Rendering changed timing source")
    end
    pie_source = joinpath(bibliography, "profiles/allocation-pie.json")
    pie_hash = bytes2hex(sha256(read(pie_source)))
    pie = saved_plot(pie_source)
    pie.kind === :allocation_pie ||
        error("The case study requires the native allocation pie")
    pie_before = deepcopy(performance_plot_dict(pie))
    write(joinpath(dirname(pie_source), "allocation-pie.html"), performance_plot_html(pie))
    performance_plot_dict(pie) == pie_before ||
        error("Rendering changed allocation observations")
    bytes2hex(sha256(read(pie_source))) == pie_hash ||
        error("Rendering changed allocation source")
    export_network_observations(joinpath(root, "oxygen-network"))
    for package in ("datastructures", "oxygen")
        export_diagnostic_observations(joinpath(root, package * "-diagnostics"))
        export_heap_observations(joinpath(root, package * "-diagnostics"))
        export_massif_observations(joinpath(root, package * "-native"))
    end
    export_collector_observations(joinpath(root, "containers-collectors"))
    export_saved_oxygen_diagnostics(joinpath(root, "oxygen-saved-diagnostics"))
end
