@testitem "Memory, GC and lock evidence preserve lifecycle and limits" tags=[:memory_diagnostics] begin
    using PerfChecker
    closed = Ref(0)
    growing = (prepare = () -> Int[], operation = x -> (append!(x, 1:4096); x),
        verify = (x, r) -> x === r && length(x) == 4096, cleanup = x -> (closed[] += 1))
    options = Dict("diagnostic_samples" => 2, "memory_growth_threshold_bytes" => 128)
    result = PerfChecker._analyze_scenario(Val(:memory), growing, options)
    @test closed[] == 2
    @test only(result["findings"])["rule_id"] == "memory.state_growth"
    @test all(r["state_after_bytes"] > r["state_before_bytes"]
    for r in result["measurements"]["samples"])
    @test all(haskey(r["process_before"], "status")
    for r in result["measurements"]["samples"])
    healthy = (prepare = () -> 42, operation = identity,
        verify = (x, r) -> x == r, cleanup = identity)
    @test isempty(PerfChecker._analyze_scenario(Val(:memory), healthy, options)["findings"])
    @test_throws ArgumentError PerfChecker._analyze_scenario(
        Val(:gc), healthy, Dict("diagnostic_samples" => 0))
    failed = merge(growing, (verify = (x, r) -> false,))
    @test_throws PerfChecker.SharedScenarioRuntime.ScenarioFailure PerfChecker._analyze_scenario(
        Val(:gc), failed, options)
    @test closed[] == 3
    collecting = merge(healthy, (operation = x -> (GC.gc(); x),))
    gc = PerfChecker._analyze_scenario(Val(:gc), collecting, options)
    @test any(f["rule_id"] == "memory.gc_pressure" for f in gc["findings"])
    locked = (prepare = () -> ReentrantLock(),
        operation = l -> begin
            lock(l)
            task = @async lock(() -> 1, l)
            yield()
            unlock(l)
            fetch(task)
        end,
        verify = (l, r) -> r == 1, cleanup = identity)
    locks = PerfChecker._analyze_scenario(Val(:locks), locked, options)
    if VERSION >= v"1.11"
        @test any(f["rule_id"] == "concurrency.lock_contention" for f in locks["findings"])
    else
        @test locks["status"] == "unavailable"
    end
    result["scenario"], result["implementation"], result["tool"] = "growing", "cpu",
    "memory"
    advice = advise(Dict(
        "schema_version" => "perfchecker-diagnosis/1", "records" => [result]))
    @test only(advice["recommendations"])["rule_id"] == "memory.state_growth"
    @test Set(["gc", "memory", "heap", "locks"]) ⊆
          Set(t["tool"] for t in diagnostic_capabilities())
    @test haskey(tool_catalog(), "analyzers")
    summary = PerfChecker._diagnostic_summary(result)
    @test occursin("does not establish a leak", summary)
    result["summary"] = summary
    payload = Dict("schema_version" => "perfchecker-diagnosis/1", "records" => [result])
    @test occursin(summary, sprint(show, MIME"text/plain"(), investigation_view(payload)))
end

@testitem "Heap artifact is explicit, redacted and retained after cleanup" tags=[
    :memory_diagnostics, :heap] begin
    using PerfChecker
    closed = Ref(0)
    case = (prepare = () -> collect(1:32), operation = identity,
        verify = (x, r) -> x === r, cleanup = x -> (closed[] += 1))
    @test PerfChecker._analyze_scenario(Val(:heap), case, Dict())["status"] == "unavailable"
    mktempdir() do directory
        report = PerfChecker._analyze_scenario(
            Val(:heap), case, Dict("artifact_dir" => directory))
        if report["status"] == "complete"
            artifact = only(report["artifacts"])
            @test isfile(artifact["path"])
            @test artifact["redacted"] && artifact["bytes"] > 0
            @test closed[] == 1
            @test_throws ArgumentError PerfChecker._analyze_scenario(
                Val(:heap), case, Dict("artifact_dir" => directory))
        else
            @test report["status"] == "unavailable"
        end
    end
end
