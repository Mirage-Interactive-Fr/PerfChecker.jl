using Test
using PerfChecker
using PerfCheckerLinuxPerf
import Pkg

const fixture = joinpath(@__DIR__, "fixtures", "CounterFixture")
const source = joinpath(@__DIR__, "fixtures", "workload.jl")
const environment = dirname(Base.active_project())

@testset "Native LinuxPerf availability and descriptor cleanup" begin
    @test PerfCheckerLinuxPerf._abi_unavailable_reason(:riscv64) ==
          "unsupported_architecture"
    @test PerfCheckerLinuxPerf._abi_unavailable_reason(:arm) == "unsupported_architecture"
    @test PerfCheckerLinuxPerf._abi_unavailable_reason(:powerpc64le) ==
          "unsupported_architecture"
    if Sys.islinux()
        @test PerfCheckerLinuxPerf._abi_unavailable_reason() === nothing
    end
    @test all(name -> haskey(PerfCheckerLinuxPerf.LinuxPerf.NAME_TO_EVENT, name),
        PerfCheckerLinuxPerf._EVENTS)
    for event in PerfCheckerLinuxPerf._EVENTS
        calls = Ref(0)
        result = measure_counters(() -> (calls[] += 1); events = [event])
        @test result.status in (:complete, :unavailable)
        @test calls[] ==
              (result.status == :complete || result.reason == "counter_not_scheduled" ? 1 :
               0)
    end
    calls = Ref(0)
    observed = measure_counters(() -> (calls[] += 1))
    @test observed.allowed_cpuids ==
          (observed.thread_id == 0 ? Int[] : PerfCheckerLinuxPerf._allowed_cpuids())
    if observed.status == :unavailable
        after_operation = observed.reason == "counter_not_scheduled"
        @test calls[] == (after_operation ? 1 : 0)
        @test isempty(observed.records)
        @test observed.reason in (
            "permission_denied", "event_unavailable", "unsupported_platform",
            "unsupported_architecture", "unsupported_syscall_abi",
            "unsupported_attribute_abi", "unsupported_read_abi", "unsupported_byte_order",
            "counter_not_scheduled")
        if after_operation
            @test isempty(counter_bundle(observed).observations)
        elseif Sys.islinux()
            before = length(readdir("/proc/self/fd"))
            for _ in 1:10
                retry = measure_counters(() -> error("unavailable callback must not run"))
                @test retry.status == :unavailable
                @test isempty(retry.records)
            end
            @test length(readdir("/proc/self/fd")) == before
        end
        @info "Native positive counters not qualified: $(observed.reason)"
    else
        @test observed.status == :complete
        @test calls[] == 1
        @test all(
            record -> record.running_ns > 0 && record.enabled_ns >= record.running_ns,
            observed.records)
        @test any(record -> record.value > 0, observed.records)
        streams, leader = PerfCheckerLinuxPerf._open_group(["instructions", "cpu-cycles"])
        try
            @test all(
                stream -> (ccall(:fcntl, Cint, (Cint, Cint), Base.fd(stream), 1) & 1) != 0,
                streams)
        finally
            PerfCheckerLinuxPerf._close_streams(streams)
        end
        @test_throws ErrorException measure_counters(() -> error("callback failure"))
    end
    @test_throws ArgumentError measure_counters(() -> nothing; events = [])
    @test_throws ArgumentError measure_counters(
        () -> nothing; events = ["cpu-cycles", "cpu-cycles"])
    @test_throws ArgumentError measure_counters(() -> nothing; events = ["unknown-event"])
end

@testset "Raw precision, units and portable evidence" begin
    exact = typemax(UInt64)
    result = CounterResult(:complete, "",
        [CounterRecord("cpu-cycles", exact, exact, exact),
            CounterRecord("instructions", UInt64(2)^53 - 1, 10, 9)], 1, [16, 17])
    bundle = counter_bundle(result)
    @test length(bundle.observations) == 1
    @test only(bundle.observations)["value"] == UInt64(2)^53 - 1
    @test all(definition -> definition["unit"] == "1", bundle.measurement_definitions)
    @test first(bundle.diagnostics)["evidence"]["records"][1]["raw_value"] == string(exact)
    @test first(bundle.diagnostics)["evidence"]["records"][1]["enabled_ns"] == string(exact)
    @test any(item -> item["rule_id"] == "hardware.counter.numeric_projection_unavailable",
        bundle.diagnostics)
    # Project declared raw fixtures through the executor's actual success path;
    # this is not a claim that this host permits a native counter capture.
    qualification = PerfChecker._empty_qualification(; correctness = "passed")
    push!(bundle.diagnostics,
        Dict{String, Any}("rule_id" => "hardware.counter.qualification",
            "severity" => "info", "message" => "Declared fixture qualification",
            "evidence" => qualification))
    checker = PerfCheckerLinuxPerf._counter_checker_result(bundle, [:projection])
    @test checker isa PerfChecker.CheckerResult
    @test checker.tags == [:projection]
    @test only(only(checker.tables).counter_records) == bundle.observations
    @test only(checker.qualifications)["correctness"] == qualification["correctness"]
    @test only(checker.qualifications)["counter_bundle"] ==
          PerfCheckerLinuxPerf._payload(bundle)
    @test !haskey(qualification, "counter_bundle")
    mktempdir() do directory
        write_run_bundle(bundle, joinpath(directory, "raw"))
        restored = read_run_bundle(joinpath(directory, "raw"))
        @test first(restored.diagnostics)["evidence"]["records"][1]["raw_value"] ==
              string(exact)
    end
    unavailable = counter_bundle(CounterResult(
        :unavailable, "permission_denied", CounterRecord[], 1, [16, 17]))
    @test unavailable.manifest["state"] == "unavailable"
    @test isempty(unavailable.observations)
    @test_throws PerfCheckerLinuxPerf.CounterUnavailable PerfCheckerLinuxPerf._counter_checker_result(
        unavailable, [:projection])
    @test_throws ArgumentError counter_bundle(CounterResult(
        :complete, "", CounterRecord[], 1, [16, 17]))
    @test PerfCheckerLinuxPerf._checked_call(() -> false)["status"] == "failed"
    @test PerfCheckerLinuxPerf._checked_call(() -> error("oracle exception"))["status"] ==
          "failed"
end

@testset "Declared PerfChecker plan and genuine isolated worker" begin
    Pkg.develop(Pkg.PackageSpec(path = fixture))
    feature = FeatureSpec(:counters; backend = :linuxperf, entrypoint = source,
        oracle = OracleSpec(), options = Dict(:counter_environment => environment,
            :events => ["instructions", "cpu-cycles"]))
    package = PackageSuite("CounterFixture"; worker_environment = environment,
        source = fixture, versions = [v"1.2.3"], features = [feature])
    suite = SoftwareSuite(:counter_test, [package])
    plan = plan_suite(suite; profile = :quick)
    @test length(plan.runs) == 1
    @test only(plan.runs).feature.backend == :linuxperf
    mktempdir() do directory
        lifecycle = joinpath(directory, "lifecycle.txt")
        result = withenv("COUNTER_LIFECYCLE_FILE" => lifecycle) do
            run_counter_suite(plan)
        end
        run = only(result.runs)
        @test run.status in (:pass, :unavailable)
        @test haskey(run.qualification, "environment_provenance")
        @test haskey(run.qualification, "source_provenance")
        evidence = run.qualification["counter_bundle"]
        @test evidence["runtime"]["backend_version"] == "0.4.2"
        @test evidence["case_id"] == "counter_test/CounterFixture/counters"
        trace = readlines(lifecycle)
        after_operation = any(
            item -> get(item, "rule_id", "") == "hardware.counter.raw" &&
                get(item, "message", "") == "counter_not_scheduled",
            evidence["diagnostics"])
        if run.status == :unavailable
            @test evidence["state"] == "unavailable"
            @test isempty(evidence["observations"])
            @test trace == (after_operation ?
                   ["prepare", "operation", "synchronize", "oracle", "cleanup"] :
                   ["prepare", "cleanup"])
            @test run.qualification["correctness"]["status"] ==
                  (after_operation ? "passed" : "not_checked")
            @test suite_verdict(result) == :partially_executed
        else
            @test trace == ["prepare", "operation", "synchronize", "oracle", "cleanup"]
            @test run.qualification["correctness"]["status"] == "passed"
            @test !isempty(evidence["observations"])
            rm(lifecycle)
            invalid = withenv(
                "COUNTER_LIFECYCLE_FILE" => lifecycle, "COUNTER_ORACLE_FALSE" => "true") do
                run_counter_suite(plan)
            end
            @test only(invalid.runs).status == :invalid
            @test count(==("operation"), readlines(lifecycle)) == 1
        end
        paths = write_suite_reports(result, joinpath(directory, "reports");
            formats = (:json, :markdown, :junit, :bundle))
        @test all(ispath, paths)
        saved = PerfCheckerLinuxPerf.JSON.parsefile(joinpath(
            directory, "reports", "suite-result.json"))
        @test occursin("counter_bundle", string(saved))
        received = RunBundle[]
        terminal = run_suite_repl(plan;
            executor = counter_executor(
                bundle_sink = (planned, bundle) -> push!(received, bundle)),
            strict = false, interactive = false, output = IOBuffer())
        @test length(received) == 1
        terminal_status = only(terminal.runs).status
        @test terminal_status in (:pass, :unavailable)
        if run.status == :unavailable && !after_operation
            @test terminal_status == :unavailable
        end
        if terminal_status == :unavailable
            @test only(received).manifest["state"] == "unavailable"
            @test isempty(only(received).observations)
        else
            @test only(terminal.runs).qualification["correctness"]["status"] == "passed"
        end
        mismatch = counter_command(:wrong_target; source, environment,
            package = "CounterFixture", target_kind = :release, target_version = v"99")
        rm(lifecycle)
        refused = withenv("COUNTER_LIFECYCLE_FILE" => lifecycle) do
            run_external_command(mismatch)
        end
        @test refused.manifest["state"] == "unavailable"
        @test !isfile(lifecycle)
        @test isempty(refused.observations)
        changed = counter_command(:changed; source, environment,
            package = "CounterFixture", target_kind = :dev, target_version = v"1.2.3", target_source = fixture)
        request = PerfCheckerLinuxPerf.JSON.parse(last(changed.command))
        request["source_sha256"] = repeat("0", 64)
        changed.command[end] = PerfCheckerLinuxPerf.JSON.json(request)
        rejected = withenv("COUNTER_LIFECYCLE_FILE" => lifecycle) do
            run_external_command(changed)
        end
        @test rejected.manifest["state"] == "unavailable"
        @test any(
            record -> occursin("source changed", record["message"]), rejected.diagnostics)
        @test !isfile(lifecycle)
        pin = counter_command(:bad_pin; source, environment,
            package = "CounterFixture", target_kind = :dev, target_version = v"1.2.3", target_source = fixture,
            pins = [Dict("name" => "LinuxPerf", "version" => "99.0.0")])
        pinned = run_external_command(pin)
        @test pinned.manifest["state"] == "unavailable"
        @test any(record -> occursin("release pin", record["message"]), pinned.diagnostics)
    end
end
