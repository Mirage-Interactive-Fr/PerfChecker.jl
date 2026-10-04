"Run only declared scenario/collector/analyzer experiments within explicit count and wall-time limits."
function investigate(catalog::ScenarioCatalog; project = catalog.root, samples = 10,
        tools = [:jet, :alloccheck, :latency], max_experiments = 4, budget_seconds = 300,
        timeout = 120, threads = 1, advisor = nothing,
        cancellation = CancellationToken(), reports = nothing)
    1 <= max_experiments <= 100 || throw(ArgumentError("max_experiments must be in 1:100"))
    0 < budget_seconds <= 86400 && isfinite(budget_seconds) ||
        throw(ArgumentError("invalid investigation budget"))
    all(t -> haskey(_SCENARIO_ANALYZERS, Symbol(t)), tools) ||
        throw(ArgumentError("unknown experiment analyzer"))
    isempty(catalog.scenarios) &&
        throw(ArgumentError("declare scenarios before investigating"))
    menu = Dict{String, Any}[]
    for (index, spec) in enumerate(catalog.scenarios)
        for collector in spec.collectors
            push!(menu,
                Dict("id" => "experiment-$(length(menu)+1)",
                    "index" => index, "action" => "run",
                    "collector" => string(collector), "purpose" => "Measure $(spec.id) / $(spec.implementation) with $collector"))
        end
    end
    for tool in Symbol.(tools), (index, spec) in enumerate(catalog.scenarios)
        tool == :aqua && index != 1 && continue
        push!(menu,
            Dict("id" => "experiment-$(length(menu)+1)",
                "index" => index, "action" => "diagnose",
                "tool" => string(tool), "purpose" => "Analyze $(spec.id) / $(spec.implementation) with $tool"))
    end
    length(menu) <= 128 ||
        throw(ArgumentError("select a smaller catalog (maximum 128 proposed experiments)"))
    # Obtain a timing reference and inference evidence before spending the budget on secondary collectors.
    sort!(menu;
        by = e -> e["action"] == "run" && e["collector"] in ("benchmark", "chairmark") ? 0 :
                  e["action"] == "diagnose" && e["tool"] == "jet" ? 1 : 2,
        alg = Base.Sort.MergeSort)
    started = time()
    bundles = RunBundle[]
    records = Dict{String, Any}[]
    attempts = Dict{String, Any}[]
    decisions = Dict{String, Any}[]
    advice = advise(
        Dict("schema_version" => DIAGNOSIS_SCHEMA, "records" => records); bundles)
    status = "complete"
    first_useful = nothing
    while !isempty(menu) && length(attempts) < max_experiments
        remaining = budget_seconds - (time() - started)
        if cancellation.requested[] || remaining <= 0
            status = cancellation.requested[] ? "cancelled" : "budget_exhausted"
            break
        end
        index = 1
        if advisor !== nothing
            bounded = AdvisorConfig(; endpoint = advisor.endpoint, model = advisor.model,
                timeout = min(advisor.timeout, remaining), max_tokens = advisor.max_tokens,
                max_evidence_chars = advisor.max_evidence_chars, api_key_env = advisor.api_key_env,
                allow_remote = advisor.allow_remote, protocol = advisor.protocol, provider_package = advisor.provider_package)
            decision = narrate_advice(advice; config = bounded, project, cancellation,
                experiments = [Dict("id" => e["id"], "purpose" => e["purpose"])
                               for e in menu])
            push!(decisions, decision)
            if get(decision, "status", "") == "complete"
                chosen = get(decision, "experiment_id", "stop")
                if chosen == "stop"
                    status = "advisor_stopped"
                    break
                end
                index = something(findfirst(e -> e["id"] == chosen, menu), 1)
            end
        end
        remaining = budget_seconds - (time() - started)
        remaining > 0 || (status = "budget_exhausted"; break)
        experiment = popat!(menu, index)
        spec = catalog.scenarios[experiment["index"]]
        directory = reports === nothing ? nothing : joinpath(reports, experiment["id"])
        began = time()
        if experiment["action"] == "run"
            chosen = ScenarioSpec(spec.id; source = spec.source, factory = spec.factory,
                implementation = spec.implementation, parameters = spec.parameters, fixtures = spec.fixtures,
                repeatable = spec.repeatable, requirements = spec.requirements,
                collectors = [Symbol(experiment["collector"])])
            result = run_scenarios(
                ScenarioCatalog(catalog.root, [chosen]); project, samples, threads,
                timeout = min(timeout, remaining), cancellation, reports = directory)
            append!(bundles, result)
            outcome = all(bundle_passed, result) ? "complete" : "incomplete"
        else
            result = diagnose(ScenarioCatalog(catalog.root, [spec]);
                project, threads, reports = directory,
                tools = [Symbol(experiment["tool"])], timeout = min(timeout, remaining), cancellation)
            append!(records, result["records"])
            directory === nothing || write_investigation_report(result, directory)
            outcome = all(r -> r["status"] == "complete", result["records"]) ? "complete" :
                      "incomplete"
        end
        push!(attempts,
            merge(
                experiment, Dict("status" => outcome, "elapsed_seconds" => time() - began)))
        advice = advise(
            Dict("schema_version" => DIAGNOSIS_SCHEMA, "records" => records); bundles)
        first_useful === nothing && !isempty(advice["recommendations"]) &&
            (first_useful = time() - started)
    end
    cancellation.requested[] && (status = "cancelled")
    status == "complete" && !isempty(menu) && (status = "budget_exhausted")
    payload = Dict{String, Any}("schema_version" => "perfchecker-investigation/1",
        "status" => status, "authority" => "advisory_only", "elapsed_seconds" => time() -
                                                                                 started,
        "limits" => Dict(
            "max_experiments" => max_experiments, "budget_seconds" => budget_seconds),
        "experiments" => attempts, "unexecuted" => menu, "decisions" => decisions,
        "runs" => _scenario_run_record.(bundles), "records" => records, "advice" => advice,
        "code_modified" => false, "performance" => "not_compared", "first_useful_advice_seconds" => first_useful)
    reports === nothing || write_investigation_report(payload, reports)
    payload
end

"Evaluate evidence selection separately from prose truth; supplied expected rule IDs are the oracle."
function evaluate_advisors(
        cases::AbstractVector; config = nothing, project = dirname(Base.active_project()),
        cancellation = CancellationToken(), include_investigator = false,
        max_experiments = 4, budget_seconds = 300, samples = 10, tools = [
            :jet, :alloccheck, :latency])
    results = Dict{String, Any}[]
    for case in cases
        expected = Set(String.(case["expected_rules"]))
        advice = case["advice"]
        modes = config === nothing ? ["deterministic"] : ["deterministic", "model_writer"]
        include_investigator && push!(modes, "bounded_investigator")
        for mode in modes
            cancellation.requested[] && break
            started = time()
            agent = mode == "bounded_investigator" ?
                    investigate(load_scenario_catalog(case["catalog"]);
                project, advisor = config, cancellation, max_experiments,
                budget_seconds, samples, tools) : nothing
            observed = agent === nothing ? advice : agent["advice"]
            narrative = mode == "model_writer" ?
                        narrate_advice(advice; config, project, cancellation) : nothing
            ids = narrative === nothing ? [r["id"] for r in observed["recommendations"]] :
                  [c["evidence_id"] for c in get(narrative, "cards", [])]
            selected = Set(String(r["rule_id"])
            for r in observed["recommendations"] if r["id"] in ids)
            hits = length(intersect(selected, expected))
            push!(results,
                Dict("case" => case["id"], "mode" => mode,
                    "status" => agent !== nothing ? agent["status"] :
                                narrative === nothing ? "complete" : narrative["status"],
                    "expected_rules" => collect(expected), "selected_rules" => collect(selected),
                    "true_positives" => hits, "false_positives" => length(setdiff(
                        selected, expected)),
                    "false_negatives" => length(setdiff(expected, selected)),
                    "elapsed_seconds" => time() - started, "extra_experiments" => agent ===
                                                                                  nothing ?
                                                                                  0 :
                                                                                  length(agent["experiments"]),
                    "first_useful_advice_seconds" => agent === nothing ? nothing :
                                                     agent["first_useful_advice_seconds"],
                    "prose_truth" => "requires_human_review", "monetary_cost" => "not_measured",
                    "narrative" => narrative === nothing ? Dict() : narrative, "investigation" => agent ===
                                                                                                  nothing ?
                                                                                                  Dict() :
                                                                                                  agent))
        end
    end
    Dict("schema_version" => "perfchecker-advisor-evaluation/1", "results" => results,
        "scope" => "Evidence selection against explicit rules; fluency and semantic truth are not automatically qualified")
end
