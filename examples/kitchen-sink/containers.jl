using PerfChecker, BenchmarkTools, Chairmarks, Test
include(joinpath(@__DIR__, "containers-suite.jl"))
include(joinpath(@__DIR__, "history.jl"))
mode = isempty(ARGS) ? "plan" : ARGS[1]
mode in ("plan", "check", "quick", "history", "chairmarks") || error("Choose plan, check, quick, history or chairmarks")
if mode == "check"
    @testset "Independent container answers" begin
        for family in ContainerCases.FAMILIES, operation in ("build", ContainerCases.operation_name(family)), n in (0, 1, 32, 512)
            @testset "$family/$operation/$n" begin
                case = ContainerCases.container_case(family, operation; n)
                state = case.prepare()
                @test case.verify(state, case.operation(state))
            end
        end
    end
else
    backend = mode == "chairmarks" ? :chairmark : :benchmark
    plan = plan_suite(build_container_suite(; backends = (backend,)); profile = :historical,
        version_provider = _ -> CONTAINER_VERSIONS)
    if mode in ("plan", "quick", "chairmarks")
        plan = filter_suite_plan(plan; from_version = v"0.19.6")
    end
    length(ARGS) >= 2 && (plan = filter_suite_plan(plan; features = [ARGS[2]]))
    print_suite_plan(plan)
    if mode != "plan"
        output = get(ENV, "PERFCHECKER_RESUME", "")
        isempty(output) && (output = mktempdir(joinpath(@__DIR__, "results"); prefix = "containers-$(mode)-", cleanup = false))
        result = mode == "history" ? checkpointed_history(plan, output) : run_suite_repl(plan; reports = output, strict = false)
        println("Reports: ", output)
        suite_passed(result) || error("Inspect unsuccessful cases in the saved report")
    end
end
