"A definition-aware comparison between two portable run bundles."
struct BundleComparison
    baseline_run_id::String
    candidate_run_id::String
    inputs_passed::Bool
    environment_status::Symbol
    warnings::Vector{String}
    records::Vector{Dict{String, Any}}
end

function _median(values::Vector{Float64})
    isempty(values) && return nothing
    ordered = sort(values)
    middle = length(ordered) ÷ 2
    return isodd(length(ordered)) ? ordered[middle + 1] :
           (ordered[middle] + ordered[middle + 1]) / 2
end

const _SAMPLE_STATISTICS = (:median, :mean, :minimum, :maximum, :p95, :p99)

function _normalize_sample_statistic(statistic)
    value = Symbol(lowercase(String(statistic)))
    value === :min && (value = :minimum)
    value === :max && (value = :maximum)
    value in _SAMPLE_STATISTICS || throw(ArgumentError(
        "sample statistic must be one of $(join(string.(_SAMPLE_STATISTICS), ", "))"))
    return value
end

function _linear_quantile(values::Vector{Float64}, probability::Float64)
    isempty(values) && return nothing
    0.0 <= probability <= 1.0 ||
        throw(ArgumentError("quantile probability must be between zero and one"))
    ordered = sort(values)
    length(ordered) == 1 && return only(ordered)
    position = 1 + (length(ordered) - 1) * probability
    lower = floor(Int, position)
    upper = ceil(Int, position)
    lower == upper && return ordered[lower]
    weight = position - lower
    return muladd(weight, ordered[upper] - ordered[lower], ordered[lower])
end

function _sample_statistic(values::Vector{Float64}, statistic)
    normalized = _normalize_sample_statistic(statistic)
    isempty(values) && return nothing
    normalized === :median && return _median(values)
    normalized === :mean && return sum(values) / length(values)
    normalized === :minimum && return minimum(values)
    normalized === :maximum && return maximum(values)
    normalized === :p95 && return _linear_quantile(values, 0.95)
    return _linear_quantile(values, 0.99)
end

function _sample_statistic_for(sample_statistics::AbstractDict, metric::String,
        default_sample_statistic)
    statistic = haskey(sample_statistics, metric) ? sample_statistics[metric] :
                haskey(sample_statistics, Symbol(metric)) ?
                sample_statistics[Symbol(metric)] :
                default_sample_statistic
    return _normalize_sample_statistic(statistic)
end

function _sample_statistic_definition(statistic)
    statistic in (:p95, :p99) ? "linear-r7/v1" : "exact/v1"
end

function _sample_statistics_dict(values::Vector{Float64})
    return Dict{String, Any}(string(statistic) => _sample_statistic(values, statistic)
    for statistic in _SAMPLE_STATISTICS)
end

function _observation_groups(bundle::RunBundle)
    groups = Dict{String, Vector{Dict{String, Any}}}()
    for observation in bundle.observations
        case_id = String(get(observation, "case_id", "unknown"))
        target_id = String(get(observation, "target_id", "unknown"))
        comparison_key = get(observation, "comparison_key", nothing)
        comparison_key === nothing &&
            (comparison_key = get(observation, "measurement_definition", "unknown"))
        join_key = "$case_id::$target_id::$(String(comparison_key))"
        push!(get!(groups, join_key, Dict{String, Any}[]), observation)
    end
    return groups
end

function _definition_index(bundle::RunBundle)
    return Dict(String(definition["id"]) => definition
    for definition in bundle.measurement_definitions)
end

function _environment_graph_fingerprints(bundle::RunBundle)
    records = get(bundle.manifest, "environment_provenance", Any[])
    fingerprints = Tuple{String, String}[]
    for record in records
        record isa AbstractDict || continue
        project = something(get(record, "project_sha256", nothing), "")
        manifest = something(get(record, "manifest_sha256", nothing), "")
        push!(fingerprints, (String(project), String(manifest)))
    end
    return sort!(unique!(fingerprints))
end

function _environment_comparability(baseline::RunBundle, candidate::RunBundle)
    left_runtime = get(baseline.manifest, "runtime", Dict{String, Any}())
    right_runtime = get(candidate.manifest, "runtime", Dict{String, Any}())
    left_environment = get(baseline.manifest, "environment", Dict{String, Any}())
    right_environment = get(candidate.manifest, "environment", Dict{String, Any}())
    warnings = String[]
    get(left_runtime, "language", nothing) == get(right_runtime, "language", nothing) ||
        return :incomparable, ["runtime languages differ"]
    for key in ("os", "architecture")
        left = get(left_environment, key, nothing)
        right = get(right_environment, key, nothing)
        left == right || return :incomparable, ["environment field $key differs"]
    end
    left_threads = get(left_runtime, "threads", nothing)
    right_threads = get(right_runtime, "threads", nothing)
    left_threads == right_threads || return :incomparable,
    ["Julia thread counts differ"]
    left_hardware = get(left_environment, "hardware_ids", nothing)
    right_hardware = get(right_environment, "hardware_ids", nothing)
    if left_hardware !== nothing && right_hardware !== nothing
        left_hardware == right_hardware || return :incomparable,
        ["hardware fingerprints differ"]
    elseif left_hardware !== right_hardware
        push!(warnings, "hardware fingerprint is missing from one input")
    end
    if get(left_runtime, "version", nothing) != get(right_runtime, "version", nothing)
        push!(warnings, "runtime versions differ")
    end
    left_graph = _environment_graph_fingerprints(baseline)
    right_graph = _environment_graph_fingerprints(candidate)
    left_graph == right_graph || push!(warnings, "resolved environment fingerprints differ")
    return isempty(warnings) ? :identical : :compatible, warnings
end

function _limit_for(relative_limits::AbstractDict, metric::String)
    value = get(relative_limits, metric, nothing)
    value === nothing && return nothing
    value isa Real && value >= 0 ||
        throw(ArgumentError("relative limit for $metric must be non-negative"))
    return Float64(value)
end

"Compare exact measurement definitions; no cross-unit conversion is implicit."
function compare_bundles(baseline::RunBundle, candidate::RunBundle;
        relative_limits::AbstractDict = Dict{String, Float64}(), min_samples::Integer = 1,
        sample_statistics::AbstractDict = Dict{String, Symbol}(),
        default_sample_statistic = :median)
    min_samples > 0 || throw(ArgumentError("min_samples must be positive"))
    default_statistic = _normalize_sample_statistic(default_sample_statistic)
    environment_status, warnings = _environment_comparability(baseline, candidate)
    baseline_groups = _observation_groups(baseline)
    candidate_groups = _observation_groups(candidate)
    baseline_definitions = _definition_index(baseline)
    candidate_definitions = _definition_index(candidate)
    records = Dict{String, Any}[]
    keys_union = sort!(collect(union(keys(baseline_groups), keys(candidate_groups))))
    for key in keys_union
        left = get(baseline_groups, key, Dict{String, Any}[])
        right = get(candidate_groups, key, Dict{String, Any}[])
        template = isempty(right) ? first(left) : first(right)
        metric = String(get(template, "metric", "unknown"))
        definition_id = String(get(template, "measurement_definition", "unknown"))
        unit = String(get(template, "unit", "unknown"))
        record = Dict{String, Any}(
            "case_id" => String(get(template, "case_id", "unknown")),
            "target_id" => String(get(template, "target_id", "unknown")),
            "comparison_key" => String(get(template, "comparison_key", definition_id)),
            "metric" => metric,
            "measurement_definition" => definition_id,
            "unit" => unit,
            "baseline_samples" => length(left),
            "candidate_samples" => length(right))
        if isempty(left) || isempty(right)
            record["status"] = "missing"
            record["reason"] = isempty(left) ? "baseline observation is missing" :
                               "candidate observation is missing"
            push!(records, record)
            continue
        end
        left_definition_id = String(get(first(left), "measurement_definition", "unknown"))
        right_definition_id = String(get(first(right), "measurement_definition", "unknown"))
        left_definition = get(baseline_definitions, left_definition_id, nothing)
        right_definition = get(candidate_definitions, right_definition_id, nothing)
        if left_definition_id != right_definition_id ||
           left_definition === nothing || right_definition === nothing ||
           _canonical_json(left_definition) != _canonical_json(right_definition)
            record["status"] = "incomparable"
            record["reason"] = "measurement definition or unit differs"
            push!(records, record)
            continue
        end
        left_values = Float64[observation["value"]
                              for observation in left
                              if observation["value"] isa Number]
        right_values = Float64[observation["value"]
                               for observation in right
                               if observation["value"] isa Number]
        if length(left_values) < min_samples || length(right_values) < min_samples
            record["status"] = "insufficient_samples"
            record["reason"] = "minimum sample count is $min_samples"
            push!(records, record)
            continue
        end
        statistic = _sample_statistic_for(sample_statistics, metric, default_statistic)
        baseline_median = _median(left_values)
        candidate_median = _median(right_values)
        baseline_value = _sample_statistic(left_values, statistic)
        candidate_value = _sample_statistic(right_values, statistic)
        absolute_delta = candidate_value - baseline_value
        relative_delta = iszero(baseline_value) ? nothing :
                         absolute_delta / abs(baseline_value)
        record["baseline_median"] = baseline_median
        record["candidate_median"] = candidate_median
        record["sample_statistic"] = string(statistic)
        record["sample_statistic_definition"] = _sample_statistic_definition(statistic)
        record["baseline_value"] = baseline_value
        record["candidate_value"] = candidate_value
        record["absolute_delta"] = absolute_delta
        record["relative_delta"] = relative_delta
        limit = _limit_for(relative_limits, metric)
        record["relative_limit"] = limit
        if environment_status === :incomparable
            record["status"] = "incomparable"
            record["reason"] = first(warnings)
        elseif limit === nothing
            record["status"] = "diagnostic"
            record["reason"] = "no CI policy configured for this metric"
        elseif relative_delta === nothing
            direction = String(get(right_definition, "preference", "lower"))
            regression = direction == "higher" ? candidate_value < baseline_value :
                         candidate_value > baseline_value
            record["status"] = regression ? "regression" : "pass"
            record["reason"] = regression ?
                               "candidate moved against policy from a zero baseline" :
                               "candidate preserved or improved a zero baseline"
        else
            direction = String(get(right_definition, "preference", "lower"))
            regression = direction == "higher" ? relative_delta < -limit :
                         relative_delta > limit
            record["status"] = regression ? "regression" : "pass"
            record["reason"] = regression ? "relative limit exceeded" : "within policy"
        end
        push!(records, record)
    end
    return BundleComparison(String(baseline.manifest["run_id"]),
        String(candidate.manifest["run_id"]),
        bundle_passed(baseline) && bundle_passed(candidate), environment_status,
        warnings, records)
end

"""
Return `true` only when `comparison_verdict(comparison)` is `:qualified`.
"""
function comparison_passed(comparison::BundleComparison)
    comparison_verdict(comparison) === :qualified
end

"""
    comparison_verdict(comparison::BundleComparison) -> Symbol

Return `:invalid_inputs`, `:incomparable`, `:regressed`, `:qualified` or
`:inconclusive`. Qualification requires valid inputs, comparable environments,
at least one comparison record and a passing status for every record.
"""
function comparison_verdict(comparison::BundleComparison)
    comparison.inputs_passed || return :invalid_inputs
    comparison.environment_status === :incomparable && return :incomparable
    isempty(comparison.records) && return :inconclusive
    statuses = String[String(get(record, "status", "")) for record in comparison.records]
    any(==("regression"), statuses) && return :regressed
    all(==("pass"), statuses) && return :qualified
    return :inconclusive
end

"""
Return the dictionary representation of a BundleComparison, including input validity, environment status, verdict and per-metric records.
This is an in-memory conversion; it does not write a report or run a workload.
"""
function comparison_dict(comparison::BundleComparison)
    return Dict{String, Any}(
        "schema_version" => "perfchecker-comparison/1",
        "baseline_run_id" => comparison.baseline_run_id,
        "candidate_run_id" => comparison.candidate_run_id,
        "inputs_passed" => comparison.inputs_passed,
        "environment_status" => string(comparison.environment_status),
        "warnings" => comparison.warnings,
        "passed" => comparison_passed(comparison),
        "verdict" => string(comparison_verdict(comparison)),
        "records" => comparison.records)
end

"""
    write_comparison_json(result::BundleComparison, path)

Write canonical JSON comparison evidence. Create parent directories,
replace the destination file and return its path. The input is saved evidence;
this writer does not execute measurements.
"""
function write_comparison_json(comparison::BundleComparison, path::AbstractString)
    mkpath(dirname(path))
    _write_json(path, comparison_dict(comparison); canonical = true)
    return String(path)
end

"""
    write_comparison_markdown(result::BundleComparison, path)

Write a Markdown comparison table and verdict. Create parent directories,
replace the destination file and return its path. The input is saved evidence;
this writer does not execute measurements.
"""
function write_comparison_markdown(comparison::BundleComparison, path::AbstractString)
    mkpath(dirname(path))
    open(path, "w") do io
        println(io, "# PerfChecker comparison\n")
        println(io, "Environment: `$(comparison.environment_status)`  ")
        println(io, "Verdict: **$(uppercase(string(comparison_verdict(comparison))))**\n")
        println(io, "| Metric | Statistic | Baseline | Candidate | Delta | Status |")
        println(io, "| --- | --- | ---: | ---: | ---: | --- |")
        for record in comparison.records
            statistic = get(record, "sample_statistic", "—")
            baseline = get(record, "baseline_value", get(record, "baseline_median", "—"))
            candidate = get(record, "candidate_value", get(record, "candidate_median", "—"))
            delta = get(record, "relative_delta", nothing)
            formatted_delta = delta === nothing ? "—" :
                              "$(round(100 * delta; digits = 2))%"
            println(io,
                "| $(record["metric"]) | $statistic | $baseline | $candidate | " *
                "$formatted_delta | $(record["status"]) |")
        end
    end
    return String(path)
end

@testitem "Definition-aware bundle comparison" tags=[:unit, :protocol, :comparison] begin
    using PerfChecker

    definition = Dict{String, Any}(
        "id" => "julia.wall.time/test-v1", "metric" => "julia.wall.time",
        "unit" => "ns", "preference" => "lower")
    function example_bundle(id, values; os = string(Sys.KERNEL))
        observations = [Dict{String, Any}(
                            "metric" => "julia.wall.time", "value" => value, "unit" => "ns",
                            "measurement_definition" => "julia.wall.time/test-v1",
                            "comparison_key" => "parse::julia.wall.time/test-v1")
                        for value in values]
        manifest = Dict{String, Any}(
            "schema_version" => "perfchecker-run-bundle/1", "run_id" => id,
            "attempt_id" => id, "reuse_key" => repeat("a", 64),
            "evidence" => "fresh", "state" => "complete", "suite" => "example",
            "runtime" => Dict("language" => "julia", "version" => string(VERSION)),
            "environment" => Dict{String, Any}(
                "os" => os, "architecture" => string(Sys.ARCH)),
            "collector_capabilities" => ["test"], "warnings" => String[])
        RunBundle(manifest, [definition], observations, Dict{String, Any}[],
            Dict{String, Any}[])
    end

    baseline = example_bundle("00000000-0000-0000-0000-000000000001", [10, 10, 10])
    candidate = example_bundle("00000000-0000-0000-0000-000000000002", [12, 12, 12])
    diagnostic = compare_bundles(baseline, candidate)
    @test !comparison_passed(diagnostic)
    @test comparison_verdict(diagnostic) == :inconclusive
    @test only(diagnostic.records)["status"] == "diagnostic"
    gated = compare_bundles(baseline, candidate;
        relative_limits = Dict("julia.wall.time" => 0.1), min_samples = 3)
    @test !comparison_passed(gated)
    @test only(gated.records)["status"] == "regression"
    @test only(gated.records)["relative_delta"] ≈ 0.2
    @test only(gated.records)["sample_statistic"] == "median"
    @test only(gated.records)["baseline_value"] == 10

    tail_baseline = example_bundle(
        "00000000-0000-0000-0000-000000000008", [fill(10, 19); 100])
    tail_candidate = example_bundle(
        "00000000-0000-0000-0000-000000000009", [fill(11, 19); 20])
    median_tail = compare_bundles(tail_baseline, tail_candidate;
        relative_limits = Dict("julia.wall.time" => 0.0), min_samples = 20)
    @test comparison_verdict(median_tail) == :regressed
    p95_tail = compare_bundles(tail_baseline, tail_candidate;
        relative_limits = Dict("julia.wall.time" => 0.0), min_samples = 20,
        sample_statistics = Dict("julia.wall.time" => :p95))
    @test comparison_verdict(p95_tail) == :qualified
    @test only(p95_tail.records)["sample_statistic"] == "p95"
    @test only(p95_tail.records)["sample_statistic_definition"] == "linear-r7/v1"
    @test only(p95_tail.records)["baseline_value"] ≈ 14.5
    @test only(p95_tail.records)["candidate_value"] ≈ 11.45
    maximum_tail = compare_bundles(tail_baseline, tail_candidate;
        relative_limits = Dict("julia.wall.time" => 0.0), min_samples = 20,
        default_sample_statistic = :max)
    @test comparison_verdict(maximum_tail) == :qualified
    @test only(maximum_tail.records)["sample_statistic"] == "maximum"
    @test_throws ArgumentError compare_bundles(tail_baseline, tail_candidate;
        default_sample_statistic = :mode)

    zero_baseline = example_bundle(
        "00000000-0000-0000-0000-000000000005", [0, 0, 0])
    zero_candidate = example_bundle(
        "00000000-0000-0000-0000-000000000006", [0, 0, 0])
    zero_gated = compare_bundles(zero_baseline, zero_candidate;
        relative_limits = Dict("julia.wall.time" => 0.0), min_samples = 3)
    @test comparison_passed(zero_gated)
    @test only(zero_gated.records)["status"] == "pass"
    @test only(zero_gated.records)["relative_delta"] === nothing

    nonzero_candidate = example_bundle(
        "00000000-0000-0000-0000-000000000007", [1, 1, 1])
    zero_regression = compare_bundles(zero_baseline, nonzero_candidate;
        relative_limits = Dict("julia.wall.time" => 0.0), min_samples = 3)
    @test comparison_verdict(zero_regression) == :regressed
    @test only(zero_regression.records)["status"] == "regression"

    for observation in baseline.observations
        observation["case_id"] = "parse@dev"
    end
    for observation in candidate.observations
        observation["case_id"] = "parse@dev"
    end
    append!(baseline.observations,
        [merge(copy(observation),
             Dict("case_id" => "format@dev", "value" => 1000))
         for observation in baseline.observations[1:3]])
    append!(candidate.observations,
        [merge(copy(observation),
             Dict("case_id" => "format@dev", "value" => 1000))
         for observation in candidate.observations[1:3]])
    separated = compare_bundles(baseline, candidate)
    @test length(separated.records) == 2
    @test Set(record["case_id"] for record in separated.records) ==
          Set(["parse@dev", "format@dev"])
    @test all(record["comparison_key"] == "parse::julia.wall.time/test-v1"
    for record in separated.records)

    failed = example_bundle("00000000-0000-0000-0000-000000000003", [12, 12, 12])
    failed.manifest["state"] = "failed"
    @test !comparison_passed(compare_bundles(baseline, failed))

    other_machine = example_bundle(
        "00000000-0000-0000-0000-000000000004", [12, 12, 12])
    baseline.manifest["environment"]["hardware_ids"] = ["machine-a"]
    other_machine.manifest["environment"]["hardware_ids"] = ["machine-b"]
    hardware_mismatch = compare_bundles(baseline, other_machine;
        relative_limits = Dict("julia.wall.time" => 0.5))
    @test comparison_verdict(hardware_mismatch) == :incomparable

    mktempdir() do dir
        @test isfile(write_comparison_json(gated, joinpath(dir, "comparison.json")))
        @test occursin("20.0%",
            read(write_comparison_markdown(gated, joinpath(dir, "comparison.md")), String))
    end
end
