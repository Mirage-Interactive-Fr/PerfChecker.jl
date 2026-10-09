using PerfChecker, UnicodePlots, JSON

"Load one saved bundle from a report directory, or a bundle directory itself."
function example_bundle(path)
    directory = isfile(joinpath(path, "manifest.json")) ? path :
                only(filter(isdir, readdir(joinpath(path, "bundles"); join = true)))
    verify_run_bundle(directory; require_integrity = true)
    read_run_bundle(directory)
end

function _replay_values_match(tradeoff, series, field)
    rows = Dict{Tuple{String, String}, Any}()
    for row in series
        all(key -> haskey(row, key), ("version", "target_kind", "value")) || return false
        key = (String(row["version"]), String(row["target_kind"]))
        haskey(rows, key) && return false
        rows[key] = row
    end
    length(rows) == length(tradeoff) || return false
    seen = Set{Tuple{String, String}}()
    for row in tradeoff
        all(key -> haskey(row, key), ("version", "target_kind", field)) || return false
        key = (String(row["version"]), String(row["target_kind"]))
        key in seen && return false
        push!(seen, key)
        source = get(rows, key, nothing)
        source === nothing && return false
        _replay_shared_identities(row, source,
            ("aggregation", "comparison_key", "measurement_definition")) === nothing &&
            return false
        value = source["value"]
        value isa Real && isfinite(value) && value == row[field] || return false
    end
    return true
end

function _replay_shared_identities(left, right, keys)
    verified = String[]
    for key in keys
        haskey(left, key) && haskey(right, key) || continue
        (left[key] === nothing || right[key] === nothing) && continue
        (left[key] == "" || right[key] == "") && continue
        left[key] == right[key] || return nothing
        push!(verified, key)
    end
    return verified
end

"Resolve legacy tradeoff units only from uniquely matching published series; never edit evidence."
function _replay_tradeoff_options(path, record, plot)
    options = Dict{String, Any}(plot["options"])
    plot["kind"] == "time_allocation_tradeoff" || return options
    all(key -> haskey(options, key), ("time_unit", "allocation_unit")) && return options
    options["unit_resolution"] = "no compatible published series"
    catalog_path = joinpath(dirname(path), "catalog.json")
    isfile(catalog_path) && get(record, "run_id", nothing) isa AbstractString ||
        return options
    isempty(record["run_id"]) && return options
    catalog = JSON.parsefile(catalog_path)
    entries = get(catalog, "views", [])
    originals = filter(
        entry -> get(entry, "id", nothing) == plot["id"] &&
            get(entry, "json", nothing) == basename(path),
        entries)
    length(originals) == 1 || return options
    identity_keys = ("package", "feature", "comparison_key", "collector", "aggregation",
        "measurement_definition", "definition")
    _replay_shared_identities(only(originals), options, identity_keys) === nothing &&
        return options
    identity = merge(only(originals), options)
    candidates = Dict("julia.wall.time" => Any[], "julia.alloc.bytes" => Any[])
    for entry in entries
        get(entry, "kind", nothing) == "version_series" || continue
        metric = get(entry, "metric", nothing)
        haskey(candidates, metric) || continue
        filename = get(entry, "json", "")
        filename isa String && basename(filename) == filename &&
            endswith(filename, ".json") || continue
        source_path = joinpath(dirname(path), filename)
        isfile(source_path) && !islink(source_path) || continue
        source = JSON.parsefile(source_path)
        get(source, "run_id", nothing) == record["run_id"] || continue
        source_plot = get(source, "plot", nothing)
        source_plot isa AbstractDict || continue
        get(source_plot, "kind", nothing) == "version_series" || continue
        get(source_plot, "id", nothing) == get(entry, "id", nothing) || continue
        source_options = get(source_plot, "options", Dict())
        _replay_shared_identities(entry, source_options, identity_keys) === nothing &&
            continue
        get(source_options, "metric", nothing) == metric || continue
        all(
            key -> haskey(options, key) && get(source_options, key, nothing) == options[key],
            ("package", "feature")) || continue
        metadata = _replay_shared_identities(record, source,
            ("runtime", "os", "worker_environments"))
        metadata === nothing && continue
        source_identity = merge(entry, source_options)
        shared = _replay_shared_identities(identity, source_identity,
            ("comparison_key", "collector", "aggregation"))
        shared === nothing && continue
        data = get(source_plot, "data", [])
        _replay_values_match(plot["data"], data,
            metric == "julia.wall.time" ? "time" : "bytes") || continue
        unit = get(source_options, "unit", "")
        unit == get(entry, "unit", nothing) || continue
        try
            metric == "julia.wall.time" ? PerfChecker._tradeoff_units(unit, "By") :
            PerfChecker._tradeoff_units("s", unit)
        catch error
            error isa ArgumentError || rethrow()
            options["unit_resolution"] = "incompatible published series units"
            continue
        end
        series_id = get(source_options, "series_id", "")
        !isempty(series_id) && series_id == get(entry, "series_id", nothing) || continue
        definitions = unique([String(source_identity[key])
                              for key in ("measurement_definition", "definition")
                              if haskey(source_identity, key)])
        length(definitions) <= 1 || continue
        definition = isempty(definitions) ? nothing : only(definitions)
        collector = definition === nothing ? get(source_identity, "collector", nothing) :
                    startswith(definition, metric * "/") ?
                    chop(definition; head = length(metric) + 1, tail = 0) : definition
        haskey(source_identity, "collector") && collector !== nothing &&
            source_identity["collector"] != collector && continue
        haskey(identity, "collector") && collector !== nothing &&
            identity["collector"] != collector && continue
        definition_key = metric == "julia.wall.time" ? "time_definition" :
                         "allocation_definition"
        expected_definition = get(identity, definition_key,
            get(identity, "measurement_definition", get(identity, "definition", nothing)))
        expected_definition !== nothing && definition !== nothing &&
            !(expected_definition in (definition, collector)) && continue
        aggregations = unique([String(row["aggregation"])
                               for row in data if haskey(row, "aggregation")])
        length(aggregations) <= 1 || continue
        aggregation = isempty(aggregations) ||
                      !all(row -> haskey(row, "aggregation"), data) ?
                      nothing : only(aggregations)
        haskey(identity, "aggregation") && aggregation !== nothing &&
            identity["aggregation"] != aggregation && continue
        push!(candidates[metric],
            (; unit, series_id, collector, aggregation,
                provenance = Dict("json" => filename,
                    "sha256" => bytes2hex(PerfChecker.SHA.sha256(read(source_path))),
                    "series_id" => series_id, "metric" => metric, "unit" => unit,
                    "measurement_definition" => definition, "source_collector" => collector,
                    "aggregation" => aggregation,
                    "verified_shared_fields" => vcat(
                        ["run_id", "package", "feature",
                            "versions", "target_kind", "values"],
                        metadata, shared))))
    end
    if any(items -> length(items) > 1, values(candidates))
        options["unit_resolution"] = "ambiguous published series"
        return options
    end
    all(items -> length(items) == 1, values(candidates)) || return options
    time = only(candidates["julia.wall.time"])
    allocation = only(candidates["julia.alloc.bytes"])
    for key in (:collector, :aggregation)
        left, right = getproperty(time, key), getproperty(allocation, key)
        if left !== nothing && right !== nothing && left != right
            options["unit_resolution"] = "incompatible published series identities"
            return options
        end
    end
    units = try
        PerfChecker._tradeoff_units(time.unit, allocation.unit)
    catch error
        error isa ArgumentError || rethrow()
        options["unit_resolution"] = "incompatible published series units"
        return options
    end
    options["time_unit"], options["allocation_unit"] = units
    options["unit"] = join(units, "+")
    options["time_series_id"] = time.series_id
    options["allocation_series_id"] = allocation.series_id
    options["unit_source"] = "published_series_replay"
    options["unit_resolution"] = "unique matching published series"
    options["unit_provenance"] = Dict(
        "saved_model_sha256" => bytes2hex(PerfChecker.SHA.sha256(read(path))),
        "catalog_sha256" => bytes2hex(PerfChecker.SHA.sha256(read(catalog_path))),
        "sources" => [time.provenance, allocation.provenance])
    return options
end

"""
Restore a published, backend-neutral plot without running its workload.
Legacy tradeoff units may be resolved from unique compatible series in the
neighboring catalogue. The returned model records those source hashes; the
saved JSON is unchanged and this does not reconstruct or verify a run bundle.
Missing or ambiguous associations remain explicitly unresolved.
"""
function saved_plot(path)
    record = JSON.parsefile(path)
    d = get(record, "plot", record)
    d["schema_version"] == "perfchecker-plot/1" || error("Unsupported plot format")
    PerfChecker.PerformancePlot(d["id"], Symbol(d["kind"]), d["title"], d["description"],
        Dict{String, Any}(d["encoding"]), Dict{String, Any}[Dict(row) for row in d["data"]],
        _replay_tradeoff_options(path, record, d))
end

if abspath(PROGRAM_FILE) == @__FILE__
    isempty(ARGS) &&
        error("Pass a report directory or a published plot.json, optionally an output directory")
    output = length(ARGS) > 1 ? abspath(ARGS[2]) : joinpath(@__DIR__, "exports", "terminal")
    mkpath(output)
    plots = if endswith(ARGS[1], ".json")
        [saved_plot(ARGS[1])]
    else
        bundle = example_bundle(abspath(ARGS[1]))
        [performance_plot(bundle, entry["id"]) for entry in plot_catalog(bundle)]
    end
    for model in plots
        text = sprint(
            show, MIME"text/plain"(), terminal_plot(model); context = :color => false)
        write(joinpath(output, model.id * ".txt"), text)
        println(model.title, "\n", text)
    end
    println("Saved ", length(plots), " terminal plots to ", output)
end
