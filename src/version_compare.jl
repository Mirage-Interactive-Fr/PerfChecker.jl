"A release-by-release comparison and its plottable version series."
struct VersionComparison
    run_id::String
    input_passed::Bool
    warnings::Vector{String}
    availability::Vector{Dict{String, Any}}
    series::Vector{Dict{String, Any}}
    records::Vector{Dict{String, Any}}
end

function _version_point_key(point::AbstractDict)
    kind = String(get(point, "target_kind", "release"))
    label = String(get(point, "version", ""))
    version = try
        VersionNumber(label)
    catch
        v"0.0.0"
    end
    # Git targets may use version labels too; 0.2.10 follows 0.2.9.
    # Arbitrary branch/commit labels retain their deterministic lexical order.
    return (kind == "release" ? 0 : 1, version, label)
end

function _series_identifier(parts)
    return _content_digest(parts)[1:16]
end

"Aggregate raw observations into plottable statistics for every package feature/version."
function suite_version_series(bundle::RunBundle)
    groups = Dict{NTuple{9, String}, Vector{Float64}}()
    for observation in bundle.observations
        attributes = get(observation, "attributes", nothing)
        attributes isa AbstractDict || continue
        all(haskey(attributes, key)
        for key in ("package", "feature", "version", "target_kind")) || continue
        value = get(observation, "value", nothing)
        value isa Number || continue
        numeric = Float64(value)
        isfinite(numeric) || continue
        definition = String(get(observation, "measurement_definition", "unknown"))
        definition == "julia.alloc.fraction/line-tracking-v1" && continue
        definition in ("julia.cpu.samples/profile-v1",
            "julia.wall.samples/profile-walltime-v1") && continue
        key = (
            String(attributes["package"]),
            String(attributes["feature"]),
            String(get(attributes, "workload", attributes["feature"])),
            String(get(observation, "comparison_key", "")),
            String(get(observation, "metric", "unknown")),
            definition,
            String(get(observation, "unit", "unknown")),
            String(attributes["version"]),
            String(attributes["target_kind"])
        )
        push!(get!(groups, key, Float64[]), numeric)
    end

    series_groups = Dict{NTuple{7, String}, Vector{Dict{String, Any}}}()
    for (key, values) in groups
        package, feature, workload, comparison_key, metric, definition, unit, version, kind = key
        allocation_sites = definition in (
            "julia.alloc.bytes/line-tracking-v1", "julia.alloc.bytes/profile-allocs-v1",
            "julia.alloc.count/profile-allocs-v1", "julia.cpu.samples/profile-v1",
            "julia.wall.samples/profile-walltime-v1")
        aggregation = allocation_sites ? "sum" : "median"
        aggregate = aggregation == "sum" ? sum(values) : _median(values)
        statistics = aggregation == "sum" ? Dict{String, Any}("median" => aggregate) :
                     _sample_statistics_dict(values)
        point = Dict{String, Any}(
            "version" => version,
            "target_kind" => kind,
            "median" => aggregate,
            "statistics" => statistics,
            "samples" => length(values),
            "aggregation" => aggregation
        )
        series_key = (package, feature, workload, comparison_key, metric, definition, unit)
        push!(get!(series_groups, series_key, Dict{String, Any}[]), point)
    end

    result = Dict{String, Any}[]
    for (key, points) in series_groups
        package, feature, workload, comparison_key, metric, definition, unit = key
        sort!(points; by = _version_point_key)
        push!(result,
            Dict{String, Any}(
                "series_id" => _series_identifier(key),
                "package" => package,
                "feature" => feature,
                "workload" => workload,
                "comparison_key" => comparison_key,
                "metric" => metric,
                "measurement_definition" => definition,
                "unit" => unit,
                "points" => points
            ))
    end
    sort!(result;
        by = series -> (
            series["package"], series["feature"], series["metric"],
            series["measurement_definition"]))
    return result
end

function _version_pairs(points)
    releases = [point for point in points if point["target_kind"] == "release"]
    development = [point for point in points if point["target_kind"] != "release"]
    pairs = Tuple{Any, Any, String}[]
    for index in 2:length(releases)
        push!(pairs, (releases[index - 1], releases[index], "adjacent-release"))
    end
    if !isempty(releases)
        for point in development
            push!(pairs, (last(releases), point, "dev-vs-latest-release"))
        end
    elseif length(development) > 1
        for point in development[2:end]
            push!(pairs, (first(development), point, "candidate-vs-reference"))
        end
    end
    return pairs
end

function _availability_records(bundle::RunBundle)
    plan = get(bundle.manifest, "plan", nothing)
    plan isa AbstractDict || return Dict{String, Any}[]
    planned = get(plan, "runs", nothing)
    planned isa AbstractVector || return Dict{String, Any}[]
    observed = Set((String(get(item, "case_id", "")),
                       String(get(item, "target_id", ""))) for item in bundle.observations)
    diagnostics = Dict(
        (String(get(item, "case_id", "")), String(get(item, "target_id", ""))) => item
    for item in bundle.diagnostics)
    suite = String(get(bundle.manifest, "suite", "suite"))
    records = Dict{String, Any}[]
    for run in planned
        package_id = String(get(run, "package_id", get(run, "package", "package")))
        feature = String(get(run, "feature", "feature"))
        case_id = "$suite/$package_id/$feature"
        target_id = String(get(run, "version", ""))
        diagnostic = get(diagnostics, (case_id, target_id), nothing)
        status, reason = if diagnostic !== nothing
            (String(get(get(diagnostic, "evidence", Dict()), "status", "failed")),
                String(get(diagnostic, "message", "")))
        elseif (case_id, target_id) in observed
            ("observed", "")
        elseif String(get(run, "status", "ready")) == "unavailable"
            ("unavailable", String(get(run, "reason", "")))
        else
            ("missing", "planned target produced no observation")
        end
        push!(records,
            Dict{String, Any}(
                "run_id" => String(get(run, "id", "")), "case_id" => case_id,
                "package" => String(get(run, "package", package_id)),
                "package_id" => package_id, "feature" => feature,
                "workload" => String(get(run, "workload", feature)),
                "version" => target_id,
                "target_kind" => String(get(run, "target_kind", "release")),
                "comparison_key" => String(get(run, "comparison_key", "")),
                "status" => status, "reason" => reason))
    end
    sort!(
        records; by = item -> (item["package"], item["feature"],
            _version_point_key(item)))
    return records
end

function _expected_points(series, availability)
    definition_suffix = "::$(series["measurement_definition"])"
    base_key = endswith(String(series["comparison_key"]), definition_suffix) ?
               chop(String(series["comparison_key"]); tail = length(definition_suffix)) :
               String(series["comparison_key"])
    matching = [Dict{String, Any}(
                    "version" => item["version"],
                    "target_kind" => item["target_kind"],
                    "availability" => item["status"],
                    "reason" => item["reason"])
                for item in availability
                if item["package"] == series["package"] &&
                   item["feature"] == series["feature"] &&
                   item["comparison_key"] == base_key]
    unique!(item -> (item["version"], item["target_kind"]), matching)
    sort!(matching; by = _version_point_key)
    return matching
end

function _bundle_comparison_policies(bundle::RunBundle)
    plan = get(bundle.manifest, "plan", nothing)
    plan isa AbstractDict || return AbstractDict[]
    policies = get(plan, "comparisons", nothing)
    policies isa AbstractVector || return AbstractDict[]
    return AbstractDict[item for item in policies if item isa AbstractDict]
end

function _series_base_comparison_key(series)
    suffix = "::$(series["measurement_definition"])"
    key = String(series["comparison_key"])
    return endswith(key, suffix) ? chop(key; tail = length(suffix)) : key
end

function _matching_policy(series, policies)
    base_key = _series_base_comparison_key(series)
    return findfirst(policies) do policy
        package = String(get(policy, "package", ""))
        feature = String(get(policy, "feature", ""))
        comparison_key = String(get(policy, "comparison_key", ""))
        selector_matches = !isempty(comparison_key) ? comparison_key == base_key :
                           isempty(feature) || feature == series["feature"] ||
                           feature == get(series, "workload", series["feature"])
        (isempty(package) || package == series["package"]) && selector_matches
    end
end

function _version_point_value(point, statistic)
    normalized = _normalize_sample_statistic(statistic)
    statistics = get(point, "statistics", nothing)
    if statistics isa AbstractDict && haskey(statistics, string(normalized))
        return Float64(statistics[string(normalized)])
    end
    normalized === :median && haskey(point, "median") &&
        return Float64(point["median"])
    return nothing
end

function _aggregate_values(values::Vector{Float64}, aggregation)
    normalized = Symbol(aggregation)
    normalized === :mean && return sum(values) / length(values)
    normalized === :minimum && return minimum(values)
    normalized === :maximum && return maximum(values)
    return _median(values)
end

function _aggregate_reference(points, policy, statistic = :median)
    labels = String.(get(policy, "baselines", String[]))
    missing = [label
               for label in labels
               if !haskey(points, label) ||
                  _version_point_value(points[label], statistic) === nothing]
    label = length(labels) == 1 ? only(labels) :
            "$(get(policy, "id", "reference"))[$(join(labels, ", "))]"
    if !isempty(missing)
        return Dict{String, Any}("version" => label, "target_kind" => "reference",
            "availability" => "missing",
            "reason" => "reference targets are missing: $(join(missing, ", "))")
    end
    selected = [points[item] for item in labels]
    aggregation = Symbol(get(policy, "aggregation", "median"))
    values = Float64[_version_point_value(item, statistic) for item in selected]
    value = _aggregate_values(values, aggregation)
    median_values = Float64[item["median"] for item in selected]
    median = _aggregate_values(median_values, aggregation)
    return Dict{String, Any}("version" => label, "target_kind" => "reference",
        "median" => median,
        "statistics" => Dict(string(_normalize_sample_statistic(statistic)) => value,
            "median" => median),
        "samples" => sum(Int(get(item, "samples", 0))
        for item in selected),
        "aggregation" => string(aggregation), "reference_versions" => labels)
end

function _comparison_pairs(series, availability, policies = AbstractDict[],
        statistic = :median)
    expected = _expected_points(series, availability)
    # A feature explicitly unavailable on an older package or Julia runtime is
    # outside the comparison domain. Keep genuine failed/missing targets so
    # incomplete measurements remain visible and blocking.
    filter!(point -> get(point, "availability", "") != "unavailable", expected)
    isempty(expected) && isempty(policies) && return _version_pairs(series["points"])
    observed = Dict(String(point["version"]) => point for point in series["points"])
    policy_index = _matching_policy(series, policies)
    if policy_index !== nothing
        policy = policies[policy_index]
        expected_index = Dict(String(point["version"]) => point for point in expected)
        points = merge(expected_index, observed)
        baseline = _aggregate_reference(points, policy, statistic)
        relation = length(get(policy, "baselines", [])) == 1 ?
                   "candidate-vs-exact-reference" : "candidate-vs-reference-group"
        return [(baseline,
                    get(points,
                        String(candidate),
                        Dict{String, Any}(
                            "version" => String(candidate), "target_kind" => "candidate",
                            "availability" => "missing", "reason" => "candidate target was not planned")),
                    relation)
                for candidate in get(policy, "candidates", String[])]
    end
    return [(get(observed, String(baseline["version"]), baseline),
                get(observed, String(candidate["version"]), candidate), relation)
            for (baseline, candidate, relation) in _version_pairs(expected)]
end

function _version_comparison_record(series, baseline, candidate, relation,
        definition, relative_limits, min_samples, statistic = :median)
    metric = String(series["metric"])
    normalized_statistic = _normalize_sample_statistic(statistic)
    baseline_median = Float64(baseline["median"])
    candidate_median = Float64(candidate["median"])
    baseline_value = _version_point_value(baseline, normalized_statistic)
    candidate_value = _version_point_value(candidate, normalized_statistic)
    absolute_delta = candidate_value - baseline_value
    relative_delta = iszero(baseline_value) ? nothing :
                     absolute_delta / abs(baseline_value)
    limit = _limit_for(relative_limits, metric)
    record = Dict{String, Any}(
        "series_id" => series["series_id"],
        "package" => series["package"],
        "feature" => series["feature"],
        "workload" => get(series, "workload", series["feature"]),
        "comparison_key" => series["comparison_key"],
        "metric" => metric,
        "measurement_definition" => series["measurement_definition"],
        "unit" => series["unit"],
        "relation" => relation,
        "baseline_version" => baseline["version"],
        "candidate_version" => candidate["version"],
        "baseline_samples" => baseline["samples"],
        "candidate_samples" => candidate["samples"],
        "baseline_median" => baseline_median,
        "candidate_median" => candidate_median,
        "sample_statistic" => string(normalized_statistic),
        "sample_statistic_definition" => _sample_statistic_definition(normalized_statistic),
        "baseline_value" => baseline_value,
        "candidate_value" => candidate_value,
        "absolute_delta" => absolute_delta,
        "relative_delta" => relative_delta,
        "relative_limit" => limit
    )
    haskey(baseline, "reference_versions") &&
        (record["baseline_versions"] = baseline["reference_versions"])
    if baseline["samples"] < min_samples || candidate["samples"] < min_samples
        record["status"] = "insufficient_samples"
        record["reason"] = "minimum sample count is $min_samples"
    elseif limit === nothing
        record["status"] = "diagnostic"
        record["reason"] = "no CI policy configured for this metric"
    elseif relative_delta === nothing
        preference = String(get(definition, "preference", "lower"))
        regression = preference == "higher" ? candidate_value < baseline_value :
                     candidate_value > baseline_value
        record["status"] = regression ? "regression" : "pass"
        record["reason"] = regression ?
                           "candidate moved against policy from a zero baseline" :
                           "candidate preserved or improved a zero baseline"
    else
        preference = String(get(definition, "preference", "lower"))
        regression = preference == "higher" ? relative_delta < -limit :
                     relative_delta > limit
        record["status"] = regression ? "regression" : "pass"
        record["reason"] = regression ? "relative limit exceeded" : "within policy"
    end
    return record
end

function _missing_version_record(series, baseline, candidate, relation,
        statistic = :median)
    normalized_statistic = _normalize_sample_statistic(statistic)
    missing = String[]
    _version_point_value(baseline, normalized_statistic) === nothing &&
        push!(missing, String(baseline["version"]))
    _version_point_value(candidate, normalized_statistic) === nothing &&
        push!(missing, String(candidate["version"]))
    reasons = unique!(String[get(point, "reason", "no observation")
                             for point in (baseline, candidate) if !haskey(point, "median")])
    return Dict{String, Any}(
        "series_id" => series["series_id"], "package" => series["package"],
        "feature" => series["feature"],
        "workload" => get(series, "workload", series["feature"]),
        "comparison_key" => series["comparison_key"],
        "metric" => series["metric"],
        "measurement_definition" => series["measurement_definition"],
        "unit" => series["unit"], "relation" => relation,
        "baseline_version" => baseline["version"],
        "candidate_version" => candidate["version"],
        "baseline_samples" => get(baseline, "samples", 0),
        "candidate_samples" => get(candidate, "samples", 0),
        "baseline_median" => get(baseline, "median", nothing),
        "candidate_median" => get(candidate, "median", nothing),
        "sample_statistic" => string(normalized_statistic),
        "sample_statistic_definition" => _sample_statistic_definition(normalized_statistic),
        "baseline_value" => _version_point_value(baseline, normalized_statistic),
        "candidate_value" => _version_point_value(candidate, normalized_statistic),
        "absolute_delta" => nothing, "relative_delta" => nothing,
        "relative_limit" => nothing, "status" => "missing",
        "reason" => "missing observations for $(join(missing, ", ")): $(join(reasons, "; "))")
end

"Compare adjacent releases, then compare a development checkout to the latest release."
function compare_suite_versions(bundle::RunBundle;
        relative_limits::AbstractDict = Dict{String, Float64}(),
        min_samples::Integer = 1,
        sample_statistics::AbstractDict = Dict{String, Symbol}(),
        default_sample_statistic = :median)
    min_samples > 0 || throw(ArgumentError("min_samples must be positive"))
    default_statistic = _normalize_sample_statistic(default_sample_statistic)
    series = suite_version_series(bundle)
    availability = _availability_records(bundle)
    definitions = _definition_index(bundle)
    policies = _bundle_comparison_policies(bundle)
    records = Dict{String, Any}[]
    warnings = String[]
    isempty(series) && push!(warnings,
        "bundle has no package/feature/version observations")
    for item in series
        statistic = _sample_statistic_for(
            sample_statistics, String(item["metric"]), default_statistic)
        definition = get(definitions, String(item["measurement_definition"]), nothing)
        if definition === nothing
            push!(warnings, "missing definition $(item["measurement_definition"])")
            continue
        end
        for (baseline, candidate, relation) in _comparison_pairs(
            item, availability, policies, statistic)
            record = _version_point_value(baseline, statistic) !== nothing &&
                     _version_point_value(candidate, statistic) !== nothing ?
                     _version_comparison_record(item, baseline, candidate,
                relation, definition, relative_limits, min_samples, statistic) :
                     _missing_version_record(
                item, baseline, candidate, relation, statistic)
            push!(records, record)
        end
    end
    return VersionComparison(String(bundle.manifest["run_id"]), bundle_passed(bundle),
        unique!(warnings), availability, series, records)
end

"""
Return `true` only when the within-bundle version comparison is `:qualified`.
"""
function version_comparison_passed(comparison::VersionComparison)
    version_comparison_verdict(comparison) === :qualified
end

"""
Return `:invalid_input`, `:regressed`, `:qualified` or `:inconclusive` for a
`VersionComparison`. Empty records and incomplete evidence are inconclusive;
a successful input bundle alone does not qualify a version comparison.
"""
function version_comparison_verdict(comparison::VersionComparison)
    comparison.input_passed || return :invalid_input
    isempty(comparison.records) && return :inconclusive
    statuses = String[String(get(record, "status", "")) for record in comparison.records]
    any(==("regression"), statuses) && return :regressed
    all(==("pass"), statuses) && return :qualified
    return :inconclusive
end

"""
Return the dictionary representation of a VersionComparison with availability, series, comparisons and verdict.
This is an in-memory conversion; it does not write a report or run a workload.
"""
function version_comparison_dict(comparison::VersionComparison)
    return Dict{String, Any}(
        "schema_version" => "perfchecker-version-comparison/1",
        "run_id" => comparison.run_id,
        "input_passed" => comparison.input_passed,
        "passed" => version_comparison_passed(comparison),
        "verdict" => string(version_comparison_verdict(comparison)),
        "warnings" => comparison.warnings,
        "availability" => comparison.availability,
        "series" => comparison.series,
        "records" => comparison.records
    )
end

"""
    write_version_series_json(result::VersionComparison, path)

Write canonical JSON series and target availability. Create parent directories,
replace the destination file and return its path. The input is saved evidence;
this writer does not execute measurements.
"""
function write_version_series_json(comparison::VersionComparison, path::AbstractString)
    mkpath(dirname(path))
    _write_json(path,
        Dict(
            "schema_version" => "perfchecker-version-series/1",
            "run_id" => comparison.run_id,
            "availability" => comparison.availability,
            "series" => comparison.series,
            "plots" => [performance_plot_dict(_normalized_plot(comparison.series, entry))
                        for entry in _normalized_catalog(comparison.series)]);
        canonical = true)
    return String(path)
end

"""
    write_version_comparison_json(result::VersionComparison, path)

Write canonical JSON version-comparison evidence. Create parent directories,
replace the destination file and return its path. The input is saved evidence;
this writer does not execute measurements.
"""
function write_version_comparison_json(comparison::VersionComparison,
        path::AbstractString)
    mkpath(dirname(path))
    _write_json(path, version_comparison_dict(comparison); canonical = true)
    return String(path)
end

"""
    write_version_comparison_markdown(result::VersionComparison, path)

Write a Markdown version-comparison report. Create parent directories,
replace the destination file and return its path. The input is saved evidence;
this writer does not execute measurements.
"""
function write_version_comparison_markdown(comparison::VersionComparison,
        path::AbstractString)
    mkpath(dirname(path))
    open(path, "w") do io
        println(io, "# PerfChecker version comparison\n")
        println(io,
            "Verdict: **$(uppercase(string(version_comparison_verdict(comparison))))**  ")
        println(io, "Series: $(length(comparison.series))  ")
        println(io, "Comparisons: $(length(comparison.records))\n")
        println(
            io,
            "| Package | Feature | Metric | Statistic | Baseline | Candidate | Delta | Status |")
        println(io, "| --- | --- | --- | --- | --- | --- | ---: | --- |")
        for record in comparison.records
            delta = record["relative_delta"]
            formatted = delta === nothing ? "—" : "$(round(100 * delta; digits = 2))%"
            println(io,
                "| $(record["package"]) | $(record["feature"]) | " *
                "$(record["metric"]) | $(get(record, "sample_statistic", "median")) | " *
                "$(record["baseline_version"]) | " *
                "$(record["candidate_version"]) | $formatted | " *
                "$(record["status"]) |")
        end
        unavailable = [item
                       for item in comparison.availability
                       if item["status"] != "observed"]
        if !isempty(unavailable)
            println(io, "\n## Unavailable, failed, or missing targets\n")
            println(io, "| Package | Feature | Version | Status | Reason |")
            println(io, "| --- | --- | --- | --- | --- |")
            for item in unavailable
                println(io,
                    "| $(item["package"]) | $(item["feature"]) | " *
                    "$(item["version"]) | $(item["status"]) | $(item["reason"]) |")
            end
        end
    end
    return String(path)
end

@testitem "Historical version series and comparisons" tags=[:unit, :protocol, :comparison] begin
    using PerfChecker

    definition = Dict{String, Any}(
        "id" => "julia.wall.time/test-v1", "metric" => "julia.wall.time",
        "unit" => "ns", "preference" => "lower")
    observations = Dict{String, Any}[]
    for (version, kind, values) in (
        ("0.1.0", "release", [10, 12]),
        ("0.2.0", "release", [8, 10]),
        ("dev@0.3.0", "dev", [12, 14]))
        for (index, value) in enumerate(values)
            push!(observations,
                Dict{String, Any}(
                    "case_id" => "Example/parse@$version",
                    "metric" => "julia.wall.time", "value" => value, "unit" => "ns",
                    "sample_index" => index,
                    "measurement_definition" => "julia.wall.time/test-v1",
                    "comparison_key" => "parse/v1::julia.wall.time/test-v1",
                    "attributes" => Dict("package" => "Example", "feature" => "parse",
                        "version" => version, "target_kind" => kind)))
        end
    end
    manifest = Dict{String, Any}(
        "schema_version" => "perfchecker-run-bundle/1",
        "run_id" => "00000000-0000-0000-0000-000000000010",
        "attempt_id" => "00000000-0000-0000-0000-000000000011",
        "reuse_key" => repeat("a", 64), "evidence" => "fresh",
        "state" => "complete", "suite" => "example",
        "runtime" => Dict("language" => "julia"),
        "environment" => Dict{String, Any}(),
        "collector_capabilities" => ["test"], "warnings" => String[])
    bundle = RunBundle(manifest, [definition], observations,
        Dict{String, Any}[], Dict{String, Any}[])
    diagnostic = compare_suite_versions(bundle)
    @test length(diagnostic.series) == 1
    @test [point["version"] for point in only(diagnostic.series)["points"]] ==
          ["0.1.0", "0.2.0", "dev@0.3.0"]
    @test length(diagnostic.records) == 2
    @test Set(record["relation"] for record in diagnostic.records) ==
          Set(["adjacent-release", "dev-vs-latest-release"])
    @test all(record["status"] == "diagnostic" for record in diagnostic.records)
    @test version_comparison_verdict(diagnostic) == :inconclusive
    comparison_series = only(diagnostic.series)
    availability = [Dict{String, Any}("package" => "Example", "feature" => "parse",
                        "comparison_key" => "parse/v1", "version" => version,
                        "target_kind" => "release", "status" => status, "reason" => reason)
                    for (version, status, reason) in (
        ("0.0.1", "unavailable", "feature not introduced yet"),
        ("0.1.0", "observed", ""), ("0.2.0", "observed", ""))]
    comparable = PerfChecker._comparison_pairs(comparison_series, availability)
    @test length(comparable) == 1
    @test (comparable[1][1]["version"], comparable[1][2]["version"]) ==
          ("0.1.0", "0.2.0")
    availability[1]["status"] = "missing"
    @test length(PerfChecker._comparison_pairs(comparison_series, availability)) == 2
    grouped_policy = Dict{String, Any}(
        "id" => "stable-reference", "package" => "Example",
        "comparison_key" => "parse/v1", "feature" => "parse",
        "baselines" => ["0.1.0", "0.2.0"],
        "candidates" => ["dev@0.3.0"], "aggregation" => "median")
    grouped = only(PerfChecker._comparison_pairs(
        comparison_series, Dict{String, Any}[], [grouped_policy]))
    @test grouped[1]["median"] == 10
    @test grouped[1]["reference_versions"] == ["0.1.0", "0.2.0"]
    @test grouped[2]["version"] == "dev@0.3.0"
    @test grouped[3] == "candidate-vs-reference-group"
    gated = compare_suite_versions(bundle;
        relative_limits = Dict("julia.wall.time" => 0.1), min_samples = 2)
    @test !version_comparison_passed(gated)
    @test only(filter(record -> record["relation"] == "dev-vs-latest-release",
        gated.records))["status"] == "regression"
    p95_gated = compare_suite_versions(bundle;
        relative_limits = Dict("julia.wall.time" => 0.1), min_samples = 2,
        sample_statistics = Dict("julia.wall.time" => :p95))
    @test all(record["sample_statistic"] == "p95" for record in p95_gated.records)
    @test all(haskey(point["statistics"], "p99")
    for point in only(p95_gated.series)["points"])
    tail_baseline = Dict{String, Any}(
        "version" => "tail-a", "samples" => 20, "median" => 10.0,
        "statistics" => Dict("median" => 10.0, "p95" => 100.0))
    tail_candidate = Dict{String, Any}(
        "version" => "tail-b", "samples" => 20, "median" => 11.0,
        "statistics" => Dict("median" => 11.0, "p95" => 20.0))
    tail_record = PerfChecker._version_comparison_record(comparison_series,
        tail_baseline, tail_candidate, "test", definition,
        Dict("julia.wall.time" => 0.0), 20, :p95)
    @test tail_record["status"] == "pass"
    @test tail_record["baseline_median"] == 10.0
    @test tail_record["baseline_value"] == 100.0
    zero_series = merge(copy(comparison_series), Dict("series_id" => "zero-series"))
    zero_baseline = Dict{String, Any}(
        "version" => "zero", "samples" => 3, "median" => 0.0)
    zero_candidate = Dict{String, Any}(
        "version" => "still-zero", "samples" => 3, "median" => 0.0)
    zero_record = PerfChecker._version_comparison_record(zero_series,
        zero_baseline, zero_candidate, "test", definition,
        Dict("julia.wall.time" => 0.0), 3)
    @test zero_record["status"] == "pass"
    @test zero_record["relative_delta"] === nothing
    mktempdir() do dir
        @test isfile(write_version_series_json(gated, joinpath(dir, "series.json")))
        @test isfile(write_version_comparison_json(gated,
            joinpath(dir, "comparison.json")))
        @test occursin("dev@0.3.0",
            read(
                write_version_comparison_markdown(gated,
                    joinpath(dir, "comparison.md")), String))
    end
end
