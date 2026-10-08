const ADVICE_SCHEMA = "perfchecker-advice/1"

# Only canonical measured quantities are eligible for optional advisor context.
# Saved source paths, arbitrary attributes, parameters and diagnostics are not
# copied into this projection.
const _ADVICE_MEASUREMENT_DEFINITIONS = let definitions = Dict{String, Any}()
    for backend in (
            :benchmark, :chairmark, :alloc, :profile_alloc, :profile, :wall_profile,
            :network, :network_interface, :network_isolated),
        column in (:times, :gctimes, :memory, :bytes, :allocs, :percentage, :samples,
            :bytes_sent, :bytes_received, :operations, :seconds,
            :throughput_bytes_per_second, :operations_per_second, :packets_sent,
            :packets_received, :connections, :retransmissions, :discarded_sent,
            :discarded_received, :workload_seconds)

        definition = _measurement_definition(backend, column)
        definition === nothing && continue
        id, unit = definition
        definitions[id] = (
            metric = _metric_name(id), unit = unit, collector = string(backend))
    end
    definitions
end

function _advice_identifier(value)
    value isa AbstractString &&
        !occursin(r"^[A-Za-z]:", value) &&
        occursin(r"^[\p{L}\p{N}_][\p{L}\p{N}_.:@+-]{0,255}$", value)
end

function _advice_case_identifier(value)
    _advice_identifier(value) && return true
    value isa AbstractString && length(value) <= 512 && !occursin(r"^[A-Za-z]:", value) ||
        return false
    segments = split(value, '/')
    length(segments) == 3 && all(_advice_identifier, segments)
end

const _ADVICE_MEASUREMENT_SCOPES = ("workload", "whole_operation", "current_process",
    "current_thread", "isolated_worker_process", "host_interface", "isolated_worker_group")

function _advice_measurement_definition(definition)
    id = get(definition, "id", "")
    id isa AbstractString || return nothing
    canonical_id = endswith(id, "/fresh-state-evals1-v1") ?
                   chop(id; tail = length("/fresh-state-evals1-v1")) : id
    canonical = get(_ADVICE_MEASUREMENT_DEFINITIONS, canonical_id, nothing)
    if canonical !== nothing
        get(definition, "collector", "") == canonical.collector || return nothing
        canonical_id != id &&
            !(canonical.collector in (
                "benchmark", "chairmark", "profile", "wall_profile", "profile_alloc")) &&
            return nothing
    else
        totals = match(
            r"^(julia\.alloc\.(?:bytes|count))/profile-independent-totals-v1/(fresh|reuse)$",
            id)
        if totals !== nothing
            metric = first(totals.captures)
            get(definition, "collector", "") == "profile_alloc" || return nothing
            canonical = (
                metric = metric, unit = metric == "julia.alloc.bytes" ? "By" : "1",
                collector = "profile_alloc")
            get(definition, "metric", "") == canonical.metric &&
                get(definition, "unit", "") == canonical.unit || return nothing
            return canonical
        end
        matched = id isa AbstractString ?
                  match(
            r"^(julia\.(?:wall\.time|alloc\.bytes|alloc\.count))/shared-(benchmark|chairmark|profile|profile_alloc|profile-independent-totals)/[0-9a-f]{64}$", id) :
                  nothing
        matched === nothing && return nothing
        metric, collector = matched.captures
        collector == "profile-independent-totals" && metric == "julia.wall.time" &&
            return nothing
        collector == "profile-independent-totals" && (collector = "profile_alloc")
        get(get(definition, "context", Dict()), "collector", "") == collector ||
            return nothing
        canonical = (metric = metric,
            unit = metric == "julia.wall.time" ? "s" :
                   metric == "julia.alloc.bytes" ? "By" : "1",
            collector = collector)
    end
    get(definition, "metric", "") == canonical.metric &&
        get(definition, "unit", "") == canonical.unit || return nothing
    canonical
end

function _advice_record_semantics(id, collector, aggregation)
    totals = occursin("/shared-profile-independent-totals/", id) ||
             occursin("/profile-independent-totals-v1/", id)
    if aggregation == "independent_operation_total"
        totals || return nothing
        return "independent_operation_total"
    end
    aggregation == "sample" || return nothing
    totals && return nothing
    occursin("/shared-", id) && return "operation_measurement"
    collector == "alloc" && return "allocation_site"
    collector == "profile_alloc" && return "allocation_profile_record"
    collector in ("profile", "wall_profile") && return "profile_frame"
    collector == "network_interface" && return "host_interface_capture"
    collector == "network_isolated" && return "isolated_worker_group_capture"
    "operation_measurement"
end

function _advice_measurement_summaries(bundle::RunBundle)
    definitions = Dict(String(item["id"]) => item
    for item in bundle.measurement_definitions
    if get(item, "id", nothing) isa AbstractString)
    groups = Dict{NTuple{6, String}, Vector{Float64}}()
    seen = Dict{Any, Float64}()
    for observation in bundle.observations
        id = get(observation, "measurement_definition", "")
        haskey(definitions, id) || continue
        definition = definitions[id]
        canonical = _advice_measurement_definition(definition)
        canonical === nothing && continue
        get(observation, "metric", "") == canonical.metric &&
            get(observation, "unit", "") == canonical.unit || continue
        aggregation = get(observation, "aggregation", "sample")
        semantics = _advice_record_semantics(id, canonical.collector, aggregation)
        semantics === nothing && continue
        value = get(observation, "value", nothing)
        value isa Real && !(value isa Bool) && isfinite(value) || continue
        value isa Integer && abs(big(value)) > 2^53 - 1 && continue
        case_id, target_id = get(observation, "case_id", ""),
        get(observation, "target_id", "")
        _advice_case_identifier(case_id) && _advice_identifier(target_id) || continue
        scope = get(
            observation, "scope", get(definition, "attribution_scope", "unspecified"))
        scope in _ADVICE_MEASUREMENT_SCOPES || continue
        converted = Float64(value)
        isfinite(converted) || continue
        comparison = get(observation, "comparison_key", nothing)
        comparison === nothing || comparison isa AbstractString || continue
        fingerprint = _content_digest(comparison)
        key = (String(case_id), String(target_id), String(id),
            String(scope), String(aggregation), fingerprint)
        # A canonical column and its compatibility alias describe one record.
        # Equal values at different indices remain distinct observations.
        index = get(observation, "sample_index", nothing)
        table = get(get(observation, "attributes", Dict()), "table_index", nothing)
        if index isa Integer && !(index isa Bool) && index > 0
            record = (key, table, index)
            if haskey(seen, record)
                seen[record] == converted ||
                    throw(ArgumentError("conflicting measurement observation identity"))
                continue
            end
            seen[record] = converted
        end
        push!(get!(groups, key, Float64[]), converted)
    end
    qualification = get(bundle.manifest, "qualification", Dict())
    status = get(bundle.manifest, "state", "unknown")
    status in (
        "complete", "failed", "error", "unavailable", "cancelled", "timeout", "invalid") ||
        (status = "unknown")
    status == "complete" && !bundle_passed(bundle) && (status = "error")
    summaries = Dict{String, Any}[]
    for ((case_id, target_id, id, scope, aggregation, fingerprint), values) in sort!(
        collect(groups); by = first)
        correctness = get(qualification, "correctness", "not_checked")
        correctness_scope = isempty(qualification) ? "not_recorded" : "bundle"
        if isempty(qualification)
            checks = filter(
                check -> get(check, "case_id", "") == case_id &&
                    get(check, "target_id", "") == target_id,
                get(bundle.manifest, "run_qualifications", []))
            statuses = unique([get(
                                   get(get(check, "evidence", Dict()),
                                       "correctness", Dict()),
                                   "status", "not_checked") for check in checks])
            correctness = length(statuses) == 1 ? only(statuses) : "not_checked"
            correctness_scope = isempty(statuses) ? "not_recorded" :
                                length(statuses) == 1 ? "case_target" :
                                "ambiguous_case_target"
        end
        correctness in ("passed", "failed", "not_checked") || (correctness = "not_checked")
        canonical = _advice_measurement_definition(definitions[id])
        run_id = get(bundle.manifest, "run_id", "")
        attempt_id = get(bundle.manifest, "attempt_id", "")
        _advice_identifier(run_id) && _advice_identifier(attempt_id) || continue
        identity = Dict("run_id" => run_id, "attempt_id" => attempt_id,
            "case_id" => case_id, "target_id" => target_id,
            "measurement_definition" => id, "scope" => scope, "aggregation" => aggregation,
            "comparison_fingerprint" => fingerprint)
        semantics = _advice_record_semantics(id, canonical.collector, aggregation)
        push!(summaries,
            merge(identity,
                Dict{String, Any}(
                    "id" => "measurement-" * _content_digest(identity),
                    "kind" => "measurement", "metric" => canonical.metric,
                    "unit" => canonical.unit, "collector" => canonical.collector,
                    "bundle_status" => status, "correctness" => correctness,
                    "correctness_scope" => correctness_scope,
                    "record_count" => length(values), "record_semantics" => semantics, "minimum" => minimum(values),
                    "median" => _median(values), "maximum" => maximum(values))))
    end
    summaries
end

function _recommendation(
        rule, scenario, implementation, evidence, hypothesis, action, validation;
        location = Dict("file" => "", "line" => 0), limitations = String[])
    identity = _content_digest(Dict("rule" => rule, "scenario" => scenario,
        "implementation" => implementation, "location" => location))
    Dict{String, Any}("id" => identity, "rule_id" => rule, "scenario" => scenario,
        "implementation" => implementation, "location" => location, "evidence" => evidence,
        "hypothesis" => hypothesis, "action" => action, "validation" => validation,
        "limitations" => limitations, "predicted_gain" => "not_measured")
end

"""
    advise(bundle::RunBundle; min_samples=10)
    advise(diagnosis::AbstractDict; bundles=RunBundle[])

Return `perfchecker-advice/1` with evidence-linked recommendations,
`authority="advisory_only"` and rules version. The bundle form first checks
execution/correctness evidence, then considers sample sufficiency, empty CPU or
allocation profiles and dominant allocation sites. Positive `min_samples`
controls a sample-count recommendation; it is not a guarantee of tail accuracy.

`measurement_summaries` contains canonical measured quantities from only the
supplied bundles, independently of whether a recommendation exists. Each record
preserves its definition, unit, collector, bundle execution status, correctness
status and its scope, and aggregation. `record_count` counts saved records: `operation_measurement` denotes
operation measurements, while allocation sites, allocation-profile records,
profile frames and interface captures are explicitly distinguished. Their
minimum/median/maximum describe those records, not an operation cost or a count
of independent repetitions. Independent operation totals remain separate.
Compatibility aliases with the same definition and sample/table index count once.
Distinct comparison keys remain separate via a fingerprint; their text is not
copied. Conflicting correctness statuses at the same case/target are represented
as `not_checked` with `correctness_scope="ambiguous_case_target"`, rather than
attributed to an arbitrary variant. Bundle execution status is not a verdict on
an individual case. Direct manifest correctness has scope `bundle`; matching
suite qualifications have scope `case_target`, or `not_recorded` if absent.

Only known definitions/scopes and bounded identifiers (letters, numbers and
`_.:@+-`, at most 256 characters per identifier/segment) are projected. Canonical
suite case IDs also allow exactly three such slash-separated segments (512
characters total). Absolute
paths, Windows drives, backslashes, parent traversal and unknown quantities are
omitted; caller-chosen identifiers can still contain
sensitive text. Source, attributes, parameters, diagnostics and artifacts are
not copied or read. Review identifiers before sharing the resulting report.

The diagnosis form requires schema `perfchecker-diagnosis/1`, interprets analyzer
records and optionally incorporates saved bundle advice. Unsupported schemas or
nonpositive sample policies raise `ArgumentError`. Neither method executes
target code, contacts a provider or mutates files. Recommendations carry an
unmeasured predicted gain; an empty list does not establish qualification.
"""
function advise(bundle::RunBundle; min_samples::Integer = 10)
    min_samples > 0 || throw(ArgumentError("min_samples must be positive"))
    recommendations = Dict{String, Any}[]
    spec = get(bundle.manifest, "scenario", Dict())
    scenario = get(spec, "id", get(bundle.manifest, "case_id", "unknown"))
    implementation = get(spec, "implementation", "unknown")
    reference = Dict("run_id" => bundle.manifest["run_id"], "kind" => "run_bundle")
    raw = get(bundle.manifest, "scenario_evidence", Dict())
    qualification = get(bundle.manifest, "qualification", Dict())
    if isempty(qualification)
        checks = get(bundle.manifest, "run_qualifications", [])
        passed = !isempty(checks) && all(
            check -> get(get(get(check, "evidence", Dict()),
                    "correctness", Dict()),
                "status", "not_checked") == "passed",
            checks)
        qualification = Dict("correctness" => passed ? "passed" : "not_checked")
    end
    if !bundle_passed(bundle) ||
       get(qualification, "correctness", "not_checked") != "passed"
        push!(recommendations,
            _recommendation("evidence.correctness", scenario, implementation,
                reference, "Correctness or execution has not been validated.",
                "Inspect the error and define a correctness check before interpreting performance.",
                "Rerun the scenario and its correctness check with the same inputs."))
    else
        times = [o["value"]
                 for o in bundle.observations if o["metric"] == "julia.wall.time"]
        if !isempty(times) && length(times) < min_samples
            push!(recommendations,
                _recommendation("evidence.samples", scenario, implementation,
                    merge(reference,
                        Dict(
                            "samples" => length(times), "requested_minimum" => min_samples)),
                    "There are too few samples for the requested analysis policy.",
                    "Collect more comparable samples.",
                    "Inspect the distribution and compare it with an explicit baseline.",
                    limitations = ["Reaching this sample count does not guarantee an accurate p99 estimate."]))
        end
        if get(raw, "collector", "") == "profile" && get(raw, "profile_samples", 0) == 0
            push!(recommendations,
                _recommendation("evidence.profile", scenario, implementation,
                    reference, "The CPU profile contains no usable samples.",
                    "Increase the profiling duration or operation count, using fresh state.",
                    "Check that stacks were collected before attributing a cost to a function."))
        end
        allocation_profiles = haskey(raw, "allocation_profile") ?
                              [raw["allocation_profile"]] :
                              [check["evidence"]["allocation_profile"]
                               for check in get(bundle.manifest, "run_qualifications", [])
                               if haskey(
            get(check, "evidence", Dict()), "allocation_profile")]
        for summary in allocation_profiles
            summary["status"] in ("complete", "zero_allocations") && continue
            push!(recommendations,
                _recommendation("evidence.allocation_profile", scenario, implementation,
                    merge(reference, Dict("allocation_profile" => summary)),
                    summary["message"],
                    summary["status"] == "no_samples" ?
                    "Increase sample_rate or profile_repetitions with fresh state." :
                    "Check target selection and source locations before attributing allocations.",
                    "Collect usable allocation stacks and compare the independent whole-operation totals."))
        end
        sites = get(raw, "allocation_sites", Any[])
        if isempty(sites)
            sites = [Dict("bytes" => o["value"], "file" => o["attributes"]["source_file"],
                         "line" => get(o["attributes"], "source_line", 0))
                     for o in bundle.observations
                     if o["metric"] == "julia.alloc.bytes" &&
                        haskey(get(o, "attributes", Dict()), "source_file")]
        end
        total = sum(site["bytes"] for site in sites; init = 0)
        if total > 0
            grouped = Dict{Tuple{String, Int}, Float64}()
            source = get(spec, "source", "")
            for site in sites
                frames = get(site, "stack", Any[])
                index = findfirst(f -> normpath(f["file"]) == normpath(source), frames)
                frame = index === nothing ? site : frames[index]
                key = (frame["file"], Int(frame["line"]))
                grouped[key] = get(grouped, key, 0) + site["bytes"]
            end
            for (location, bytes) in sort!(collect(grouped); by = x -> -last(x))
                bytes / total >= 0.25 || continue
                push!(recommendations,
                    _recommendation("allocation.dominant_site", scenario, implementation,
                        merge(reference,
                            Dict("sampled_bytes" => bytes,
                                "sampled_fraction" => bytes / total)),
                        "This call path accounts for a large share of observed allocations.",
                        "Inspect temporary objects, copies and conversions; try reusing storage if the operation permits it.",
                        "Check correctness, elapsed time, allocations and retained memory after the change.",
                        location = Dict("file" => location[1], "line" => location[2]),
                        limitations = ["An allocation may be necessary; removing it does not guarantee a speedup."]))
            end
        end
    end
    return Dict{String, Any}(
        "schema_version" => ADVICE_SCHEMA, "recommendations" => recommendations,
        "authority" => "advisory_only", "rules_version" => "1",
        "measurement_summaries" => _advice_measurement_summaries(bundle))
end

function advise(diagnosis::AbstractDict; bundles::AbstractVector{RunBundle} = RunBundle[])
    get(diagnosis, "schema_version", "") == DIAGNOSIS_SCHEMA ||
        throw(ArgumentError("advise expects a diagnosis report or RunBundle"))
    recommendations = Dict{String, Any}[]
    for record in get(diagnosis, "records", Any[])
        scenario, implementation = record["scenario"], record["implementation"]
        reference = Dict("tool" => record["tool"], "status" => record["status"],
            "configuration" => get(record, "configuration", Dict()))
        if record["status"] != "complete"
            if get(record, "correctness", "not_checked") == "failed"
                push!(recommendations,
                    _recommendation("evidence.correctness", scenario, implementation,
                        reference, "The operation or its correctness check failed.",
                        "Fix the functional failure before interpreting performance.",
                        "Rerun the tests, scenario and correctness check with the same inputs.",
                        limitations = [get(record, "message", record["status"])]))
                continue
            end
            push!(recommendations,
                _recommendation("evidence.analyzer", scenario, implementation,
                    reference, "The analysis did not produce a usable result.",
                    "Check the analyzer's availability, compatibility and time limit.",
                    "Rerun the affected analysis in a compatible environment.",
                    limitations = [get(record, "message", record["status"])]))
            continue
        end
        for finding in get(record, "findings", Any[])
            rule = finding["rule_id"]
            evidence = merge(reference, Dict("finding" => finding))
            location = get(finding, "location", Dict("file" => "", "line" => 0))
            if rule in ("inference.runtime_dispatch", "inference.optimization")
                measured = any(
                    b -> get(get(b.manifest, "scenario", Dict()), "id", "") == scenario &&
                             get(get(b.manifest, "scenario", Dict()),
                                 "implementation", "") == implementation &&
                             bundle_passed(b),
                    bundles)
                push!(recommendations,
                    _recommendation(rule, scenario, implementation, evidence,
                        "JET reports an inference issue for this specialization.",
                        measured ?
                        "Locate the call path in the profile before trying more precise types or a function barrier." :
                        "Benchmark and profile this scenario to find out whether the diagnostic affects an expensive call path.",
                        "Rerun JET, correctness checks and measurements for each affected implementation.";
                        location, limitations = ["A static diagnostic does not establish a dominant cost or a regression."]))
            elseif rule in (
                "memory.gc_pressure", "memory.state_growth", "concurrency.lock_contention")
                hypothesis, action, verification = if rule == "memory.gc_pressure"
                    (
                        "Garbage collection takes a measurable share of the observed execution time.",
                        "Locate the largest allocation sources and try reusable workspace where the operation permits it.",
                        "Compare allocations, GC time and elapsed time across repeated runs, keeping correctness checks unchanged.")
                elseif rule == "memory.state_growth"
                    ("Reachable state grows after the operation in the observed cases.",
                        "Check whether the growth is intended; inspect caches, retained references and cleanup before concluding that memory leaks.",
                        "Compare state, results and snapshots on a representative scenario with the same lifetime policy.")
                else
                    ("Some lock acquisitions had to wait during the operation.",
                        "Profile the waiting time and compare critical-section sizes at several thread counts.",
                        "Check concurrency invariants and compare throughput, latency and contention without changing correctness checks.")
                end
                push!(recommendations,
                    _recommendation(rule, scenario, implementation,
                        evidence, hypothesis, action, verification; location,
                        limitations = get(record, "limitations", String[])))
            elseif rule == "allocation.potential"
                push!(recommendations,
                    _recommendation(rule, scenario, implementation, evidence,
                        "Static analysis reports a possible allocation.",
                        "Confirm the call path with an allocation profile and a representative case.",
                        "Compare allocations and elapsed time after the change, using the same correctness check.";
                        location, limitations = [get(
                            record, "analysis_scope", "specialization-specific analysis")]))
            elseif rule == "compilation.inference"
                push!(recommendations,
                    _recommendation(rule, scenario, implementation, evidence,
                        "Type inference was observed during the first scenario.",
                        "Compare first-call and warm execution; inspect expensive specializations.",
                        "Measure loading, the first operation and precompilation cost in fresh processes.";
                        location, limitations = ["The observed inference may be expected and useful."]))
            elseif rule == "quality.aqua"
                push!(recommendations,
                    _recommendation(rule, scenario, implementation, evidence,
                        "An Aqua quality check failed.", "Inspect the check and its explicit exclusions.",
                        "Rerun Aqua and functional tests; evaluate performance separately."; location))
            end
        end
        if record["tool"] == "latency"
            metrics = get(record, "measurements", Dict())
            first_time = get(metrics, "first_case_seconds", 0.0)
            warm_time = get(metrics, "warm_case_seconds", 0.0)
            if first_time > max(0.01, 2warm_time)
                push!(recommendations,
                    _recommendation("latency.first_case", scenario, implementation,
                        merge(reference, Dict("measurements" => metrics)),
                        "The first observed execution costs more than the next one.",
                        "Separate compilation, initialization and cache effects using several fresh processes.",
                        "Check the improvement in both startup and warm execution.",
                        limitations = ["Two exploratory observations are not enough to attribute the difference to compilation."]))
            end
        end
    end
    summaries = Dict{String, Any}[]
    for bundle in bundles
        report = advise(bundle)
        append!(recommendations, report["recommendations"])
        append!(summaries, report["measurement_summaries"])
    end
    return Dict{String, Any}(
        "schema_version" => ADVICE_SCHEMA, "recommendations" => recommendations,
        "authority" => "advisory_only", "rules_version" => "1",
        "measurement_summaries" => summaries)
end

"""
    agent_evidence(diagnosis::AbstractDict; max_records=100)

Return a `perfchecker-investigation-evidence/1` dictionary containing bounded
records and recommendations, with advisory authority and a `truncated` flag.
Accept diagnosis, advice, narrative and investigation schemas. Narrative cards
retain `unverified_narrative` authority and deterministic fallback advice;
investigation results retain status, experiments and external-review metadata.
Positive `max_records` caps each list independently, not the total payload size.
Invalid input schemas propagate an advice validation error. No target code,
provider call, report write or code modification is performed.
"""
function agent_evidence(diagnosis::AbstractDict; max_records::Integer = 100)
    max_records > 0 || throw(ArgumentError("max_records must be positive"))
    schema = get(diagnosis, "schema_version", "")
    if schema in (ADVICE_SCHEMA, "perfchecker-narrative/1", "perfchecker-investigation/1")
        advice = schema == ADVICE_SCHEMA ? diagnosis :
                 schema == "perfchecker-narrative/1" ? diagnosis["fallback"] :
                 diagnosis["advice"]
        records = get(diagnosis, "records", [])
        cards = get(diagnosis, "cards", [])
        experiments = get(diagnosis, "experiments", [])
        return Dict{String, Any}(
            "schema_version" => "perfchecker-investigation-evidence/1",
            "records" => first(records, max_records), "recommendations" => first(
                advice["recommendations"], max_records),
            "narrative" => first(cards, max_records), "narrative_authority" => "unverified_narrative",
            "external_review" => get(diagnosis, "external_review", ""),
            "reference_status" => get(diagnosis, "reference_status", "structured"),
            "experiments" => first(experiments, max_records), "status" => get(
                diagnosis, "status", "complete"),
            "truncated" => any(length(items) > max_records
            for items in (records, cards, experiments, advice["recommendations"])),
            "authority" => "advisory_only")
    end
    advice = advise(diagnosis)
    return Dict{String, Any}("schema_version" => "perfchecker-investigation-evidence/1",
        "records" => first(diagnosis["records"], max_records),
        "recommendations" => first(advice["recommendations"], max_records),
        "truncated" => length(diagnosis["records"]) > max_records ||
                       length(advice["recommendations"]) > max_records,
        "authority" => "advisory_only")
end

"""
    write_investigation_report(payload::AbstractDict, directory; force=false)

Write canonical JSON and readable Markdown for a discovery, diagnosis, advice,
scenario comparison/run, tool catalogue, narrative, investigation, advisor
evaluation or scenario-sync payload. The schema determines the basename (for
example `diagnosis.json` and `diagnosis.md`); return the two paths.
Create `directory` as needed. If either destination is an existing file, throw
`ArgumentError` unless `force=true`; force permits replacing both reports.
Unsupported schemas raise an error, and serialization/filesystem failures
propagate. Writes are sequential, so an interrupted export can leave one report.
This renders supplied evidence without rerunning its workloads or advisors.
"""
function write_investigation_report(
        payload::AbstractDict, directory::AbstractString; force::Bool = false)
    schema = get(payload, "schema_version", "")
    name = schema == DISCOVERY_SCHEMA ? "discovery" :
           schema == DIAGNOSIS_SCHEMA ? "diagnosis" :
           schema == ADVICE_SCHEMA ? "advice" :
           schema == "perfchecker-scenario-comparison/1" ? "comparison" :
           schema == "perfchecker-scenario-run/1" ? "run" :
           schema == "perfchecker-tool-catalog/1" ? "tools" :
           schema == "perfchecker-narrative/1" ? "narrative" :
           schema == "perfchecker-investigation/1" ? "investigation" :
           schema == "perfchecker-advisor-evaluation/1" ? "evaluation" :
           schema == "perfchecker-scenario-sync/1" ? "sync" :
           error("unsupported investigation report")
    paths = [joinpath(directory, "$name.json"), joinpath(directory, "$name.md")]
    !force && any(isfile, paths) &&
        throw(ArgumentError("report exists; use force=true to replace it"))
    mkpath(directory)
    _write_json(paths[1], payload; canonical = true)
    open(paths[2], "w") do io
        println(io, "# PerfChecker — $name\n")
        if schema in ("perfchecker-tool-catalog/1", "perfchecker-narrative/1",
            "perfchecker-investigation/1",
            "perfchecker-advisor-evaluation/1", "perfchecker-scenario-sync/1")
            show(io, MIME"text/plain"(), investigation_view(payload))
        elseif schema == ADVICE_SCHEMA
            for item in payload["recommendations"]
                println(io, "## ", item["scenario"], " / ", item["implementation"], "\n")
                for key in ("hypothesis", "action", "validation", "limitations", "evidence")
                    println(io, "**$key**: ", item[key], "\n")
                end
            end
            isempty(payload["recommendations"]) && println(io,
                "These rules produced no supported recommendation. This does not establish overall qualification.")
        elseif schema == "perfchecker-scenario-run/1"
            show(io, MIME"text/plain"(), investigation_view(payload))
        elseif schema == "perfchecker-scenario-comparison/1"
            println(io,
                "| Scenario | Implementation | Collector | Verdict |\n|---|---|---|---|")
            for item in payload["configurations"]
                println(io,
                    "| ",
                    join(
                        [replace(string(item[key]), "|" => "\\|")
                         for key in ("scenario", "implementation", "collector", "status")],
                        " | "),
                    " |")
            end
        else
            key = schema == DISCOVERY_SCHEMA ? "candidates" : "records"
            for item in payload[key]
                println(io, "- ", get(item, "id", get(item, "scenario", "package")),
                    " — ", item["status"],
                    ": ",
                    get(item, "message",
                        get(item, "operation_candidate", get(item, "tool", ""))))
                isempty(get(item, "summary", "")) || println(io, "\n  ", item["summary"])
                for artifact in get(item, "artifacts", [])
                    println(io, "\n  Artifact: ", artifact["path"],
                        " (SHA-256 ", artifact["sha256"], ")")
                end
            end
            if schema == DISCOVERY_SCHEMA
                println(io, "\nDeclarations: ", length(payload["declared"]),
                    "; candidates: ", length(payload["candidates"]))
                for warning in payload["warnings"]
                    println(io, "\n- ", warning["file"], ":",
                        warning["line"], " — ", warning["message"])
                end
                for change in payload["changes"]
                    println(io, "\n- ", change["status"], " : ", change["file"])
                end
            else
                for record in payload["records"], finding in get(record, "findings", Any[])
                    println(io, "\n- ", finding["rule_id"], ": ", finding["message"])
                end
            end
        end
    end
    return paths
end
