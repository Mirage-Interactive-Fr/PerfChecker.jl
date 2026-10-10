using Test
using PerfChecker
using PerfCheckerLIKWID
import LIKWID
import Pkg

const event_set = "INSTR_RETIRED_ANY:FIXC0,CPU_CLK_UNHALTED_CORE:FIXC1"
const units = Dict("INSTR_RETIRED_ANY" => "1", "CPU_CLK_UNHALTED_CORE" => "1")
const allowed = PerfCheckerLIKWID._allowed_cpuids()
const cpus = isempty(allowed) ? [0] : [first(allowed)]
const environment = dirname(Base.active_project())
const fixture = joinpath(@__DIR__, "fixtures", "CounterFixture")
const source = joinpath(@__DIR__, "fixtures", "workload.jl")

@testset "Inherited affinity, exact declarations and actual library refusal" begin
    if Sys.islinux()
        foreign_cpu = first(cpu for cpu in 0:(maximum(allowed) + 1) if !(cpu in allowed))
        @test_throws ArgumentError measure_counters(() -> error("must not run");
            event_set, units, cpuids = [foreign_cpu])
    end
    @test_throws ArgumentError measure_counters(
        () -> nothing; event_set, units, cpuids = [true])
    @test_throws ArgumentError measure_counters(
        () -> nothing; event_set, units, cpuids = vcat(cpus, cpus))
    @test_throws ArgumentError measure_counters(
        () -> nothing; event_set = "FLOPS_DP", units, cpuids = cpus)
    @test_throws ArgumentError measure_counters(
        () -> nothing; event_set = "UNC_M_CAS_COUNT_RD:MBOX0C0",
        units = Dict("UNC_M_CAS_COUNT_RD" => "1"), cpuids = cpus)
    @test_throws ArgumentError measure_counters(
        () -> nothing; event_set, units = Dict("wrong" => "1"), cpuids = cpus)
    @test_throws ArgumentError measure_counters(() -> nothing; event_set,
        units = Dict("INSTR_RETIRED_ANY" => "1", "CPU_CLK_UNHALTED_CORE" => "s"), cpuids = cpus)
    if Sys.islinux()
        original_pid = get(ENV, "LIKWID_PERF_PID", nothing)
        withenv("LIKWID_PERF_PID" => string(getpid() + 1)) do
            called = Ref(false)
            refused = measure_counters(
                () -> (called[] = true); event_set, units, cpuids = cpus)
            @test refused.status == :unavailable
            @test refused.reason == "foreign_or_invalid_perf_pid"
            @test isempty(refused.records)
            @test !called[]
        end
        @test get(ENV, "LIKWID_PERF_PID", nothing) == original_pid
    end
    before = copy(allowed)
    called = Ref(0)
    observed = measure_counters(() -> (called[] += 1); event_set, units, cpuids = cpus)
    @test PerfCheckerLIKWID._allowed_cpuids() == before
    @test observed.allowed_cpuids == before
    @test observed.cpuids == cpus
    if observed.status == :unavailable
        @test called[] == 0
        @test isempty(observed.records)
        @test observed.reason in (
            "library_unavailable", "unsupported_platform", "initialization_refused",
            "event_set_refused", "setup_refused", "start_refused",
            "event_identity_changed", "event_set_changed", "access_mode_unknown")
        @info "Native positive LIKWID counters not qualified: $(observed.reason)"
    else
        @test observed.status == :complete
        @test called[] == 1
        @test all(record -> isfinite(record.value), observed.records)
        @test observed.group_time_seconds isa Float64
        @test !LIKWID.PerfMon.isinitialized()
        @test_throws ErrorException measure_counters(() -> error("callback failure");
            event_set, units, cpuids = cpus)
        @test !LIKWID.PerfMon.isinitialized()
    end
end

@testset "Raw Float64 semantics and explicit absent times" begin
    raw = Float64(2)^54
    record = CounterRecord("CPU_CLK_UNHALTED_CORE", "FIXC1", first(cpus), "1", raw)
    result = CounterResult(
        :complete, "", [record], isempty(allowed) ? cpus : allowed, cpus, 0.25)
    bundle = counter_bundle(result)
    observation = only(bundle.observations)
    @test observation["value"] === raw
    @test observation["unit"] == "1"
    @test observation["scope"] == "selected_cpu_backend_window"
    @test observation["attributes"]["raw_encoding"] == "backend_float64"
    @test !observation["attributes"]["exact_integer_count"]
    @test observation["attributes"]["enabled_ns"] === nothing
    @test observation["attributes"]["running_ns"] === nothing
    @test observation["attributes"]["group_time_seconds"] == 0.25
    @test observation["attributes"]["unit_source"] == "caller_declaration"
    @test observation["attributes"]["access_mode"] == "not_recorded"
    @test observation["attributes"]["backend_perf_pid"] === nothing
    @test observation["attributes"]["native_library_version"] === nothing
    changed_mode = counter_bundle(CounterResult(:complete, "", [record],
        isempty(allowed) ? cpus : allowed, cpus, 0.25, "ACCESSMODE_PERF", getpid()))
    @test only(changed_mode.observations)["measurement_definition"] !=
          observation["measurement_definition"]
    @test !observation["attributes"]["autopin"]
    # Project declared raw fixtures through the executor's actual success path;
    # this is not a claim that this host permits a native counter capture.
    qualification = PerfChecker._empty_qualification(; correctness = "passed")
    push!(bundle.diagnostics,
        Dict{String, Any}("rule_id" => "hardware.counter.qualification",
            "severity" => "info", "message" => "Declared fixture qualification",
            "evidence" => qualification))
    checker = PerfCheckerLIKWID._counter_checker_result(bundle, [:projection])
    @test checker isa PerfChecker.CheckerResult
    @test checker.tags == [:projection]
    @test only(only(checker.tables).counter_records) == bundle.observations
    @test only(checker.qualifications)["correctness"] == qualification["correctness"]
    @test only(checker.qualifications)["counter_bundle"] ==
          PerfCheckerLIKWID._payload(bundle)
    @test !haskey(qualification, "counter_bundle")
    mktempdir() do directory
        write_run_bundle(bundle, joinpath(directory, "raw"))
        restored = read_run_bundle(joinpath(directory, "raw"))
        @test only(restored.observations)["value"] == raw
        @test only(restored.observations)["attributes"]["enabled_ns"] === nothing
    end
    unavailable = counter_bundle(CounterResult(
        :unavailable, "library_unavailable", CounterRecord[], allowed, cpus, nothing))
    @test unavailable.manifest["state"] == "unavailable"
    @test isempty(unavailable.observations)
    @test_throws PerfCheckerLIKWID.CounterUnavailable PerfCheckerLIKWID._counter_checker_result(
        unavailable, [:projection])
    @test_throws ArgumentError counter_bundle(CounterResult(
        :complete, "", CounterRecord[], allowed, cpus, nothing))
    @test PerfCheckerLIKWID._checked_call(() -> false)["status"] == "failed"
    @test PerfCheckerLIKWID._checked_call(() -> error("oracle exception"))["status"] ==
          "failed"
end

@testset "Declared plan and genuine isolated PerfChecker provider" begin
    Pkg.develop(Pkg.PackageSpec(path = fixture))
    feature = FeatureSpec(:counters; backend = :likwid, entrypoint = source,
        oracle = OracleSpec(), options = Dict(:counter_environment => environment,
            :event_set => event_set, :cpuids => cpus, :units => units))
    package = PackageSuite("CounterFixture"; worker_environment = environment,
        source = fixture, versions = [v"1.2.3"], features = [feature])
    plan = plan_suite(SoftwareSuite(:likwid_test, [package]); profile = :quick)
    @test length(plan.runs) == 1
    mktempdir() do directory
        path = joinpath(directory, "lifecycle.txt")
        original_pid = get(ENV, "LIKWID_PERF_PID", nothing)
        result = withenv("COUNTER_LIFECYCLE_FILE" => path, "LIKWID_PERF_PID" => nothing) do
            run_counter_suite(plan)
        end
        @test get(ENV, "LIKWID_PERF_PID", nothing) == original_pid
        run = only(result.runs)
        @test run.status in (:pass, :unavailable)
        bundle = run.qualification["counter_bundle"]
        @test bundle["runtime"]["backend_version"] == "0.4.6"
        @test bundle["case_id"] == "likwid_test/CounterFixture/counters"
        @test haskey(run.qualification, "environment_provenance")
        @test haskey(run.qualification, "source_provenance")
        if run.status == :unavailable
            @test isempty(bundle["observations"])
            @test readlines(path) == ["prepare", "cleanup"]
            @test suite_verdict(result) == :partially_executed
        else
            @test readlines(path) ==
                  ["prepare", "operation", "synchronize", "oracle", "cleanup"]
            @test run.qualification["correctness"]["status"] == "passed"
        end
        paths = write_suite_reports(result, joinpath(directory, "reports");
            formats = (:json, :markdown, :junit, :bundle))
        @test all(ispath, paths)
        saved = PerfCheckerLIKWID.JSON.parsefile(joinpath(
            directory, "reports", "suite-result.json"))
        @test occursin("counter_bundle", string(saved))
        received = RunBundle[]
        terminal = withenv("LIKWID_PERF_PID" => nothing) do
            run_suite_repl(plan;
                executor = counter_executor(
                    bundle_sink = (planned, bundle) -> push!(received, bundle)),
                strict = false, interactive = false, output = IOBuffer())
        end
        @test get(ENV, "LIKWID_PERF_PID", nothing) == original_pid
        @test length(received) == 1
        @test only(terminal.runs).status == run.status
        rm(path)
        if Sys.islinux()
            foreign = withenv("COUNTER_LIFECYCLE_FILE" => path, "LIKWID_PERF_PID" => "0") do
                run_counter_suite(plan)
            end
            @test get(ENV, "LIKWID_PERF_PID", nothing) == original_pid
            @test only(foreign.runs).status == :unavailable
            refused = only(foreign.runs).qualification["counter_bundle"]
            @test isempty(refused["observations"])
            @test any(record -> occursin("foreign_or_invalid_perf_pid", record["message"]),
                refused["diagnostics"])
            @test readlines(path) == ["prepare", "cleanup"]
            rm(path)
        end
        mismatch = counter_command(:wrong; source, environment,
            package = "CounterFixture", target_kind = :release, target_version = v"99",
            event_set, units, cpuids = cpus)
        refused = withenv("COUNTER_LIFECYCLE_FILE" => path) do
            run_external_command(mismatch)
        end
        @test refused.manifest["state"] == "unavailable"
        @test !isfile(path)
        changed = counter_command(:changed; source, environment,
            package = "CounterFixture", target_kind = :dev, target_version = v"1.2.3", target_source = fixture,
            event_set, units, cpuids = cpus)
        request = PerfCheckerLIKWID.JSON.parse(last(changed.command))
        request["environment_project_sha256"] = repeat("0", 64)
        changed.command[end] = PerfCheckerLIKWID.JSON.json(request)
        rejected = withenv("COUNTER_LIFECYCLE_FILE" => path) do
            run_external_command(changed)
        end
        @test rejected.manifest["state"] == "unavailable"
        @test any(record -> occursin("environment changed", record["message"]),
            rejected.diagnostics)
        @test !isfile(path)
    end
end
