# Shared, reproducible frontend exports from the published observations. These
# functions are used by the capture exporters and by publish-evidence.jl.
using PerfChecker, PerfCheckerMakie, WGLMakie, CairoMakie, JSON, SHA, Statistics

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

function export_saved_oxygen_diagnostics(directory)
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
            sources, metadata = Dict(
                "performance" => "not_compared", "records" => provenance))
    end
end

function export_network_observations(directory)
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
        scope, sources = [latest_path],
        metadata = Dict("throughput_definition" => "2 * request_body_bytes / workload_seconds / 2^20; application bodies, not wire traffic"))
    for payload in [request["payload_bytes"] for request in first(history)["records"]]
        rows, panels = project(history, payload)
        export_observation_model(directory, "history-$payload", rows, panels;
            title = "Oxygen patch history: $payload-byte echo", collector = "PerfChecker network runner",
            scope, sources = [history_path],
            metadata = Dict("payload_bytes" => payload,
                "throughput_definition" => "2 * request_body_bytes / workload_seconds / 2^20"))
    end
end

function export_diagnostic_observations(directory)
    source = joinpath(directory, "diagnosis.json")
    records = JSON.parsefile(source)["records"]
    tool(name) = only(filter(record -> record["tool"] == name, records))
    function publish(name, rows, panels, record, title)
        export_observation_model(directory, name, rows, panels; title,
            collector = "Julia $(record["tool"]) diagnostic",
            scope = get(record, "analysis_scope",
                "Recorded $name observations; this source report does not include analysis_scope"),
            sources = [source],
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

function export_heap_observations(directory)
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
        scope = record["scope"], sources = [source],
        metadata = Dict("artifact_sha256" => record["artifact_sha256"]))
end

function export_massif_observations(directory)
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
            scope = record["scope"], sources = [source])
    end
end

function export_collector_observations(directory)
    catalog_path = joinpath(directory, "catalog.json")
    catalog = JSON.parsefile(catalog_path)
    for view in catalog["views"]
        source = joinpath(directory, view["json"])
        record = JSON.parsefile(source)
        observations = record["records"]
        metrics = unique(row["metric"] for row in observations)
        operations = unique(row["workload"] for row in observations)
        panels = [observation_panel(
                      metric, replace(metric, "julia." => ""), "Operation", "",
                      replace(metric, "julia." => ""),
                      only(unique(row["unit"]
                      for row in observations if row["metric"] == metric));
                      categories = operations) for metric in metrics]
        rows = [Dict("panel" => row["metric"],
                    "series" => row["collector"], "x" => row["workload"],
                    "value" => row["value"], "version" => row["version"], "style" => "bar",
                    "label" => "$(row["derivation"]) · $(row["samples"]) samples")
                for row in observations]
        export_observation_model(directory, view["id"], rows, panels;
            title = "$(record["family"]) · DataStructures $(record["version"])",
            collector = "BenchmarkTools and Chairmarks", scope = record["scope"], sources = [source],
            metadata = Dict("run_ids" => record["run_ids"]))
        view["html"] = view["id"] * ".html"
        view["plot"] = view["id"] * ".plot.json"
        view["kind"] = "observation_series"
    end
    open(io -> JSON.print(io, catalog, 2), catalog_path, "w")
end

function export_documentation_observations(root)
    export_network_observations(joinpath(root, "oxygen-network"))
    for package in ("datastructures", "oxygen")
        export_diagnostic_observations(joinpath(root, package * "-diagnostics"))
        export_heap_observations(joinpath(root, package * "-diagnostics"))
        export_massif_observations(joinpath(root, package * "-native"))
    end
    export_collector_observations(joinpath(root, "containers-collectors"))
    export_saved_oxygen_diagnostics(joinpath(root, "oxygen-saved-diagnostics"))
end
