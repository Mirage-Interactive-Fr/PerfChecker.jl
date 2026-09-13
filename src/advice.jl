const ADVICE_SCHEMA = "perfchecker-advice/1"

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

"Produce deterministic, evidence-linked advice. This function never executes target code."
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
        "authority" => "advisory_only", "rules_version" => "1")
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
                    ("Garbage collection takes a measurable share of the observed execution time.",
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
    for bundle in bundles
        append!(recommendations, advise(bundle)["recommendations"])
    end
    return Dict{String, Any}(
        "schema_version" => ADVICE_SCHEMA, "recommendations" => recommendations,
        "authority" => "advisory_only", "rules_version" => "1")
end

"Expose diagnostics and deterministic advice to agents without running or modifying target code."
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

"Write the same investigation as JSON and human-readable Markdown. Existing output requires force=true."
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
