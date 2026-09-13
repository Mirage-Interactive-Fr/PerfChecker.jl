@testitem "Process and external memory contracts" tags=[:unit, :resources] begin
    using PerfChecker

    snapshot = process_memory_snapshot()
    @test snapshot.schema_version == "perfchecker-process-memory/1"
    @test snapshot.pid == getpid()
    @test snapshot.status in (:observed, :unavailable)
    if Sys.iswindows() || Sys.islinux()
        @test snapshot.status == :observed
        @test snapshot.rss_bytes isa UInt64
        @test snapshot.peak_rss_bytes isa UInt64
        @test snapshot.peak_rss_bytes >= snapshot.rss_bytes
    end

    before = PerfChecker.ProcessMemorySnapshot(7, 1; rss_bytes = 100,
        peak_rss_bytes = 120, private_bytes = 80)
    after = PerfChecker.ProcessMemorySnapshot(7, 2; rss_bytes = 140,
        peak_rss_bytes = 160, private_bytes = 90)
    external_before = external_memory_snapshot((;
        schema_version = "perfchecker-external-memory/1", live_bytes = 0,
        reserved_bytes = 128, allocated_bytes_total = 64, freed_bytes_total = 64))
    external_after = external_memory_snapshot(Dict(
        "schema_version" => "perfchecker-external-memory/1", "live_bytes" => 32,
        "reserved_bytes" => 128, "allocated_bytes_total" => 96,
        "freed_bytes_total" => 64))
    envelope = PerfChecker.ResourceEnvelope(0.25, before, after,
        external_before, external_after; external_requested = true)
    metrics = resource_envelope_metrics(envelope)
    @test metrics[:rss_delta_bytes] == 40
    @test metrics[:new_peak_rss_bytes] == 40
    @test metrics[:external_live_delta_bytes] == 32
    @test metrics[:external_allocated_delta_bytes] == 32
    @test metrics[:external_freed_delta_bytes] == 0
    @test resource_envelope_dict(envelope)["external_requested"]
    failed = evaluate_resource_envelope(envelope;
        upper_limits = Dict(:external_live_delta_bytes => 0),
        require_external = true, require_external_balance = true)
    @test !resource_policy_passed(failed)
    @test failed["status"] == "failed"
    @test length(failed["violations"]) == 3
    passed = evaluate_resource_envelope(
        PerfChecker.ResourceEnvelope(0.25, before,
            after, external_before, external_before; external_requested = true);
        upper_limits = Dict(:external_live_delta_bytes => 0),
        require_external = true, require_external_balance = true)
    @test resource_policy_passed(passed)
    external_overfreed = external_memory_snapshot((;
        schema_version = "perfchecker-external-memory/1", live_bytes = 0,
        reserved_bytes = 128, allocated_bytes_total = 96,
        freed_bytes_total = 128, provider = "fixture"))
    overfreed = evaluate_resource_envelope(
        PerfChecker.ResourceEnvelope(0.25, before, after,
            external_before, external_overfreed; external_requested = true);
        require_external = true, require_external_balance = true)
    @test overfreed["status"] == "failed"
    @test any(occursin("unbalanced", violation)
    for violation in overfreed["violations"])
    @test_throws ArgumentError evaluate_resource_envelope(envelope;
        upper_limits = Dict(:imaginary_bytes => 0))
    @test_throws ArgumentError evaluate_resource_envelope(envelope;
        upper_limits = Dict(:rss_delta_bytes => true))
    @test_throws ArgumentError external_memory_snapshot((; live_bytes = 1))
end
