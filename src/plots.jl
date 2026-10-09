const PERFORMANCE_PLOT_SCHEMA = "perfchecker-plot/1"

"""
    PerformancePlot(id, kind, title, description, encoding, data, options)

Backend-neutral saved-evidence view with plot identity/kind, human-readable
labels, field encodings, data records and renderer options. Obtain a validated
model with [`performance_plot`](@ref), then render it using an interface package
or serialize it using [`performance_plot_dict`](@ref). This internal model
stores records without starting a measurement or choosing a graphics backend.
"""
struct PerformancePlot
    id::String
    kind::Symbol
    title::String
    description::String
    encoding::Dict{String, Any}
    data::Vector{Dict{String, Any}}
    options::Dict{String, Any}
end

"""
    performance_plot_dict(plot::PerformancePlot)

Return `perfchecker-plot/1` with identity, string kind, title, description,
encoding, data and options. Nested dictionaries and records are retained, not
deep-copied. No renderer is loaded and no report, HTML or image is written.
"""
function performance_plot_dict(plot::PerformancePlot)
    return Dict{String, Any}(
        "schema_version" => PERFORMANCE_PLOT_SCHEMA,
        "id" => plot.id,
        "kind" => string(plot.kind),
        "title" => plot.title,
        "description" => plot.description,
        "encoding" => plot.encoding,
        "data" => plot.data,
        "options" => plot.options)
end

function _plot_id(kind::Symbol, identity...)
    return "$(replace(string(kind), '_' => '-'))-$(_content_digest((kind, identity...))[1:16])"
end

# Choose a renderer without changing the definition or comparison key carried
# by the evidence. Fresh-state measurements retain their distinct identity.
function _plot_collector_definition(definition::AbstractString)
    suffix = "/fresh-state-evals1-v1"
    return endswith(definition, suffix) ? chop(definition; tail = length(suffix)) :
           definition
end

function _series_catalog(bundle::RunBundle)
    entries = Dict{String, Any}[]
    series = suite_version_series(bundle)
    for item in series
        identity = String(item["series_id"])
        common = Dict{String, Any}(
            "package" => item["package"], "feature" => item["feature"],
            "metric" => item["metric"], "unit" => item["unit"],
            "series_id" => identity)
        kinds = _plot_collector_definition(item["measurement_definition"]) in (
            "julia.alloc.bytes/line-tracking-v1", "julia.alloc.bytes/profile-allocs-v1",
            "julia.alloc.count/profile-allocs-v1", "julia.cpu.samples/profile-v1",
            "julia.wall.samples/profile-walltime-v1") ?
                ((:version_series, "Version trajectory"),
            (:version_delta, "Regression deltas")) :
                ((:version_series, "Version trajectory"),
            (:distribution, "Sample distribution"),
            (:version_delta, "Regression deltas"))
        for (kind, label) in kinds
            push!(entries,
                merge(copy(common),
                    Dict{String, Any}(
                        "id" => _plot_id(kind, identity), "kind" => string(kind),
                        "title" => "$(item["package"]) · $(item["feature"]) · $(item["metric"])",
                        "label" => label)))
        end
    end
    return entries
end

function _plot_base_comparison_key(series)
    suffix = "::$(series["measurement_definition"])"
    key = String(series["comparison_key"])
    return endswith(key, suffix) ? chop(key; tail = length(suffix)) : key
end

# A zero reference cannot define a quotient. Equal zeros are displayed at the
# unchanged line by convention; nonzero/zero remains unavailable, never Inf.
function _relative_measurement(value, reference)
    iszero(reference) ?
    (iszero(value) ? 1.0 : nothing) : Float64(value / reference)
end

function _normalized_groups(bundle)
    groups = Dict{Tuple, Vector{Dict{String, Any}}}()
    for series in (bundle isa RunBundle ? suite_version_series(bundle) : bundle)
        metric = series["metric"]
        metric in ("julia.wall.time", "julia.gc.time", "julia.gc.fraction",
            "julia.alloc.bytes", "julia.alloc.count") || continue
        definition = String(series["measurement_definition"])
        startswith(definition, "$metric/") || continue
        collector = chop(definition; head = length(metric) + 1, tail = 0)
        (startswith(collector, "benchmarktools-v1") ||
         startswith(collector, "chairmarks-v1")) || continue
        key = (series["package"], series["feature"], series["workload"],
            _plot_base_comparison_key(series), collector)
        push!(get!(groups, key, Dict{String, Any}[]), series)
    end
    order = ("julia.wall.time", "julia.gc.time", "julia.gc.fraction",
        "julia.alloc.bytes", "julia.alloc.count")
    for series in values(groups)
        sort!(series; by = item -> findfirst(==(item["metric"]), order))
    end
    return groups
end

function _normalized_catalog(bundle)
    return [Dict{String, Any}(
                "id" => _plot_id(:normalized_metrics, key...),
                "kind" => "normalized_metrics", "package" => key[1],
                "feature" => key[2], "workload" => key[3],
                "comparison_key" => key[4], "collector" => key[5],
                "metric" => "benchmark metrics", "unit" => "ratio",
                "title" => "$(key[1]) · $(key[2]) · relative to minimum",
                "label" => "Overlaid measurements · minimum = 1")
            for (key, series) in sort!(collect(_normalized_groups(bundle)); by = first)
            if length(series) > 1]
end

function _normalized_records(
        bundle, entry; reference_version = nothing, statistic::Symbol = :minimum)
    statistic in (:minimum, :median) ||
        throw(ArgumentError("statistic must be minimum or median"))
    function measure(point)
        get(get(point, "statistics", Dict()), string(statistic), point["median"])
    end
    key = (entry["package"], entry["feature"], entry["workload"],
        entry["comparison_key"], entry["collector"])
    series = _normalized_groups(bundle)[key]
    points = sort!(
        unique(vcat([item["points"] for item in series]...)); by = _version_point_key)
    versions = unique(String[point["version"] for point in points])
    reference = isnothing(reference_version) ? "minimum" :
                reference_version === :latest ? last(versions) : String(reference_version)
    (isnothing(reference_version) || reference in versions) ||
        throw(ArgumentError("unknown reference version $reference"))
    records = Dict{String, Any}[]
    for item in series
        baseline = isnothing(reference_version) ? item["points"] :
                   filter(p -> p["version"] == reference, item["points"])
        denominator = isempty(baseline) ? nothing : minimum(measure.(baseline))
        indexed = Dict(point["version"] => point for point in item["points"])
        for version in versions
            if !haskey(indexed, version)
                push!(records,
                    Dict{String, Any}("version" => version,
                        "target_kind" => "unavailable", "metric" => item["metric"],
                        "value" => nothing, "unit" => item["unit"], "samples" => 0,
                        "ratio" => nothing, "reference_value" => denominator,
                        "reference_version" => reference, "statistic" => string(statistic),
                        "normalization_status" => "missing_measurement"))
                continue
            end
            point = indexed[version]
            value = measure(point)
            ratio = isnothing(denominator) ? nothing :
                    _relative_measurement(value, denominator)
            status = isnothing(denominator) ? "missing_reference" :
                     iszero(denominator) ?
                     (iszero(value) ? "both_zero" : "zero_reference") : "ratio"
            push!(records,
                Dict{String, Any}("version" => point["version"],
                    "target_kind" => point["target_kind"], "metric" => item["metric"],
                    "value" => value, "unit" => item["unit"], "samples" => point["samples"],
                    "ratio" => ratio, "reference_value" => denominator,
                    "reference_version" => reference, "statistic" => string(statistic), "normalization_status" => status))
        end
    end
    return records, versions, reference
end

function _normalized_plot(
        source, entry; reference_version = nothing, statistic::Symbol = :minimum)
    data, versions, reference = _normalized_records(
        source, entry; reference_version, statistic)
    options = Dict{String, Any}(
        "package" => entry["package"], "feature" => entry["feature"],
        "workload" => entry["workload"], "unit" => "ratio", "versions" => versions,
        "reference_version" => reference, "statistic" => string(statistic), "collector" => entry["collector"],
        "tags" => source isa RunBundle ? get(source.manifest, "tags", String[]) : String[],
        "zero_reference_policy" => "equal zeros = 1 (unchanged); nonzero / zero = unavailable")
    return PerformancePlot(entry["id"], :normalized_metrics,
        "$(entry["package"]) · $(entry["feature"]) · relative to $reference",
        "$statistic per version / reference ($reference) for each metric; 1 = reference, above 1 = more, below 1 = less. " *
        options["zero_reference_policy"],
        Dict{String, Any}("x" => "version", "y" => "ratio", "color" => "metric"), data, options)
end

function _allocation_observations(bundle::RunBundle)
    return [observation
            for observation in bundle.observations
            if _plot_collector_definition(get(observation, "measurement_definition", "")) in (
        "julia.alloc.bytes/line-tracking-v1",
        "julia.alloc.bytes/profile-allocs-v1") &&
               get(get(observation, "attributes", Dict()), "source_file", nothing) !==
               nothing]
end

function _allocation_catalog(bundle::RunBundle)
    identities = Dict{Tuple{String, String, String}, Dict{String, Any}}()
    for observation in _allocation_observations(bundle)
        attributes = observation["attributes"]
        package = String(get(attributes, "package", "package"))
        feature = String(get(attributes, "feature", "feature"))
        case_id = String(get(observation, "case_id", "$package/$feature"))
        identities[(package, feature, case_id)] = Dict{String, Any}(
            "package" => package, "feature" => feature, "case_id" => case_id)
    end
    entries = Dict{String, Any}[]
    for ((package, feature, case_id), common) in sort!(collect(identities); by = first)
        for (kind, label) in ((:allocation_pie, "Allocation share by line (%)"),
            (:allocation_files, "Allocations by file"),
            (:allocation_lines, "Allocation hotspots by line"),
            (:allocation_heatmap, "Allocation line heatmap"))
            push!(entries,
                merge(copy(common),
                    Dict{String, Any}(
                        "id" => _plot_id(kind, case_id), "kind" => string(kind),
                        "title" => "$package · $feature · allocations", "label" => label,
                        "metric" => "julia.alloc.bytes", "unit" => "By")))
        end
        observations = _allocation_records(bundle, case_id)
        if any(
            observation -> get(get(observation, "attributes", Dict()),
                "stack", nothing) isa AbstractVector,
            observations)
            push!(entries,
                merge(copy(common),
                    Dict{String, Any}(
                        "id" => _plot_id(:allocation_flamegraph, case_id),
                        "kind" => "allocation_flamegraph",
                        "title" => "$package · $feature · allocation flame graph",
                        "label" => "Allocation flame graph",
                        "metric" => "julia.alloc.bytes", "unit" => "By")))
        end
    end
    return entries
end

function _profile_catalog(bundle::RunBundle)
    identities = Dict{Tuple{String, String, String, String}, Dict{String, Any}}()
    for observation in bundle.observations
        definition = get(observation, "measurement_definition", "")
        _plot_collector_definition(definition) in ("julia.cpu.samples/profile-v1",
            "julia.wall.samples/profile-walltime-v1") || continue
        attributes = get(observation, "attributes", Dict())
        get(attributes, "stack", nothing) isa AbstractVector || continue
        package = String(get(attributes, "package", "package"))
        feature = String(get(attributes, "feature", "feature"))
        case_id = String(get(observation, "case_id", "$package/$feature"))
        identities[(package, feature, case_id, definition)] = Dict{String, Any}(
            "package" => package, "feature" => feature, "case_id" => case_id,
            "definition" => definition)
    end
    return [merge(copy(common),
                Dict{String, Any}(
                    "id" => _plot_id(
                        _plot_collector_definition(definition) ==
                        "julia.cpu.samples/profile-v1" ?
                        :cpu_flamegraph : :wall_flamegraph,
                        definition == _plot_collector_definition(definition) ?
                        case_id : "$case_id::$definition"),
                    "kind" => _plot_collector_definition(definition) ==
                              "julia.cpu.samples/profile-v1" ?
                              "cpu_flamegraph" : "wall_flamegraph",
                    "title" => "$package · $feature · " *
                               (_plot_collector_definition(definition) ==
                                "julia.cpu.samples/profile-v1" ? "CPU" :
                                "wall-time") *
                               " flame graph",
                    "label" => _plot_collector_definition(definition) ==
                               "julia.cpu.samples/profile-v1" ?
                               "CPU flame graph" : "Wall-time flame graph",
                    "metric" => _plot_collector_definition(definition) ==
                                "julia.cpu.samples/profile-v1" ?
                                "julia.cpu.samples" : "julia.wall.samples",
                    "unit" => "samples"))
            for ((package, feature, case_id, definition), common) in sort!(
        collect(identities); by = first)]
end

function _tradeoff_collector(series)
    metric = String(series["metric"])
    definition = String(series["measurement_definition"])
    return startswith(definition, "$metric/") ?
           chop(definition; head = length(metric) + 1, tail = 0) : definition
end

"""
    _tradeoff_units(time_unit, allocation_unit)

Validate a tradeoff's recorded time and allocation dimensions and return their
unit strings without converting values. Time accepts `s`, `ms`, `us`, `µs`, `μs`
or `ns`; allocation accepts bytes (`By`). Unsupported dimensions raise
`ArgumentError`.
"""
function _tradeoff_units(time_unit, allocation_unit)
    time_unit in ("s", "ms", "us", "µs", "μs", "ns") ||
        throw(ArgumentError("Tradeoff time requires an explicit supported time unit"))
    allocation_unit == "By" ||
        throw(ArgumentError("Tradeoff allocation requires recorded bytes (By)"))
    return String(time_unit), String(allocation_unit)
end

"""
    _tradeoff_plot_units(options)

Read and validate explicit `time_unit` and `allocation_unit` plot options.
If either is absent, return `("unit unspecified", "unit unspecified")`: legacy
combined labels such as `s+By` did not establish the original units. Present but
incompatible units raise `ArgumentError`; numeric measurements are unchanged.
"""
function _tradeoff_plot_units(options)
    # Older serialized models stamped s+By without checking their source units.
    # That combined label cannot establish the dimensions of their raw values.
    all(key -> haskey(options, key), ("time_unit", "allocation_unit")) ||
        return ("unit unspecified", "unit unspecified")
    return _tradeoff_units(options["time_unit"], options["allocation_unit"])
end

function _tradeoff_catalog(bundle::RunBundle)
    grouped = Dict{NTuple{4, String}, Dict{String, Vector{Any}}}()
    for series in suite_version_series(bundle)
        metric = String(series["metric"])
        metric in ("julia.wall.time", "julia.alloc.bytes") || continue
        key = (String(series["package"]), String(series["feature"]),
            _plot_base_comparison_key(series), _tradeoff_collector(series))
        metrics = get!(grouped, key, Dict{String, Vector{Any}}())
        push!(get!(metrics, metric, Any[]), series)
    end
    entries = Dict{String, Any}[]
    complete = filter(
        pair -> all(haskey(last(pair), metric)
        for metric in ("julia.wall.time", "julia.alloc.bytes")),
        collect(grouped))
    valid = filter(complete) do pair
        candidates = last(pair)
        all(records -> length(records) == 1, values(candidates)) || return false
        time_unit = get(only(candidates["julia.wall.time"]), "unit", "")
        allocation_unit = get(only(candidates["julia.alloc.bytes"]), "unit", "")
        return time_unit in ("s", "ms", "us", "µs", "μs", "ns") && allocation_unit == "By"
    end
    # Filter first: unavailable pairs must not rename the valid collector's ID
    # or hide independent series/distribution views.
    for ((package, feature, comparison_key, collector), candidates) in sort!(
        valid; by = first)
        metrics = Dict(metric => only(records) for (metric, records) in candidates)
        time_unit = get(metrics["julia.wall.time"], "unit", "")
        allocation_unit = get(metrics["julia.alloc.bytes"], "unit", "")
        # Retain existing IDs for one collector. Ambiguous comparisons get
        # distinct IDs and labels; measurements are never combined across tools.
        multiple = count(
            pair -> first(pair)[1:3] == (package, feature, comparison_key), valid) > 1
        identity = multiple ? (comparison_key, collector) : (comparison_key,)
        suffix = multiple ? " · $collector" : ""
        push!(entries,
            Dict{String, Any}(
                "id" => _plot_id(
                    :time_allocation_tradeoff, package, feature, identity...),
                "kind" => "time_allocation_tradeoff", "package" => package,
                "feature" => feature, "comparison_key" => comparison_key,
                "collector" => collector,
                "time_series_id" => metrics["julia.wall.time"]["series_id"],
                "allocation_series_id" => metrics["julia.alloc.bytes"]["series_id"],
                "metric" => "julia.wall.time+julia.alloc.bytes",
                "unit" => "$time_unit+$allocation_unit",
                "time_unit" => time_unit, "allocation_unit" => allocation_unit,
                "title" => "$package · $feature · time/allocation trade-off$suffix",
                "label" => "Time vs allocations$suffix"))
    end
    return entries
end

"""
    plot_catalog(bundle::RunBundle)

Return dictionaries describing plot IDs, kinds, titles and identifying metrics
available from the bundle's saved observations. Include supported normalized
benchmark metrics, version series/distributions/deltas, time/allocation
tradeoffs, allocation site/file/stack plots and CPU/wall profiles.
Entries are ordered by package/feature, preferring normalized metrics; their IDs
are content-derived identities accepted by [`performance_plot`](@ref).
Time/allocation tradeoffs pair metrics only within the same collector identity.
Comparisons with multiple collectors expose separate labeled entries; existing
IDs are retained when only one collector supplies a valid pair. A pair requires
one unambiguous series per metric, a supported time unit and allocation bytes
(`By`). Ambiguous or incompatible pairs are omitted without hiding independent
series and distributions. Tradeoff entries retain separate `time_unit` and
`allocation_unit` fields and both source series IDs; values are not converted.
A bundle without supported observations returns an empty list. No workload or
graphics backend is started; malformed evidence errors propagate.
"""
function plot_catalog(bundle::RunBundle)
    plots = vcat(
        _normalized_catalog(bundle), _series_catalog(bundle), _tradeoff_catalog(bundle),
        _allocation_catalog(bundle), _profile_catalog(bundle))
    sort!(plots;
        by = item -> (String(get(item, "package", "")),
            String(get(item, "feature", "")), item["kind"] == "normalized_metrics" ? 0 : 1,
            String(item["kind"]), String(item["id"])))
    return plots
end

function _catalog_entry(bundle::RunBundle, id::AbstractString)
    catalog = plot_catalog(bundle)
    entry = findfirst(item -> item["id"] == id, catalog)
    if entry === nothing
        startswith(id, "time-allocation-tradeoff-") && throw(ArgumentError(
            "Unknown or unavailable tradeoff $id: a tradeoff requires one unambiguous time series with a supported time unit and one allocation series in By for the same workload and collector"))
        throw(ArgumentError("unknown performance plot $id"))
    end
    return catalog[entry]
end

function _series_by_id(bundle::RunBundle, id::AbstractString)
    series = suite_version_series(bundle)
    index = findfirst(item -> item["series_id"] == id, series)
    index === nothing && throw(ArgumentError("unknown performance series $id"))
    return series[index]
end

function _series_observations(bundle::RunBundle, series)
    return [observation
            for observation in bundle.observations
            if
            get(observation, "comparison_key", "") == series["comparison_key"] &&
            get(observation, "metric", "") == series["metric"] &&
            get(observation, "measurement_definition", "") ==
            series["measurement_definition"] &&
            get(get(observation, "attributes", Dict()), "package", "") ==
            series["package"] &&
            get(get(observation, "attributes", Dict()), "feature", "") ==
            series["feature"]]
end

function _version_records(series)
    return [Dict{String, Any}(
                "version" => point["version"], "target_kind" => point["target_kind"],
                "value" => point["median"], "samples" => point["samples"],
                "aggregation" => get(point, "aggregation", "median"))
            for point in series["points"]]
end

function _distribution_records(bundle, series)
    return [Dict{String, Any}(
                "version" => get(observation, "target_id",
                    get(observation["attributes"], "version", "unknown")),
                "target_kind" => get(observation["attributes"], "target_kind", "release"),
                "value" => Float64(observation["value"]))
            for observation in _series_observations(bundle, series)
            if observation["value"] isa Number]
end

function _delta_records(bundle, series)
    comparison = compare_suite_versions(bundle)
    return [copy(record)
            for record in comparison.records
            if get(record, "series_id", "") == series["series_id"]]
end

function _allocation_records(bundle, case_id::String)
    return [observation
            for observation in _allocation_observations(bundle)
            if get(observation, "case_id", "") == case_id]
end

function _short_source_path(path::AbstractString)
    normalized = replace(normpath(String(path)), '\\' => '/')
    parts = split(normalized, '/')
    depot = findlast(==("packages"), parts)
    if depot !== nothing && depot + 3 <= length(parts) &&
       occursin(r"^[A-Za-z0-9]{5}$", parts[depot + 2])
        # Julia's package cache includes a content slug, not a meaningful source label.
        return join(vcat(parts[depot + 1], parts[(depot + 3):end]), '/')
    end
    return join(last(parts, min(length(parts), 3)), '/')
end

function _allocation_file_records(bundle, case_id)
    grouped = Dict{Tuple{String, String}, Float64}()
    for observation in _allocation_records(bundle, case_id)
        version = String(get(observation, "target_id", "unknown"))
        file = _short_source_path(String(observation["attributes"]["source_file"]))
        key = (version, file)
        grouped[key] = get(grouped, key, 0.0) + Float64(observation["value"])
    end
    versions = unique!(String[first(key) for key in keys(grouped)])
    sort!(versions;
        by = item -> _version_point_key(Dict("version" => item,
            "target_kind" => startswith(item, "dev@") ? "dev" : "release")))
    files = sort!(unique!(String[last(key) for key in keys(grouped)]))
    return [Dict{String, Any}("version" => version, "file" => file,
                "bytes" => get(grouped, (version, file), 0.0))
            for version in versions for file in files if haskey(grouped, (version, file))]
end

function _group_allocation_pie(records; min_percentage::Real = 5, top::Integer = 40)
    isfinite(min_percentage) && 0 <= min_percentage <= 100 ||
        throw(ArgumentError("min_percentage must be between 0 and 100"))
    records = sort(
        copy(records); by = item -> (-Float64(item["bytes"]), String(item["label"])))
    total = sum(item -> Float64(item["bytes"]), records; init = 0.0)
    limit = max(Int(top), 2)
    kept = filter(
        item -> total > 0 &&
            100 * Float64(item["bytes"]) / total >= min_percentage,
        records)
    # Reserve one legend entry for the combined remainder when necessary.
    count = length(kept)
    if count < length(records) || count > limit
        count = min(count, limit - 1)
    end
    selected_records = [copy(item) for item in first(kept, count)]
    remainder = records[(count + 1):end]
    if !isempty(remainder)
        push!(selected_records,
            Dict{String, Any}(
                "version" => get(first(remainder), "version", ""),
                "file" => "other", "line" => 0, "label" => "Other allocation sites",
                "bytes" => sum(item -> Float64(item["bytes"]), remainder; init = 0.0),
                "grouped_sites" => length(remainder)))
    end
    for item in selected_records
        item["percentage"] = total == 0 ? 0.0 : 100 * Float64(item["bytes"]) / total
    end
    return selected_records
end

function _allocation_pie_records(bundle, case_id; version = nothing, top::Integer = 40,
        min_percentage::Real = 5)
    records, versions, selected = _allocation_line_records(bundle, case_id;
        version, top = typemax(Int))
    selected_records = _group_allocation_pie(records; min_percentage, top)
    return selected_records, versions, selected
end

function _allocation_line_records(bundle, case_id; version = nothing, top::Integer = 40)
    grouped = Dict{Tuple{String, String, Int}, Float64}()
    for observation in _allocation_records(bundle, case_id)
        target = String(get(observation, "target_id", "unknown"))
        file = _short_source_path(String(observation["attributes"]["source_file"]))
        line = Int(get(observation["attributes"], "source_line", 0))
        key = (target, file, line)
        grouped[key] = get(grouped, key, 0.0) + Float64(observation["value"])
    end
    versions = unique!(String[first(key) for key in keys(grouped)])
    sort!(versions;
        by = _version_point_key ∘ (item -> Dict("version" => item,
            "target_kind" => startswith(item, "dev@") ? "dev" : "release")))
    selected = version === nothing ? (isempty(versions) ? "" : last(versions)) :
               String(version)
    records = [Dict{String, Any}("version" => target, "file" => file, "line" => line,
                   "label" => "$file:$line", "bytes" => bytes)
               for ((target, file, line), bytes) in grouped if target == selected]
    sort!(records; by = item -> (-Float64(item["bytes"]), String(item["label"])))
    resize!(records, min(length(records), max(Int(top), 1)))
    return records, versions, selected
end

"Aggregate observed allocation cells without inferring zero for an absent version/site pair."
function _allocation_heatmap_records(bundle, case_id; top::Integer = 40)
    grouped = Dict{Tuple{String, String}, Float64}()
    totals = Dict{String, Float64}()
    versions = String[]
    for observation in _allocation_records(bundle, case_id)
        version = String(get(observation, "target_id", "unknown"))
        file = _short_source_path(String(observation["attributes"]["source_file"]))
        line = Int(get(observation["attributes"], "source_line", 0))
        label = "$file:$line"
        grouped[(version, label)] = get(grouped, (version, label), 0.0) +
                                    Float64(observation["value"])
        totals[label] = get(totals, label, 0.0) + Float64(observation["value"])
        push!(versions, version)
    end
    unique!(versions)
    sort!(versions;
        by = item -> _version_point_key(Dict("version" => item,
            "target_kind" => startswith(item, "dev@") ? "dev" : "release")))
    labels = first.(first(sort!(collect(totals); by = item -> -last(item)),
        min(length(totals), max(Int(top), 1))))
    data = [Dict{String, Any}("version" => version, "label" => label,
                "bytes" => grouped[(version, label)])
            for label in labels
            for version in versions if haskey(grouped, (version, label))]
    return data, versions, labels
end

function _flame_records(observations; version = nothing, top::Integer = 40)
    versions = unique!(String[String(get(item, "target_id", "unknown"))
                              for item in observations])
    sort!(versions;
        by = item -> _version_point_key(Dict("version" => item,
            "target_kind" => startswith(item, "dev@") ? "dev" : "release")))
    selected = version === nothing ? (isempty(versions) ? "" : last(versions)) :
               String(version)
    grouped = Dict{Tuple{Vararg{String}}, Dict{String, Any}}()
    for observation in observations
        String(get(observation, "target_id", "unknown")) == selected || continue
        attributes = get(observation, "attributes", Dict())
        stack = get(attributes, "stack", nothing)
        stack isa AbstractVector || continue
        labels = Tuple(String.(stack))
        isempty(labels) && continue
        count = length(labels)
        function vector_attribute(name, fallback)
            values = get(attributes, name, nothing)
            values isa AbstractVector && length(values) == count ? collect(values) :
            fill(fallback, count)
        end
        runtime_dispatch = Bool.(vector_attribute("runtime_dispatch", false))
        gc_event = Bool.(vector_attribute("gc_event", false))
        inference_status = String.(vector_attribute("inference_status", "unknown"))
        inferred_return_type = String.(vector_attribute("inferred_return_type", ""))
        record = get!(grouped, labels) do
            Dict{String, Any}("value" => 0.0,
                "runtime_dispatch_value" => zeros(Float64, count),
                "gc_event_value" => zeros(Float64, count),
                "inference_status" => [Set{String}() for _ in 1:count],
                "inferred_return_type" => [Set{String}() for _ in 1:count])
        end
        value = Float64(observation["value"])
        record["value"] += value
        for index in eachindex(labels)
            runtime_dispatch[index] &&
                (record["runtime_dispatch_value"][index] += value)
            gc_event[index] && (record["gc_event_value"][index] += value)
            push!(record["inference_status"][index], inference_status[index])
            isempty(inferred_return_type[index]) ||
                push!(record["inferred_return_type"][index], inferred_return_type[index])
        end
    end
    stacks = sort!(collect(grouped); by = item -> -Float64(last(item)["value"]))
    resize!(stacks, min(length(stacks), max(Int(top), 1)))
    root = Dict{String, Any}("value" => 0.0,
        "children" => Dict{String, Any}())
    for (stack, stack_record) in stacks
        value = Float64(stack_record["value"])
        root["value"] += value
        node = root
        for (index, label) in pairs(stack)
            children = node["children"]
            child = get!(children, label) do
                Dict{String, Any}("value" => 0.0,
                    "runtime_dispatch_value" => 0.0, "gc_event_value" => 0.0,
                    "inference_status" => Set{String}(),
                    "inferred_return_type" => Set{String}(),
                    "children" => Dict{String, Any}())
            end
            child["value"] += value
            child["runtime_dispatch_value"] += stack_record["runtime_dispatch_value"][index]
            child["gc_event_value"] += stack_record["gc_event_value"][index]
            union!(child["inference_status"], stack_record["inference_status"][index])
            union!(child["inferred_return_type"],
                stack_record["inferred_return_type"][index])
            node = child
        end
    end
    total = Float64(root["value"])
    records = Dict{String, Any}[]
    function visit(children, depth, start, path)
        cursor = start
        ordered = sort!(collect(children); by = item -> -Float64(last(item)["value"]))
        for (label, child) in ordered
            width = total == 0 ? 0.0 : Float64(child["value"]) / total
            child_path = [path; String(label)]
            value = Float64(child["value"])
            runtime_dispatch_value = Float64(child["runtime_dispatch_value"])
            gc_event_value = Float64(child["gc_event_value"])
            inference_status = sort!(collect(child["inference_status"]))
            inferred_return_type = sort!(collect(child["inferred_return_type"]))
            inference_warning = any(status -> status in ("any", "union", "abstract"),
                inference_status)
            status = runtime_dispatch_value > 0 ? "runtime_dispatch" :
                     inference_warning ? "inference_warning" :
                     gc_event_value > 0 ? "gc_event" : "normal"
            push!(records,
                Dict{String, Any}(
                    "label" => String(label), "path" => child_path,
                    "depth" => depth, "x0" => cursor, "x1" => cursor + width,
                    "value" => value,
                    "percentage" => total == 0 ? 0.0 : 100 * value / total,
                    "status" => status,
                    "runtime_dispatch_value" => runtime_dispatch_value,
                    "runtime_dispatch_percentage" => value == 0 ? 0.0 :
                                                     100 * runtime_dispatch_value / value,
                    "gc_event_value" => gc_event_value,
                    "gc_event_percentage" => value == 0 ? 0.0 :
                                             100 * gc_event_value / value,
                    "inference_status" => inference_status,
                    "inferred_return_type" => inferred_return_type))
            visit(child["children"], depth + 1, cursor, child_path)
            cursor += width
        end
    end
    visit(root["children"], 1, 0.0, String[])
    return records, versions, selected, total
end

function _tradeoff_records(bundle, entry)
    series = suite_version_series(bundle)
    time = only(filter(item -> item["series_id"] == entry["time_series_id"], series))
    bytes = only(filter(item -> item["series_id"] == entry["allocation_series_id"], series))
    times = Dict(String(point["version"]) => point for point in time["points"])
    allocations = Dict(String(point["version"]) => point for point in bytes["points"])
    versions = sort!(collect(intersect(keys(times), keys(allocations)));
        by = item -> _version_point_key(times[item]))
    return [Dict{String, Any}("version" => version,
                "target_kind" => times[version]["target_kind"],
                "time" => times[version]["median"], "bytes" => allocations[version]["median"])
            for version in versions]
end

"""
    performance_plot(bundle, [id]; reference_version=nothing, version=nothing,
                     statistic=:minimum, top=40, min_percentage=5)

Build a backend-neutral plot. With no identifier, prefer overlaid BenchmarkTools
or Chairmarks metrics. By default, use each version's minimum sample, divided by
the minimum across the compared versions separately for each metric (best = 1).
Pass `statistic=:median` to compare medians instead.
Release targets use semantic version order; Git labels follow the series order.
Use `reference_version=:latest` or a version label to select a target instead
of the minimum. Raw measurements and
units remain in every record. Equal zeros appear at 1 (unchanged), by convention;
a nonzero value over a zero reference, or a missing reference, has no finite ratio.
Separate absolute plots remain available through `plot_catalog`.
Allocation pies combine sites contributing strictly less than `min_percentage`
percent of the selected version's allocated bytes into "Other allocation sites".
The default is 5%; exactly 5% remains separate. Set `min_percentage=0` to disable
this threshold. `top` still caps legend entries, including the combined remainder.
Allocation heatmaps retain only observed version/site pairs, including explicit
zero weights. Their complete axis labels remain in the options, with
`missing_cell_policy="not_observed"`; absent cells are not measured zeros.
Return a `PerformancePlot` from saved records without rerunning workloads.
Standard models retain their measurement definitions (or normalized collector)
and manifest tags in presentation options so renderers can label evidence
without inferring its collector from units.
Tradeoffs preserve raw recorded values and identify `time_unit`,
`allocation_unit`, `time_series_id` and `allocation_series_id` in their options,
with `unit_source="recorded_series"`. Only the compatible, unambiguous pairs
advertised by `plot_catalog` are available.
`version` selects allocation/profile versions; normalized metrics use
`reference_version` instead. Unknown plot IDs, absent plottable measurements,
unsupported statistics or invalid grouping limits raise `ArgumentError` in the
applicable plot builder. Use [`performance_plot_dict`](@ref) for transport or
[`performance_figure`](@ref) after loading PerfCheckerMakie to render the model.
"""
function performance_plot(bundle::RunBundle, id::AbstractString; version = nothing,
        reference_version = nothing, statistic::Symbol = :minimum,
        top::Integer = 40, min_percentage::Real = 5)
    entry = _catalog_entry(bundle, id)
    kind = Symbol(entry["kind"])
    data = Dict{String, Any}[]
    encoding = Dict{String, Any}()
    options = Dict{String, Any}("package" => get(entry, "package", ""),
        "feature" => get(entry, "feature", ""), "unit" => get(entry, "unit", ""))
    description = String(entry["label"])
    if kind === :normalized_metrics
        return _normalized_plot(bundle, entry; reference_version, statistic)
    elseif kind in (:version_series, :distribution, :version_delta)
        series = _series_by_id(bundle, entry["series_id"])
        options["series_id"] = series["series_id"]
        options["metric"] = series["metric"]
        data = kind === :version_series ? _version_records(series) :
               kind === :distribution ? _distribution_records(bundle, series) :
               _delta_records(bundle, series)
        encoding = kind === :version_delta ?
                   Dict(
            "x" => "candidate_version", "y" => "relative_delta", "color" => "status") :
                   Dict("x" => "version", "y" => "value", "color" => "target_kind")
    elseif kind === :allocation_pie
        data, versions, selected = _allocation_pie_records(bundle, entry["case_id"];
            version, top, min_percentage)
        options["versions"] = versions
        options["selected_version"] = selected
        options["top"] = Int(top)
        options["min_percentage"] = Float64(min_percentage)
        encoding = Dict("theta" => "bytes", "color" => "label", "label" => "percentage")
    elseif kind === :allocation_files
        data = _allocation_file_records(bundle, entry["case_id"])
        encoding = Dict("x" => "version", "y" => "bytes", "color" => "file")
    elseif kind === :allocation_lines
        data, versions, selected = _allocation_line_records(bundle, entry["case_id"];
            version, top)
        options["versions"] = versions
        options["selected_version"] = selected
        options["top"] = Int(top)
        encoding = Dict("x" => "label", "y" => "bytes", "color" => "file")
    elseif kind === :allocation_heatmap
        data, versions, labels = _allocation_heatmap_records(bundle, entry["case_id"]; top)
        options["versions"] = versions
        options["labels"] = labels
        options["top"] = Int(top)
        options["missing_cell_policy"] = "not_observed"
        encoding = Dict("x" => "version", "y" => "label", "color" => "bytes")
    elseif kind === :allocation_flamegraph
        observations = _allocation_records(bundle, entry["case_id"])
        data, versions, selected, total = _flame_records(observations; version, top)
        options["versions"] = versions
        options["selected_version"] = selected
        options["top"] = Int(top)
        options["total"] = total
        options["value_label"] = "allocated bytes"
        encoding = Dict("x" => "percentage", "y" => "depth", "color" => "status")
    elseif kind === :cpu_flamegraph
        observations = [observation
                        for observation in bundle.observations
                        if get(observation, "case_id", "") == entry["case_id"] &&
                           get(observation, "measurement_definition", "") ==
                           entry["definition"]]
        data, versions, selected, total = _flame_records(observations; version, top)
        options["versions"] = versions
        options["selected_version"] = selected
        options["top"] = Int(top)
        options["total"] = total
        options["value_label"] = "CPU samples"
        options["diagnostic_semantics"] = "runtime dispatch and cached Julia inference metadata"
        encoding = Dict("x" => "percentage", "y" => "depth", "color" => "status")
    elseif kind === :wall_flamegraph
        observations = [observation
                        for observation in bundle.observations
                        if get(observation, "case_id", "") == entry["case_id"] &&
                           get(observation, "measurement_definition", "") ==
                           entry["definition"]]
        data, versions, selected, total = _flame_records(observations; version, top)
        options["versions"] = versions
        options["selected_version"] = selected
        options["top"] = Int(top)
        options["total"] = total
        options["value_label"] = "wall-time task samples"
        options["diagnostic_semantics"] = "runtime dispatch and cached Julia inference metadata"
        encoding = Dict("x" => "percentage", "y" => "depth", "color" => "status")
    elseif kind === :time_allocation_tradeoff
        data = _tradeoff_records(bundle, entry)
        for key in (
            "time_unit", "allocation_unit", "time_series_id", "allocation_series_id")
            options[key] = entry[key]
        end
        options["unit_source"] = "recorded_series"
        encoding = Dict("x" => "bytes", "y" => "time", "label" => "version")
    else
        throw(ArgumentError("unsupported performance plot kind $kind"))
    end
    # Presentation retains the collector's existing identity; units alone cannot
    # distinguish collectors. These fields do not change observations or IDs.
    definitions = if haskey(entry, "series_id")
        [series["measurement_definition"]]
    elseif haskey(entry, "definition")
        [entry["definition"]]
    elseif startswith(string(kind), "allocation_")
        unique([observation["measurement_definition"]
                for observation in _allocation_observations(bundle)
                if get(observation, "case_id", "") == entry["case_id"]])
    elseif kind === :time_allocation_tradeoff
        unique([item["measurement_definition"]
                for item in suite_version_series(bundle)
                if item["package"] == entry["package"] &&
                       item["feature"] == entry["feature"] &&
                       item["series_id"] in (
                           entry["time_series_id"], entry["allocation_series_id"])])
    else
        String[]
    end
    options["measurement_definitions"] = definitions
    options["tags"] = get(bundle.manifest, "tags", String[])
    return PerformancePlot(String(entry["id"]), kind, String(entry["title"]),
        description, encoding, data, options)
end

function performance_plot(bundle::RunBundle; kwargs...)
    catalog = plot_catalog(bundle)
    isempty(catalog) && throw(ArgumentError("run bundle has no plottable measurements"))
    preferred = findfirst(item -> item["kind"] == "normalized_metrics", catalog)
    return performance_plot(
        bundle, catalog[isnothing(preferred) ? 1 : preferred]["id"]; kwargs...)
end

"""
    performance_figure(plot::PerformancePlot)
    performance_figure(bundle::RunBundle, [id]; kwargs...)

Load `PerfCheckerMakie` and a Makie backend to render a saved-evidence plot as a
Makie figure. Bundle overloads first call [`performance_plot`](@ref), forwarding
its selection/grouping keywords. The companion accepts separate `figure_kwargs`,
`axis_kwargs` and `plot_kwargs` attribute bundles plus presentation `tags`.
Unsupported plot kinds raise `ArgumentError`.
No workload is rerun, and rendering does not save an image; use the active
backend's save API for an explicit export. Without the companion's methods,
calling this generic function raises `MethodError`.
"""
function performance_figure end

"""
    performance_plot_html(plot::PerformancePlot)

Load `PerfCheckerMakie` and `WGLMakie` to render the plot as an embeddable
interactive HTML string. The companion's WGLMakie extension supplies the method;
without it, this generic raises `MethodError`. Rendering consumes saved data
and does not start a measurement or write/deploy an HTML page. The caller owns
embedding and any file export.
"""
function performance_plot_html end

@testitem "Performance plot grammar" tags=[:unit, :plots] begin
    using PerfChecker

    definitions = [Dict{String, Any}("id" => "julia.wall.time/benchmarktools-v1",
        "metric" => "julia.wall.time", "unit" => "s")]
    observations = [Dict{String, Any}(
                        "case_id" => "demo/Demo/parse", "target_id" => version,
                        "comparison_key" => "parse/v1::julia.wall.time/benchmarktools-v1",
                        "metric" => "julia.wall.time", "measurement_definition" => "julia.wall.time/benchmarktools-v1",
                        "value" => value, "unit" => "s",
                        "attributes" => Dict("package" => "Demo", "feature" => "parse",
                            "version" => version, "target_kind" => kind))
                    for (version, kind, value) in (("1.0.0", "release", 1.0),
        ("1.1.0", "release", 0.8),
        ("dev@1.2.0", "dev", 0.7))]
    bundle = RunBundle(
        Dict{String, Any}("run_id" => "plot-run", "suite" => "demo",
            "state" => "complete"),
        definitions, observations,
        Dict{String, Any}[], Dict{String, Any}[])
    catalog = plot_catalog(bundle)
    @test length(catalog) == 3
    trajectory = only(filter(item -> item["kind"] == "version_series", catalog))
    plot = performance_plot(bundle, trajectory["id"])
    @test performance_plot_dict(plot)["schema_version"] == "perfchecker-plot/1"
    @test length(plot.data) == 3
end

@testitem "Tradeoffs retain recorded dimensions without hiding valid series" tags=[
    :unit, :plots] begin
    using PerfChecker
    function records(time_unit, allocation_unit = "By")
        observations = Dict{String, Any}[]
        for (metric, unit, value) in (("julia.wall.time", time_unit, 400.0),
                ("julia.alloc.bytes", allocation_unit, 2048.0)),
            (version, scale) in (("1.0.0", 1), ("1.1.0", 2))

            push!(observations,
                Dict{String, Any}("metric" => metric,
                    "measurement_definition" => "$metric/benchmarktools-v1",
                    "comparison_key" => "parse/v1::$metric/benchmarktools-v1",
                    "unit" => unit, "value" => value * scale,
                    "attributes" => Dict("package" => "Demo", "feature" => "parse",
                        "workload" => "parse", "version" => version, "target_kind" => "release")))
        end
        return observations
    end
    bundle(observations) = RunBundle(Dict{String, Any}("run_id" => "tradeoff-units"),
        Dict{String, Any}[], observations, Dict{String, Any}[], Dict{String, Any}[])
    for unit in ("ns", "s")
        observations = records(unit)
        before = deepcopy(observations)
        source = bundle(observations)
        entry = only(filter(
            item -> item["kind"] == "time_allocation_tradeoff", plot_catalog(source)))
        model = performance_plot(source, entry["id"])
        @test entry["unit"] == "$unit+By"
        @test model.options["time_unit"] == unit
        @test model.options["allocation_unit"] == "By"
        @test model.options["unit_source"] == "recorded_series"
        @test model.options["time_series_id"] == entry["time_series_id"]
        @test model.options["allocation_series_id"] == entry["allocation_series_id"]
        @test [point["time"] for point in model.data] == [400.0, 800.0]
        @test observations == before
    end
    mixed = [records("ns");
             filter(item -> item["metric"] == "julia.wall.time", records("s"))]
    incompatible_collector = records("By")
    for item in incompatible_collector, key in ("measurement_definition", "comparison_key")
        item[key] = replace(item[key], "benchmarktools-v1" => "chairmarks-v1")
    end
    valid_entry = only(PerfChecker._tradeoff_catalog(bundle(records("ns"))))
    with_invalid = only(PerfChecker._tradeoff_catalog(bundle([records("ns");
                                                              incompatible_collector])))
    @test with_invalid["id"] == valid_entry["id"]
    @test with_invalid["collector"] == valid_entry["collector"]
    for observations in (
        mixed, records("By"), records("ns", "s"), records("ns", "kB"), records(""))
        source = bundle(observations)
        catalog = plot_catalog(source)
        @test !any(item -> item["kind"] == "time_allocation_tradeoff", catalog)
        series = first(filter(item -> item["kind"] == "version_series", catalog))
        distribution = first(filter(item -> item["kind"] == "distribution", catalog))
        @test !isempty(performance_plot(source, series["id"]).data)
        @test !isempty(performance_plot(source, distribution["id"]).data)
        @test_throws ArgumentError performance_plot(source,
            PerfChecker._plot_id(:time_allocation_tradeoff, "Demo", "parse", "parse/v1"))
    end
    @test PerfChecker._tradeoff_plot_units(Dict("unit" => "s+By")) ==
          ("unit unspecified", "unit unspecified")
    @test_throws ArgumentError PerfChecker._tradeoff_plot_units(
        Dict("time_unit" => "By", "allocation_unit" => "s"))
end

@testitem "Tradeoffs preserve distinct collectors and legacy identities" tags=[
    :unit, :plots] begin
    using PerfChecker
    observations = Dict{String, Any}[]
    for (collector, scale) in (("benchmarktools-v1", 1), ("chairmarks-v1", 10)),
        (metric, unit, value) in (("julia.wall.time", "s", 1.0),
            ("julia.alloc.bytes", "By", 100.0)),
        (version, factor) in (("1.0.0", 1), ("1.1.0", 2))

        push!(observations,
            Dict{String, Any}(
                "case_id" => "Demo/parse/$collector", "target_id" => version,
                "comparison_key" => "parse/v1::$metric/$collector",
                "metric" => metric, "measurement_definition" => "$metric/$collector",
                "value" => value * scale * factor, "unit" => unit,
                "attributes" => Dict("package" => "Demo", "feature" => "parse",
                    "workload" => "parse", "version" => version, "target_kind" => "release")))
    end
    bundle(records) = RunBundle(Dict{String, Any}("run_id" => "tradeoff"),
        Dict{String, Any}[], records, Dict{String, Any}[], Dict{String, Any}[])
    source = bundle(observations)
    evidence = deepcopy(observations)
    entries = filter(
        item -> item["kind"] == "time_allocation_tradeoff", plot_catalog(source))
    @test length(entries) == 2
    @test [entry["collector"] for entry in entries] ==
          ["benchmarktools-v1", "chairmarks-v1"]
    @test length(unique(entry["id"] for entry in entries)) == 2
    @test plot_catalog(source) == plot_catalog(bundle(reverse(observations)))
    for (entry, scale) in zip(entries, (1, 10))
        collector = entry["collector"]
        @test occursin(collector, entry["label"])
        model = performance_plot(source, entry["id"])
        @test [point["version"] for point in model.data] == ["1.0.0", "1.1.0"]
        @test [point["time"] for point in model.data] == scale .* [1.0, 2.0]
        @test [point["bytes"] for point in model.data] == scale .* [100.0, 200.0]
        @test Set(model.options["measurement_definitions"]) ==
              Set(["julia.wall.time/$collector", "julia.alloc.bytes/$collector"])
        single = bundle(filter(
            item -> endswith(item["measurement_definition"], collector), observations))
        legacy = only(filter(
            item -> item["kind"] == "time_allocation_tradeoff", plot_catalog(single)))
        @test legacy["id"] ==
              PerfChecker._plot_id(:time_allocation_tradeoff, "Demo", "parse", "parse/v1")
        @test performance_plot(single, legacy["id"]).data == model.data
    end
    @test observations == evidence
    # VersionComparison exports supply series directly, without a RunBundle
    # manifest. Preserve this public writer and avoid fabricating absent tags.
    comparison = compare_suite_versions(source)
    mktempdir() do directory
        file = write_version_series_json(comparison, joinpath(directory, "series.json"))
        exported = PerfChecker.JSON.parse(read(file, String))
        @test length(exported["plots"]) == 2
        @test all(plot -> isempty(plot["options"]["tags"]), exported["plots"])
        @test Set(plot["options"]["collector"] for plot in exported["plots"]) ==
              Set(["benchmarktools-v1", "chairmarks-v1"])
        @test length(exported["series"]) == 4
    end
end

@testitem "Allocation plot grammar" tags=[:unit, :plots, :allocations] begin
    using PerfChecker

    definition = Dict{String, Any}(
        "id" => "julia.alloc.bytes/line-tracking-v1",
        "metric" => "julia.alloc.bytes", "unit" => "By")
    observations = Dict{String, Any}[]
    for (version, kind) in (("1.0.0", "release"), ("dev@1.1.0", "dev"))
        for (file, line, bytes) in (("src/parse.jl", 10, 100.0),
            ("src/parse.jl", 20, 40.0),
            ("src/model.jl", 8, 20.0))
            push!(observations,
                Dict{String, Any}(
                    "case_id" => "demo/Demo/parse_allocations", "target_id" => version,
                    "comparison_key" => "parse/v1::julia.alloc.bytes/line-tracking-v1",
                    "metric" => "julia.alloc.bytes", "measurement_definition" => "julia.alloc.bytes/line-tracking-v1",
                    "value" => bytes,
                    "unit" => "By", "attributes" => Dict{String, Any}(
                        "package" => "Demo", "feature" => "parse_allocations",
                        "version" => version, "target_kind" => kind,
                        "source_file" => file, "source_line" => line,
                        "stack" => ["parse (src/parse.jl:1)", "$file:$line"])))
        end
    end
    bundle = RunBundle(
        Dict{String, Any}("run_id" => "allocation-plot-run",
            "suite" => "demo", "state" => "complete"),
        [definition],
        observations,
        Dict{String, Any}[], Dict{String, Any}[])
    catalog = plot_catalog(bundle)
    allocation = filter(item -> startswith(item["kind"], "allocation_"), catalog)
    @test Set(item["kind"] for item in allocation) == Set(("allocation_pie",
        "allocation_files", "allocation_lines", "allocation_heatmap",
        "allocation_flamegraph"))
    plots = Dict(item["kind"] => performance_plot(bundle, item["id"])
    for item in allocation)
    @test length(plots["allocation_files"].data) == 4
    @test sum(item["percentage"] for item in plots["allocation_pie"].data) ≈ 100
    @test plots["allocation_lines"].options["selected_version"] == "dev@1.1.0"
    @test length(plots["allocation_lines"].data) == 3
    @test plots["allocation_heatmap"].options["versions"] ==
          ["1.0.0", "dev@1.1.0"]
    @test !isempty(plots["allocation_flamegraph"].data)
    series = only(filter(item -> item["kind"] == "version_series", catalog))
    @test performance_plot(bundle, series["id"]).data[1]["value"] == 160.0
end

@testitem "Allocation heatmaps distinguish absent cells from explicit zero observations" tags=[
    :unit, :plots, :allocations] begin
    using PerfChecker
    definition = Dict{String, Any}("id" => "julia.alloc.bytes/profile-allocs-v1",
        "metric" => "julia.alloc.bytes", "unit" => "By")
    observations = [Dict{String, Any}(
                        "case_id" => "demo/Demo/allocations", "target_id" => version,
                        "comparison_key" => "allocations/v1", "metric" => "julia.alloc.bytes",
                        "measurement_definition" => definition["id"], "value" => bytes, "unit" => "By",
                        "attributes" => Dict(
                            "package" => "Demo", "feature" => "allocations",
                            "version" => version, "target_kind" => "release",
                            "source_file" => file, "source_line" => 10))
                    for (version, file, bytes) in (("1.0.0", "src/a.jl", 100.0),
        ("1.0.0", "src/a.jl", 20.0), ("1.1.0", "src/b.jl", 0.0))]
    bundle = RunBundle(
        Dict{String, Any}("run_id" => "sparse-allocation-heatmap",
            "suite" => "demo", "state" => "complete"),
        [definition],
        observations,
        Dict{String, Any}[], Dict{String, Any}[])
    before = deepcopy(bundle.observations)
    entry = only(filter(item -> item["kind"] == "allocation_heatmap", plot_catalog(bundle)))
    model = performance_plot(bundle, entry["id"])
    @test model.options["missing_cell_policy"] == "not_observed"
    @test model.options["versions"] == ["1.0.0", "1.1.0"]
    @test Set(model.options["labels"]) == Set(["src/a.jl:10", "src/b.jl:10"])
    cells = Dict((row["version"], row["label"]) => row["bytes"] for row in model.data)
    @test length(cells) == length(model.data) == 2
    @test cells[("1.0.0", "src/a.jl:10")] == 120.0
    @test cells[("1.1.0", "src/b.jl:10")] == 0.0
    @test !haskey(cells, ("1.0.0", "src/b.jl:10"))
    @test !haskey(cells, ("1.1.0", "src/a.jl:10"))
    @test bundle.observations == before
end

@testitem "CPU flame graph grammar" tags=[:unit, :plots, :profile, :flamegraph] begin
    using PerfChecker

    definition = Dict{String, Any}("id" => "julia.cpu.samples/profile-v1",
        "metric" => "julia.cpu.samples", "unit" => "1")
    observations = [Dict{String, Any}(
                        "case_id" => "demo/Demo/parse_profile", "target_id" => "dev@1.1.0",
                        "comparison_key" => "parse/v1::julia.cpu.samples/profile-v1",
                        "metric" => "julia.cpu.samples", "measurement_definition" => "julia.cpu.samples/profile-v1",
                        "value" => samples, "unit" => "1",
                        "attributes" => Dict{String, Any}(
                            "package" => "Demo", "feature" => "parse_profile",
                            "version" => "dev@1.1.0", "target_kind" => "dev",
                            "source_file" => "src/parse.jl", "source_line" => 10,
                            "stack" => stack, "runtime_dispatch" => dispatch,
                            "gc_event" => gc, "inference_status" => inference,
                            "inferred_return_type" => return_types))
                    for (samples, stack, dispatch, gc, inference, return_types) in (
        (8, ["parse", "tokenize"], [false, true], [false, false],
            ["concrete", "union"], ["Nothing", "Union{String, Nothing}"]),
        (2, ["parse", "normalize"], [false, false], [false, false],
            ["concrete", "abstract"], ["Nothing", "AbstractString"]),
        (1, ["parse", "cleanup"], [false, false], [false, true],
            ["concrete", "concrete"], ["Nothing", "Nothing"]))]
    bundle = RunBundle(
        Dict{String, Any}("run_id" => "profile-plot-run",
            "suite" => "demo", "state" => "complete"),
        [definition],
        observations,
        Dict{String, Any}[], Dict{String, Any}[])
    entry = only(filter(item -> item["kind"] == "cpu_flamegraph",
        plot_catalog(bundle)))
    plot = performance_plot(bundle, entry["id"])
    @test plot.options["total"] == 11
    @test plot.options["selected_version"] == "dev@1.1.0"
    root = only(filter(item -> item["depth"] == 1, plot.data))
    @test root["label"] == "parse"
    @test root["percentage"] == 100
    tokenize = only(filter(item -> item["label"] == "tokenize", plot.data))
    @test tokenize["status"] == "runtime_dispatch"
    @test tokenize["runtime_dispatch_value"] == 8
    @test tokenize["runtime_dispatch_percentage"] == 100
    @test tokenize["inference_status"] == ["union"]
    @test tokenize["inferred_return_type"] == ["Union{String, Nothing}"]
    normalize = only(filter(item -> item["label"] == "normalize", plot.data))
    @test normalize["status"] == "inference_warning"
    cleanup = only(filter(item -> item["label"] == "cleanup", plot.data))
    @test cleanup["status"] == "gc_event"
end
