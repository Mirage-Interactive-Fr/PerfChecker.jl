# Run as a standalone process: the legacy suite contract intentionally defines Main callbacks.
using Test, PerfChecker, BenchmarkTools, Chairmarks, Profile

const prepared = Ref(0)
const cleaned = Ref(0)
const active = Ref(0)
const peak = Ref(0)
const last_owner = Ref(WeakRef(nothing))
function perf_setup()
    prepared[] += 1
    active[] += 1
    peak[] = max(peak[], active[])
    owner = [3, 1, 2]
    last_owner[] = WeakRef(owner)
    return owner
end
perf_workload(x) = (x == [3, 1, 2] || error("mutable state reused"); sort!(x))
perf_oracle(x, result) = x === result && x == [1, 2, 3]
perf_cleanup(x) = (cleaned[] += 1; active[] -= 1)
perf_oracle_throws(x, result) = error("qualification oracle failure")
perf_probe_throws(x) = error("qualification probe failure")
perf_reuse_oracle(x) = x == [1, 2, 3]

@testset "Fresh state in legacy suite collectors" begin
    for collector in (:benchmark, :chairmark, :profile_alloc)
        options = merge(PerfChecker.default_options(Val(collector)),
            Dict(
                :fresh_feature => true, :feature_oracle => "perf_oracle",
                :samples => 3, :seconds => 0.1, :targets => ["PerfChecker"],
                :profile_repetitions => 2))
        prepared[] = cleaned[] = active[] = peak[] = 0
        expression = PerfChecker.check(
            options, :(error("old state path used")), Val(collector))
        result = Core.eval(Main, :(let
            $expression
        end))
        @test prepared[] >= 3
        @test prepared[] == cleaned[]
        @test active[] == 0
        @test peak[] == 1
        @test !isempty(PerfChecker.to_table(result))
    end
    mktempdir() do directory
        source = joinpath(directory, "case.jl")
        write(source, "# callbacks already installed above\n")
        feature = FeatureSpec(:mutable; entrypoint = source, oracle = OracleSpec())
        package = PackageSuite("SharedScenarioDemo";
            source = joinpath(pkgdir(PerfChecker), "examples", "shared-scenarios"),
            environment = joinpath(pkgdir(PerfChecker), "examples", "shared-scenarios"),
            versions = VersionNumber[], features = [feature])
        plan = plan_suite(SoftwareSuite(:legacy, [package]))
        planned = only(plan.runs)
        configuration = PerfChecker._run_config(planned, Dict())
        @test configuration.options[:fresh_feature]
        @test configuration.options[:evals] == 1
        @test_throws ArgumentError PerfChecker._run_config(planned, Dict(:evals => 2))
        @test !get(PerfChecker._run_config(planned, Dict(:state_policy => :reuse)).options,
            :fresh_feature, false)
        global d = configuration.options
        setup, _, qualification = PerfChecker._feature_blocks(planned)
        prepared[] = cleaned[] = active[] = peak[] = 0
        Core.eval(Main, setup)
        @test prepared[] == active[] == 0
        # Match check_function's actual order: setup, qualification, measurement.
        # Cleanup already ran before measurement in the previous implementation;
        # the regression is the global constant retaining that closed owner.
        evidence = Core.eval(Main, qualification)
        @test evidence["correctness"]["status"] == "passed"
        @test prepared[] == cleaned[] == 1
        @test active[] == 0
        qualified_owner = last_owner[]
        GC.gc()
        @test qualified_owner.value === nothing

        shared = (; prepare = perf_setup, operation = perf_workload,
            verify = perf_oracle, cleanup = perf_cleanup)
        for _ in 1:3
            Main.SharedScenarioRuntime.once(shared)
            @test active[] == 0
        end
        @test prepared[] == cleaned[] == 4
        @test active[] == 0
        @test peak[] == 1

        for (id, probes, oracle) in (
            (:oracle_error, ProbeSpec[], OracleSpec(function_name = :perf_oracle_throws)),
            (:probe_error, [ProbeSpec(:throws; function_name = :perf_probe_throws)], OracleSpec()),
            (:missing_probe, [ProbeSpec(:missing; function_name = :perf_missing_probe)], OracleSpec()),
        )
            candidate = FeatureSpec(id; entrypoint = source, probes, oracle)
            candidate_package = PackageSuite("SharedScenarioDemo";
                source = package.source, environment = package.worker_environment,
                versions = VersionNumber[], features = [candidate])
            candidate_run = only(plan_suite(SoftwareSuite(id, [candidate_package])).runs)
            global d = PerfChecker._run_config(candidate_run, Dict()).options
            candidate_setup, _, candidate_qualification = PerfChecker._feature_blocks(candidate_run)
            prepared[] = cleaned[] = active[] = peak[] = 0
            Core.eval(Main, candidate_setup)
            @test prepared[] == active[] == 0
            failure = Core.eval(Main, candidate_qualification)
            @test prepared[] == cleaned[] == 1
            @test active[] == 0
            @test peak[] == 1
            GC.gc()
            @test last_owner[].value === nothing
            if id == :oracle_error
                @test failure["correctness"]["status"] == "failed"
            else
                @test only(failure["probes"])["status"] == (id == :missing_probe ? "unavailable" : "failed")
            end
        end

        reused = FeatureSpec(:shared_reuse; entrypoint = source,
            oracle = OracleSpec(function_name = :perf_reuse_oracle), state_policy = :reuse)
        reused_package = PackageSuite("SharedScenarioDemo";
            source = package.source, environment = package.worker_environment,
            versions = VersionNumber[], features = [reused])
        reused_run = only(plan_suite(SoftwareSuite(:shared_reuse, [reused_package])).runs)
        global d = PerfChecker._run_config(reused_run, Dict()).options
        reused_setup, reused_workload, reused_qualification = PerfChecker._feature_blocks(reused_run)
        prepared[] = cleaned[] = active[] = peak[] = 0
        Core.eval(Main, reused_setup)
        @test prepared[] == active[] == 1
        observed = Core.eval(Main, reused_workload)
        @test observed == [1, 2, 3]
        reused_evidence = Core.eval(Main, reused_qualification)
        @test reused_evidence["correctness"]["status"] == "passed"
        @test prepared[] == 1
        @test cleaned[] == 0
        @test active[] == peak[] == 1
        @test last_owner[].value === observed
        perf_cleanup(observed)
        @test prepared[] == cleaned[] == 1
        @test active[] == 0
    end
end
