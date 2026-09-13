# Run as a standalone process: the legacy suite contract intentionally defines Main callbacks.
using Test, PerfChecker, BenchmarkTools, Chairmarks, Profile

const prepared = Ref(0)
const cleaned = Ref(0)
perf_setup() = (prepared[] += 1; [3, 1, 2])
perf_workload(x) = (x == [3, 1, 2] || error("mutable state reused"); sort!(x))
perf_oracle(x, result) = x === result && x == [1, 2, 3]
perf_cleanup(x) = (cleaned[] += 1)

@testset "Fresh state in legacy suite collectors" begin
    for collector in (:benchmark, :chairmark, :profile_alloc)
        options = merge(PerfChecker.default_options(Val(collector)),
            Dict(
                :fresh_feature => true, :feature_oracle => "perf_oracle",
                :samples => 3, :seconds => 0.1, :targets => ["PerfChecker"],
                :profile_repetitions => 2))
        prepared[] = cleaned[] = 0
        expression = PerfChecker.check(
            options, :(error("old state path used")), Val(collector))
        result = Core.eval(Main, :(let
            $expression
        end))
        @test prepared[] >= 3
        @test prepared[] == cleaned[]
        @test !isempty(PerfChecker.to_table(result))
    end
    mktempdir() do directory
        source = joinpath(directory, "case.jl")
        write(source, "# callbacks already installed above\n")
        feature = FeatureSpec(:mutable; entrypoint = source, oracle = OracleSpec())
        package = PackageSuite("SharedScenarioDemo";
            source = joinpath(pkgdir(PerfChecker), "examples", "shared-scenarios"),
            environment = dirname(Base.active_project()), versions = VersionNumber[], features = [feature])
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
        prepared[] = cleaned[] = 0
        Core.eval(Main, setup)
        evidence = Core.eval(Main, qualification)
        @test evidence["correctness"]["status"] == "passed"
        @test prepared[] == cleaned[] == 1
    end
end
