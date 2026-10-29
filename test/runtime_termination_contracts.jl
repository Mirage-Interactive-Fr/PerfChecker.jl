@testitem "Runtime campaign requires explicit reaped termination" tags=[
    :unit, :runtime, :runtime_termination] begin
    using PerfChecker

    passed = Dict{String, Any}("status" => "passed", "exit_code" => 0,
        "termination_signal" => 0, "termination_mode" => "posix",
        "process_exited" => true, "cleanup_complete" => true,
        "runtime_id" => "fixture", "role" => "baseline", "stdout" => "",
        "stderr" => "", "elapsed_seconds" => 0.0,
        "bundle_path" => "preexisting-bundle")
    campaign(record) = JuliaRuntimeCampaign("termination-contract", "unused", :ci,
        :fixture, "start", "finish", [record], Dict{String, Any}[])
    @test runtime_campaign_passed(campaign(passed))
    @test PerfChecker._runtime_run_passed(passed)

    # An old or manually edited PASS label cannot stand in for an observed
    # process status. In particular, Bool is an Integer in Julia, not an exit code.
    invalid = Tuple{String, Any}[("exit_code", value)
                                 for value in (nothing, false, true, 1, -1)]
    append!(invalid,
        [("termination_signal", value)
         for value in (nothing, false, true, 15, 11, -1)])
    append!(invalid, [("termination_mode", value) for value in (nothing, "", "legacy")])
    append!(invalid, [("process_exited", value) for value in (false, nothing, 1)])
    append!(invalid, [("cleanup_complete", value) for value in (false, nothing, 1)])
    for (key, value) in invalid
        record = merge(passed, Dict{String, Any}(key => value))
        before = deepcopy(record)
        @test !PerfChecker._runtime_run_passed(record)
        @test !runtime_campaign_passed(campaign(record))
        @test !julia_runtime_campaign_dict(campaign(record))["passed"]
        comparison = PerfChecker._runtime_comparison(passed, record;
            relative_limits = Dict(), min_samples = 1,
            sample_statistics = Dict(), default_sample_statistic = nothing)
        @test comparison["status"] == "unavailable"
        @test comparison["passed"] === false
        @test comparison["comparison"] === nothing
        candidate = merge(record, Dict{String, Any}("runtime_id" => "candidate"))
        comparison_record = Dict{String, Any}("baseline_runtime_id" => "fixture",
            "candidate_runtime_id" => "candidate", "passed" => false)
        rejected_campaign = JuliaRuntimeCampaign("rejected", "unused", :ci, :fixture,
            "start", "finish", [passed, candidate], [comparison_record])
        investigation = investigate_julia_regressions(rejected_campaign)
        @test only(investigation.comparisons)["status"] == "unavailable"
        @test isempty(only(investigation.comparisons)["frames"])
        @test isequal(record, before)
    end
    for key in ("exit_code", "termination_signal", "termination_mode",
        "process_exited", "cleanup_complete")
        legacy = copy(passed)
        delete!(legacy, key)
        before = deepcopy(legacy)
        @test !runtime_campaign_passed(campaign(legacy))
        @test isequal(legacy, before)
    end
    windows = merge(passed,
        Dict{String, Any}(
            "termination_mode" => "windows_native", "termination_signal" => nothing))
    @test runtime_campaign_passed(campaign(windows))
    @test !PerfChecker._runtime_run_passed(merge(windows,
        Dict{String, Any}("termination_signal" => 0)))

    execution = (process_exited = true, exit_code = 0, termination_signal = 0,
        termination_mode = "posix", cleanup_complete = true, timed_out = false,
        stdout = "", stderr = "")
    @test PerfChecker._runtime_execution_status(execution, "existing-bundle") == "passed"
    @test PerfChecker._runtime_execution_status(execution, nothing) == "missing_bundle"
    @test PerfChecker._runtime_execution_status(
        merge(execution, (cleanup_complete = false,)), "existing-bundle") == "cleanup_error"
    @test PerfChecker._runtime_execution_status(
        merge(execution, (timed_out = true,)), "existing-bundle") == "timeout"
    @test PerfChecker._runtime_execution_status(
        merge(execution, (termination_signal = nothing,)), "existing-bundle") ==
          "termination_unverified"
    for (signal, kind) in ((Int(Base.SIGTERM), "runtime_signal"),
        (11, "runtime_crash"))
        # Classification of a synthetic SIGSEGV exercises status handling; this
        # test never crashes a process or produces a core dump.
        abnormal = merge(execution, (termination_signal = signal,))
        @test PerfChecker._runtime_execution_status(abnormal, "existing-bundle") == "failed"
        @test PerfChecker._runtime_failure_kind(abnormal) == kind
        @test PerfChecker._runtime_failure_stage(abnormal) == "termination"
        @test occursin("termination_signal=$signal",
            PerfChecker._runtime_failure_summary(abnormal, "failed"))
    end
end

@testitem "A real SIGTERM cannot qualify an existing runtime bundle" tags=[
    :integration, :runtime, :runtime_termination] begin
    using PerfChecker

    if Sys.isunix()
        mktempdir() do directory
            bundle = RunBundle(
                Dict{String, Any}(
                    "schema_version" => "perfchecker-run-bundle/1", "state" => "complete"),
                Dict{String, Any}[], Dict{String, Any}[], Dict{String, Any}[],
                Dict{String, Any}[])
            path = write_run_bundle(bundle, joinpath(directory, "run"))
            @test verify_run_bundle(path; require_integrity = true)["verified"]
            @test PerfChecker._runtime_bundle(directory) == path
            before = read(joinpath(path, "integrity.json"))

            # The shell is the owned provider process, not a helper file. It
            # disables cores and kills itself deterministically, without a timer.
            observation = Ref{Any}(nothing)
            execution = PerfChecker._runtime_process(
                ["/bin/sh", "-c", raw"ulimit -c 0; kill -TERM $$"], 10;
                observation)
            @test observation[] === execution
            @test execution.process_exited === true
            @test execution.cleanup_complete === true
            @test execution.exit_code == 0
            @test execution.termination_signal == Int(Base.SIGTERM)
            @test execution.termination_mode == "posix"
            @test !execution.timed_out
            @test execution.pid isa Integer
            @test PerfChecker._runtime_execution_status(execution, path) == "failed"
            @test PerfChecker._runtime_failure_kind(execution) == "runtime_signal"
            @test PerfChecker._runtime_failure_stage(execution) == "termination"
            probe_marker = joinpath(directory, "unexpected-probe")
            quoted_marker = "'" * replace(probe_marker, "'" => "'\\''") * "'"
            # If a regression reaches probing, this existing executable leaves
            # an intrinsic fixture marker before its deliberately non-Julia
            # output is rejected. Merely returning nothing would not prove the
            # probe was skipped, because probe errors are caught by resume.
            spec = JuliaRuntimeSpec(:fixture, "termination-fixture"; role = :baseline,
                source = :executable, executable = "/bin/sh",
                arguments = ["-c", "printf unexpected-probe > " * quoted_marker])
            for key in ("termination_signal", "termination_mode", "process_exited",
                "cleanup_complete")
                legacy = Dict{String, Any}("runtime_id" => "fixture", "role" => "baseline",
                    "spec" => julia_runtime_spec_dict(spec), "status" => "passed",
                    "exit_code" => 0, "termination_signal" => 0,
                    "termination_mode" => "posix", "process_exited" => true,
                    "cleanup_complete" => true, "bundle_path" => path)
                delete!(legacy, key)
                previous = Dict{String, Any}("suite" => "fixture-suite", "profile" => "ci",
                    "runs" => [legacy])
                snapshot = deepcopy(previous)
                # Rejection occurs before probing a runtime. No benchmark, worker
                # or Julia process is started merely to reject legacy evidence.
                @test PerfChecker._resumable_runtime_run(previous, spec;
                    suite = "fixture-suite", profile = :ci,
                    perfchecker_project = directory) === nothing
                @test !isfile(probe_marker)
                @test isequal(previous, snapshot)
            end
            @test read(joinpath(path, "integrity.json")) == before
            @test verify_run_bundle(path; require_integrity = true)["verified"]
            Sys.islinux() && @test !ispath("/proc/$(execution.pid)")

            normal = PerfChecker._runtime_process(
                ["/bin/sh", "-c",
                    "printf final-stdout; printf final-stderr >&2"], 10)
            @test normal.stdout == "final-stdout"
            @test normal.stderr == "final-stderr"
            @test normal.process_exited === true
            @test normal.cleanup_complete === true
            @test normal.exit_code == 0
            @test normal.termination_signal == 0
            @test PerfChecker._runtime_execution_status(normal, path) == "passed"
            Sys.islinux() && @test !ispath("/proc/$(normal.pid)")
        end
    else
        # POSIX SIGTERM is unavailable here; Windows status is covered by the
        # explicit native-record matrix, not falsely labelled a real signal test.
        @test_skip false
    end
end
