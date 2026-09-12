function _diagnostic_sample_count(options)
    count = get(options, "diagnostic_samples", 5)
    count isa Integer && 1 <= count <= 1000 ||
        throw(ArgumentError("diagnostic_samples must be an integer in 1:1000"))
    Int(count)
end

function _operation_counters(case, count)
    rows = Dict{String, Any}[]
    for _ in 1:count
        evaluation = SharedScenarioRuntime.prepare(case)
        try
            measured = @timed SharedScenarioRuntime.operation!(evaluation)
            SharedScenarioRuntime.verify!(evaluation)
            row = Dict{String, Any}("operation_seconds" => measured.time,
                "gc_seconds" => measured.gctime, "allocated_bytes" => measured.bytes)
            for key in (:pause, :full_sweep, :poolalloc, :bigalloc, :malloc, :realloc)
                hasproperty(measured.gcstats, key) &&
                    (row[string(key)] = getproperty(measured.gcstats, key))
            end
            for key in (:lock_conflicts, :compile_time, :recompile_time)
                hasproperty(measured, key) &&
                    (row[string(key)] = getproperty(measured, key))
            end
            push!(rows, row)
        finally
            SharedScenarioRuntime.cleanup!(evaluation)
        end
    end
    rows
end

function _analyze_scenario(::Val{:gc}, case, options)
    rows = _operation_counters(case, _diagnostic_sample_count(options))
    gc_seconds = sum(row["gc_seconds"] for row in rows)
    duration = sum(row["operation_seconds"] for row in rows)
    fraction = duration > 0 ? gc_seconds / duration : 0.0
    findings = Dict{String, Any}[]
    if gc_seconds >= 0.001 && fraction >= 0.1
        push!(findings,
            _analyzer_finding("memory.gc_pressure",
                "Garbage collection occupied at least 10% of observed operation time.";
                evidence = Dict(
                    "gc_seconds" => gc_seconds, "operation_seconds" => duration,
                    "fraction" => fraction, "samples" => length(rows))))
    end
    Dict("status" => "complete", "correctness" => "passed", "findings" => findings,
        "measurements" => Dict("samples" => rows),
        "analysis_scope" => "warmed operation and synchronization; fresh state; preparation, verification and cleanup excluded",
        "limitations" => ["Diagnostic instrumentation is separate from baseline timing.",
            "GC counters are process-wide and can include concurrently running tasks.",
            "No observed collection is not evidence that the workload never triggers GC."])
end

function _analyze_scenario(::Val{:locks}, case, options)
    VERSION >= v"1.11" || return Dict("status" => "unavailable",
        "message" => "lock conflict counters require Julia 1.11 or newer")
    rows = _operation_counters(case, _diagnostic_sample_count(options))
    all(haskey(row, "lock_conflicts") for row in rows) ||
        return Dict("status" => "unavailable",
            "message" => "runtime does not expose lock conflict counters")
    conflicts = sum(row["lock_conflicts"] for row in rows)
    findings = conflicts > 0 ?
               [_analyzer_finding("concurrency.lock_contention",
        "ReentrantLock acquisition waited during the observed operations.";
        evidence = Dict("lock_conflicts" => conflicts, "samples" => length(rows)))] :
               Dict{String, Any}[]
    Dict("status" => "complete", "correctness" => "passed", "findings" => findings,
        "measurements" => Dict("samples" => rows),
        "limitations" => [
            "Counts do not measure blocked duration or prove a scalability bottleneck.",
            "Only runtime-reported lock conflicts are covered; native locks and device barriers are not."])
end

function _memory_point()
    Dict(k => v
    for (k, v) in process_memory_snapshot_dict(process_memory_snapshot()) if v !== nothing)
end

function _analyze_scenario(::Val{:memory}, case, options)
    threshold = get(options, "memory_growth_threshold_bytes", 1_048_576)
    threshold isa Integer && threshold >= 0 ||
        throw(ArgumentError("invalid memory growth threshold"))
    rows = Dict{String, Any}[]
    for _ in 1:_diagnostic_sample_count(options)
        evaluation = SharedScenarioRuntime.prepare(case)
        try
            before_size = Base.summarysize(evaluation.state)
            before = _memory_point()
            SharedScenarioRuntime.operation!(evaluation)
            after = _memory_point()
            SharedScenarioRuntime.verify!(evaluation)
            push!(rows,
                Dict("state_before_bytes" => before_size,
                    "state_after_bytes" => Base.summarysize(evaluation.state),
                    "state_and_result_bytes" => Base.summarysize((
                        evaluation.state, evaluation.result[])),
                    "process_before" => before, "process_after" => after))
        finally
            SharedScenarioRuntime.cleanup!(evaluation)
        end
    end
    growth = [row["state_after_bytes"] - row["state_before_bytes"] for row in rows]
    findings = all(>(threshold), growth) ?
               [_analyzer_finding("memory.state_growth",
        "Reachable scenario state grew on every observed fresh-state evaluation.";
        evidence = Dict("growth_bytes" => growth, "threshold_bytes" => threshold))] :
               Dict{String, Any}[]
    Dict("status" => "complete", "correctness" => "passed", "findings" => findings,
        "measurements" => Dict("samples" => rows),
        "limitations" => [
            "Reachable state growth may be an intended result or cache, not a leak.",
            "Process memory includes Julia, allocator retention and unrelated tasks; two points do not measure an operation peak.",
            "State and result are traversed together to avoid double-counting shared Julia objects; native/device allocations require their own provider."])
end

function _diagnostic_summary(record)
    get(record, "status", "") == "complete" || return get(record, "message", "")
    tool = get(record, "tool", "")
    rows = get(get(record, "measurements", Dict()), "samples", [])
    if tool == "gc" && !isempty(rows)
        seconds = sum(r["gc_seconds"] for r in rows)
        allocated = sum(r["allocated_bytes"] for r in rows)
        return "$(length(rows)) operations: $(round(seconds * 1000; digits=3)) ms in GC, $allocated allocated bytes in total. Diagnostic counters are process-wide."
    elseif tool == "locks" && !isempty(rows)
        conflicts = sum(r["lock_conflicts"] for r in rows)
        return "$(length(rows)) operations: $conflicts observed lock conflicts. Counts do not measure waiting duration."
    elseif tool == "memory" && !isempty(rows)
        growth = [r["state_after_bytes"] - r["state_before_bytes"] for r in rows]
        return "$(length(rows)) operations: reachable state changed by $(minimum(growth)) to $(maximum(growth)) bytes. Growth may be intended output or a cache; it does not establish a leak."
    elseif tool == "heap"
        return "Redacted heap snapshot captured after verification. Covers GC-managed objects in the whole worker; native and device memory are excluded."
    end
    get(record, "message", "")
end

function _analyze_scenario(::Val{:heap}, case, options)
    destination = get(options, "artifact_dir", nothing)
    destination === nothing && return Dict("status" => "unavailable",
        "message" => "heap snapshots require a report directory (diagnose(...; reports=...) or --reports)")
    isdefined(Profile, :take_heap_snapshot) || return Dict("status" => "unavailable",
        "message" => "heap snapshots are not supported by this Julia runtime")
    hasmethod(Profile.take_heap_snapshot, Tuple{String}, (:redact_data,)) ||
        return Dict("status" => "unavailable",
            "message" => "runtime does not support redacted heap snapshots")
    directory = abspath(destination)
    mkpath(directory)
    path = joinpath(directory, "after-operation.heapsnapshot")
    ispath(path) && throw(ArgumentError("snapshot output already exists"))
    evaluation = SharedScenarioRuntime.prepare(case)
    try
        SharedScenarioRuntime.operation!(evaluation)
        SharedScenarioRuntime.verify!(evaluation)
        # The state/result remain rooted until cleanup; snapshotting is outside operation timing.
        GC.@preserve evaluation Profile.take_heap_snapshot(path; redact_data = true)
    finally
        SharedScenarioRuntime.cleanup!(evaluation)
    end
    Dict("status" => "complete", "correctness" => "passed",
        "findings" => Dict{String, Any}[],
        "artifacts" => [Dict("kind" => "heap_snapshot", "path" => path,
            "sha256" => bytes2hex(open(SHA.sha256, path)), "bytes" => filesize(path), "redacted" => true)],
        "limitations" => [
            "Snapshot covers the entire diagnostic process, not just the scenario.",
            "Only GC-managed memory is represented; native and device memory are excluded.",
            "Snapshot capture is intrusive and its duration is not baseline performance evidence."])
end
