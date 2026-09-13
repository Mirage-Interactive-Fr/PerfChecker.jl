"A presentation of saved investigation evidence for the REPL, Pluto and HTML reports."
struct InvestigationView
    payload::Dict{String, Any}
end

"Display an investigation without executing the target program."
function investigation_view(payload::AbstractDict)
    schema = get(payload, "schema_version", "")
    schema in (DISCOVERY_SCHEMA, DIAGNOSIS_SCHEMA, ADVICE_SCHEMA,
        "perfchecker-scenario-comparison/1", "perfchecker-scenario-run/1", "perfchecker-tool-catalog/1",
        "perfchecker-narrative/1", "perfchecker-investigation/1",
        "perfchecker-advisor-evaluation/1", "perfchecker-scenario-sync/1") ||
        throw(ArgumentError("unsupported investigation view schema"))
    return InvestigationView(Dict{String, Any}(string(k) => v for (k, v) in pairs(payload)))
end

function _investigation_escape(value)
    replace(string(value), '&' => "&amp;", '<' => "&lt;",
        '>' => "&gt;", '"' => "&quot;", '\'' => "&#39;")
end

function _investigation_rows(payload)
    schema = get(payload, "schema_version", "")
    if schema == "perfchecker-scenario-sync/1"
        return [(title = "$(r["scenario"]) / $(r["implementation"]) / $(r["collector"])",
                    status = r["qualification"],
                    text = "$(r["workflow"]) / $(r["job"]) / $(r["configuration"])",
                    evidence = r) for r in payload["coverage"]]
    elseif schema == "perfchecker-tool-catalog/1"
        return [(title = t["name"], status = t["integration"],
                    text = "$(t["purpose"])\n$(t["platform"])\n$(t["limitations"])",
                    evidence = t) for t in payload["tools"]]
    elseif schema == "perfchecker-narrative/1"
        rows = [(title = "Optional model explanation", status = "unverified_narrative",
                    text = c["explanation"], evidence = c) for c in payload["cards"]]
        if !isempty(get(payload, "external_review", ""))
            rows = vcat(rows,
                [(title = "External MCP advice", status = "unverified_narrative",
                    text = payload["external_review"], evidence = Dict("reference_status" => "unstructured_not_verified"))])
        end
        return vcat(rows, _investigation_rows(payload["fallback"]))
    elseif schema == "perfchecker-investigation/1"
        rows = [(title = e["purpose"], status = e["status"],
                    text = "$(e["elapsed_seconds"]) seconds", evidence = e)
                for e in payload["experiments"]]
        return vcat(rows, _investigation_rows(payload["advice"]))
    elseif schema == "perfchecker-advisor-evaluation/1"
        return [(title = "$(r["case"]) / $(r["mode"])",
                    status = r["status"],
                    text = "Matched $(r["true_positives"]); unsupported $(r["false_positives"]); missed $(r["false_negatives"]). Prose: $(r["prose_truth"])",
                    evidence = r) for r in payload["results"]]
    end
    if haskey(payload, "recommendations")
        return [(title = "$(r["scenario"]) / $(r["implementation"])",
                    status = "advisory", text = "$(r["hypothesis"])\n$(r["action"])\nVerify: $(r["validation"])",
                    evidence = r) for r in payload["recommendations"]]
    elseif haskey(payload, "declared")
        declared = [(title = "$(r["id"]) / $(r["implementation"])", status = "declared",
                        text = "$(r["source"]) → $(r["factory"])", evidence = r)
                    for r in payload["declared"]]
        proposals = [(title = r["id"], status = "proposed",
                         text = r["operation_candidate"], evidence = r)
                     for r in payload["candidates"]]
        return vcat(declared, proposals)
    elseif haskey(payload, "records")
        return [(title = "$(r["scenario"]) / $(r["implementation"]) / $(r["tool"])",
                    status = r["status"], text = "Correctness: $(get(r, "correctness", "not_checked")); quality: $(get(r, "quality", "not_checked")); performance: $(get(r, "performance", "not_compared"))\n$(get(r, "summary", ""))",
                    evidence = r) for r in payload["records"]]
    elseif haskey(payload, "configurations")
        return [(title = "$(r["scenario"]) / $(r["implementation"]) / $(r["collector"])",
                    status = r["status"], text = "Comparison of explicit configurations", evidence = r)
                for r in payload["configurations"]]
    end
    return [(title = "$(r["scenario"]["id"]) / $(r["scenario"]["implementation"])",
                status = r["qualification"]["availability"], text = "Collector: $(get(r, "collector", "unknown")); correctness: $(r["qualification"]["correctness"])\n" *
                                                                    join(
                    ["$(s["metric"]): median $(s["median"]) $(s["unit"]) ($(s["samples"]) samples)"
                     for s in get(r, "summaries", [])],
                    "\n"),
                evidence = r)
            for r in payload["runs"]]
end

function Base.show(io::IO, ::MIME"text/plain", view::InvestigationView)
    rows = _investigation_rows(view.payload)
    println(io, "PerfChecker investigation · ", length(rows), " records")
    haskey(view.payload, "status") && println(io, "Status: ", view.payload["status"])
    for row in rows
        println(io, '\n', row.title, " [", row.status, "]\n", row.text)
    end
    for warning in get(view.payload, "warnings", [])
        println(io, "\nUnresolved: ", warning["file"], ":",
            warning["line"], " ", warning["message"])
    end
    isempty(rows) && println(
        io, "No observations or recommendations; no general qualification is implied.")
end

function Base.show(io::IO, ::MIME"text/html", view::InvestigationView)
    escape = _investigation_escape
    print(io, "<section class=perfchecker-investigation><h2>PerfChecker investigation</h2>")
    haskey(view.payload, "status") &&
        print(io, "<p>Status: ", escape(view.payload["status"]), "</p>")
    rows = _investigation_rows(view.payload)
    isempty(rows) && print(io,
        "<p>No observations or recommendations; no general qualification is implied.</p>")
    for row in rows
        print(io,
            "<article style='border:1px solid #8895a5;border-radius:6px;padding:1em;margin:1em 0'>",
            "<h3>", escape(row.title), "</h3><p><strong>", escape(row.status),
            "</strong></p><p style='white-space:pre-wrap'>", escape(row.text),
            "</p><details><summary>Evidence, source and limits</summary><pre style='white-space:pre-wrap;max-height:24em;overflow:auto'>",
            escape(sprint(io -> JSON.print(io, row.evidence, 2))), "</pre></details></article>")
        profile = get(row.evidence, "profile", nothing)
        if profile !== nothing && (!isempty(get(profile, "stacks", [])) ||
            !isempty(get(profile, "allocation_sites", [])))
            print(io,
                "<details><summary>Sampled stacks and allocation sites</summary><p>These are profile weights, not independent timing observations.</p>")
            stacks = isempty(get(profile, "stacks", [])) ?
                     get(profile, "allocation_sites", []) : profile["stacks"]
            for stack in first(stacks, 100)
                print(io, "<details><summary>",
                    escape(get(stack, "value", get(stack, "bytes", 0))),
                    " samples / bytes</summary><pre style='white-space:pre-wrap'>",
                    escape(sprint(io -> JSON.print(io, stack["stack"], 2))), "</pre></details>")
            end
            print(io,
                "<p>Showing at most 100 stacks; complete profile remains in the bundle.</p></details>")
        end
    end
    for key in ("changes", "warnings", "ci", "corpora", "unexecuted",
        "decisions", "limits", "message", "usage")
        isempty(get(view.payload, key, [])) && continue
        print(io, "<details><summary>", escape(key),
            "</summary><pre style='white-space:pre-wrap'>",
            escape(sprint(io -> JSON.print(io, view.payload[key], 2))), "</pre></details>")
    end
    print(io, "</section>")
end

"An asynchronous investigation shared by the web interface and notebook interfaces."
mutable struct InvestigationJob
    id::String
    action::Symbol
    cancellation::CancellationToken
    task::Union{Nothing, Task}
    status::Symbol
    result::Union{Nothing, Dict{String, Any}}
    advice::Union{Nothing, Dict{String, Any}}
    error::String
    started::Float64
    finished::Union{Nothing, Float64}
    lock::ReentrantLock
end

"Launch one bounded investigation; callbacks execute only after this explicit call."
function launch_investigation(action::Symbol; root::AbstractString = pwd(),
        catalog::Union{Nothing, ScenarioCatalog} = nothing, project::AbstractString = root,
        tools = [:jet, :aqua, :alloccheck, :snoopcompile, :latency], samples::Integer = 10,
        timeout::Real = 120, threads::Integer = 1, reports = nothing, previous = nothing,
        advisor = nothing, evidence = nothing, max_experiments = 4, budget_seconds = 300)
    action in (:discover, :run, :diagnose, :sync, :tools, :narrate, :investigate) ||
        throw(ArgumentError("unsupported investigation action"))
    needs_catalog = action in (:run, :diagnose, :investigate)
    !needs_catalog || catalog !== nothing ||
        throw(ArgumentError("a declared catalogue is required"))
    !needs_catalog || !isempty(catalog.scenarios) ||
        throw(ArgumentError("select at least one declared scenario"))
    action != :narrate || evidence !== nothing ||
        throw(ArgumentError("saved deterministic advice is required"))
    job = InvestigationJob(string(uuid4()), action, CancellationToken(), nothing, :running,
        nothing, nothing, "", time(), nothing, ReentrantLock())
    job.task = @async begin
        try
            payload, advice = if action == :discover
                discover(root; previous), nothing
            elseif action == :sync
                scenario_sync(root; previous), nothing
            elseif action == :tools
                tool_catalog(), nothing
            elseif action == :narrate
                narrate_advice(
                    evidence; config = advisor === nothing ? AdvisorConfig() : advisor,
                    project, cancellation = job.cancellation),
                evidence
            elseif action == :investigate
                result = investigate(
                    catalog; project, tools, samples, timeout, threads, advisor,
                    max_experiments, budget_seconds, cancellation = job.cancellation,
                    reports = reports === nothing ? nothing :
                              joinpath(reports, "experiments"))
                result, result["advice"]
            elseif action == :diagnose
                result = diagnose(catalog; project, tools, timeout, threads, reports,
                    cancellation = job.cancellation)
                result, advise(result)
            else
                bundles = run_scenarios(catalog; project, samples, timeout, threads,
                    cancellation = job.cancellation, reports = reports === nothing ?
                                                               nothing :
                                                               joinpath(reports, "bundles"))
                payload = Dict{String, Any}(
                    "schema_version" => "perfchecker-scenario-run/1",
                    "runs" => _scenario_run_record.(bundles))
                payload,
                advise(
                    Dict("schema_version" => DIAGNOSIS_SCHEMA, "records" => []); bundles)
            end
            if reports !== nothing
                write_investigation_report(payload, reports)
                advice === nothing ||
                    write_investigation_report(advice, joinpath(reports, "advice"))
            end
            lock(job.lock) do
                job.result, job.advice = payload, advice
                job.status = job.cancellation.requested[] ? :cancelled : :complete
                job.finished = time()
            end
        catch error
            lock(job.lock) do
                job.status = job.cancellation.requested[] ? :cancelled : :error
                job.error = sprint(showerror, error, catch_backtrace())
                job.finished = time()
            end
        end
    end
    return job
end

"Request cancellation of a web or notebook investigation and its isolated worker."
cancel!(job::InvestigationJob) = cancel!(job.cancellation)

"Read a consistent job snapshot without waiting or rerunning code."
function investigation_status(job::InvestigationJob; include_result::Bool = true)
    lock(job.lock) do
        result = Dict{String, Any}("schema_version" => "perfchecker-investigation-job/1",
            "id" => job.id, "action" => string(job.action), "status" => string(job.status),
            "elapsed_seconds" => something(job.finished, time()) - job.started, "error" => job.error)
        if include_result
            job.result === nothing || (result["result"] = job.result)
            job.advice === nothing || (result["advice"] = job.advice)
        end
        return result
    end
end

"Wait for a launched investigation and retain incomplete or cancelled outcomes."
function wait_investigation(job::InvestigationJob)
    job.task === nothing || wait(job.task)
    return investigation_status(job)
end
