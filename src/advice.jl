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
                reference, "La correction ou l'exécution n'est pas qualifiée.",
                "Examiner l'erreur et établir un oracle avant d'interpréter les performances.",
                "Rejouer le scénario et son oracle avec le même corpus."))
    else
        times = [o["value"]
                 for o in bundle.observations if o["metric"] == "julia.wall.time"]
        if !isempty(times) && length(times) < min_samples
            push!(recommendations,
                _recommendation("evidence.samples", scenario, implementation,
                    merge(reference,
                        Dict(
                            "samples" => length(times), "requested_minimum" => min_samples)),
                    "La série est trop courte pour la politique d'analyse demandée.",
                    "Collecter davantage d'échantillons comparables.",
                    "Examiner la distribution et comparer à une référence explicite.",
                    limitations = ["Atteindre ce nombre ne garantit pas la précision d'un p99."]))
        end
        if get(raw, "collector", "") == "profile" && get(raw, "profile_samples", 0) == 0
            push!(recommendations,
                _recommendation("evidence.profile", scenario, implementation,
                    reference, "Le profil CPU ne contient aucun échantillon exploitable.",
                    "Augmenter la durée ou le nombre d'opérations profilées avec un état frais.",
                    "Vérifier que des piles sont collectées avant d'attribuer un coût à une fonction."))
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
                        "Ce chemin représente une part importante des allocations observées.",
                        "Examiner les temporaires, copies et conversions ; tester une réutilisation si la sémantique le permet.",
                        "Vérifier l'oracle, le temps, les allocations et la mémoire retenue après modification.",
                        location = Dict("file" => location[1], "line" => location[2]),
                        limitations = ["Une allocation peut être nécessaire ; la supprimer ne garantit pas un gain de temps."]))
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
                        reference, "L'opération ou son oracle a échoué.",
                        "Corriger le cas fonctionnel avant d'interpréter les performances.",
                        "Rejouer les tests, le scénario et son oracle avec les mêmes entrées.",
                        limitations = [get(record, "message", record["status"])]))
                continue
            end
            push!(recommendations,
                _recommendation("evidence.analyzer", scenario, implementation,
                    reference, "L'analyse n'a pas fourni de résultat exploitable.",
                    "Consulter la disponibilité, la compatibilité ou la limite de durée de l'analyseur.",
                    "Relancer uniquement l'analyse concernée dans un environnement compatible.",
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
                        "JET signale une difficulté d'inférence sur cette spécialisation.",
                        measured ?
                        "Localiser le chemin dans le profil avant de tester une amélioration des types ou une frontière de fonction." :
                        "Mesurer et profiler ce scénario pour déterminer si le diagnostic touche un chemin coûteux.",
                        "Rejouer JET, l'oracle et les mesures sur chaque implémentation concernée.";
                        location, limitations = ["Le diagnostic statique ne prouve ni un coût dominant ni une régression."]))
            elseif rule in (
                "memory.gc_pressure", "memory.state_growth", "concurrency.lock_contention")
                hypothesis, action, verification = if rule == "memory.gc_pressure"
                    ("Le GC occupe une part mesurable des opérations observées.",
                        "Localiser les allocations dominantes et tester un espace de travail réutilisable quand le contrat le permet.",
                        "Comparer allocations, temps de GC et durée avec l'oracle inchangé, sur plusieurs exécutions.")
                elseif rule == "memory.state_growth"
                    ("L'état accessible grossit après l'opération dans les cas observés.",
                        "Vérifier si cette croissance est voulue ; examiner caches, références conservées et nettoyage avant de parler de fuite.",
                        "Comparer état, résultat et snapshots sur un scénario représentatif avec la même politique de durée de vie.")
                else
                    ("Des acquisitions de verrou ont dû attendre pendant l'opération.",
                        "Profiler l'attente et comparer la granularité des sections critiques sur plusieurs nombres de threads.",
                        "Vérifier les invariants concurrents et comparer débit, latence et conflits sans modifier l'oracle.")
                end
                push!(recommendations,
                    _recommendation(rule, scenario, implementation,
                        evidence, hypothesis, action, verification; location,
                        limitations = get(record, "limitations", String[])))
            elseif rule == "allocation.potential"
                push!(recommendations,
                    _recommendation(rule, scenario, implementation, evidence,
                        "L'analyse statique signale une allocation potentielle.",
                        "Confirmer le chemin concerné avec un profil d'allocations et un cas représentatif.",
                        "Comparer allocations et temps après correction, avec le même oracle.";
                        location, limitations = [get(
                            record, "analysis_scope", "specialization-specific analysis")]))
            elseif rule == "compilation.inference"
                push!(recommendations,
                    _recommendation(rule, scenario, implementation, evidence,
                        "De l'inférence a été observée pendant le premier scénario.",
                        "Comparer première exécution et régime chaud ; examiner les spécialisations coûteuses.",
                        "Mesurer dans de nouveaux processus le chargement, la première opération et le coût de précompilation.";
                        location, limitations = ["L'inférence observée peut être normale et utile."]))
            elseif rule == "quality.aqua"
                push!(recommendations,
                    _recommendation(rule, scenario, implementation, evidence,
                        "Un contrôle de qualité Aqua a échoué.", "Examiner le contrôle et ses exclusions explicites.",
                        "Rejouer Aqua et les tests fonctionnels ; évaluer séparément les performances."; location))
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
                        "La première exécution observée coûte davantage que la suivante.",
                        "Séparer compilation, initialisation et effets des caches avec plusieurs processus neufs.",
                        "Vérifier le gain sur le démarrage et le régime chaud.",
                        limitations = ["Deux observations exploratoires ne suffisent pas à attribuer la différence à la compilation."]))
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
                "Aucune recommandation étayée par ces règles. Cela ne constitue pas une qualification générale.")
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
                println(io, "\nDéclarations : ", length(payload["declared"]),
                    "; propositions : ", length(payload["candidates"]))
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
