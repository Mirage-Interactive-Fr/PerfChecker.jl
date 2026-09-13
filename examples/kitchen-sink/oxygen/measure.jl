using PerfChecker, BenchmarkTools, Chairmarks
include(joinpath(@__DIR__, "suite.jl"))
include(joinpath(@__DIR__, "../history.jl"))
mode = isempty(ARGS) ? "plan" : ARGS[1]
length(ARGS) <= 3 || error("Pass a mode, then optional first and last versions")
mode in ("plan", "quick", "history", "profiles", "all") || error("Choose plan, quick, history, profiles or all")
plan = plan_suite(build_suite(); profile = :historical, version_provider = _ -> OXYGEN_VERSIONS)
if mode in ("plan", "quick")
    plan = filter_suite_plan(plan; backends = [:benchmark], from_version = v"1.11.0")
elseif mode == "history"
    plan = filter_suite_plan(plan; features = [:heap_benchmark, :counter_benchmark, :buffer_benchmark, :heap_chairmark])
elseif mode == "profiles"
    plan = filter_suite_plan(plan; features = [:heap_profile, :heap_wall_profile, :heap_profile_alloc], from_version = v"1.11.0")
end
if length(ARGS) >= 2
    plan = filter_suite_plan(plan; from_version = VersionNumber(ARGS[2]),
        to_version = length(ARGS) == 3 ? VersionNumber(ARGS[3]) : nothing)
end
print_suite_plan(plan)
if mode != "plan"
    parent = joinpath(@__DIR__, "../results")
    mkpath(parent)
    output = mktempdir(parent; prefix = "oxygen-" * mode * "-", cleanup = false)
    result = mode == "history" ? checkpointed_history(plan, output) : run_suite_repl(plan; reports = output, strict = false)
    println("Reports: ", output)
    suite_passed(result) || error("A check failed; inspect the saved report")
end
