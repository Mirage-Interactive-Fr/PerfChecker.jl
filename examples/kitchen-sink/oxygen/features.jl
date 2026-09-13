using PerfChecker, BenchmarkTools
include(joinpath(@__DIR__, "features-suite.jl"))
include(joinpath(@__DIR__, "../history.jl"))
mode = isempty(ARGS) ? "plan" : ARGS[1]
mode in ("plan", "quick", "history") || error("Choose plan, quick or history")
plan = plan_suite(build_http_feature_suite(); profile = :historical, version_provider = _ -> OXYGEN_VERSIONS)
mode != "history" && (plan = filter_suite_plan(plan; from_version = v"1.11.0"))
length(ARGS) >= 2 && (plan = filter_suite_plan(plan; from_version = VersionNumber(ARGS[2])))
length(ARGS) >= 3 && (plan = filter_suite_plan(plan; to_version = VersionNumber(ARGS[3])))
print_suite_plan(plan)
if mode != "plan"
    output = mktempdir(joinpath(@__DIR__, "../results"); prefix = "oxygen-features-", cleanup = false)
    result = mode == "history" ? checkpointed_history(plan, output) : run_suite_repl(plan; reports = output, strict = false)
    println("Reports: ", output)
    suite_passed(result) || error("Inspect unsuccessful cases in the saved report")
end
