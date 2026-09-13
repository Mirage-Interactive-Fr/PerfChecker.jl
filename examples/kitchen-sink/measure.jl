using PerfChecker, BenchmarkTools, Chairmarks
include(joinpath(@__DIR__, "suite.jl"))
include(joinpath(@__DIR__, "history.jl"))

# Listing is the default. A complete campaign is explicitly requested.
mode = isempty(ARGS) ? "plan" : ARGS[1]
length(ARGS) <= 3 || error("Pass a mode, then optional first and last versions")
mode in ("plan", "quick", "history", "profiles", "all") || error("Choose plan, quick, history, profiles or all")
plan = plan_suite(build_suite(); profile = :historical, version_provider = _ -> KITCHEN_VERSIONS)
if mode in ("plan", "quick")
    plan = filter_suite_plan(plan; features = ["heap_2048_benchmark", "vector_2048_benchmark", "counter_2048_benchmark", "buffer_2048_benchmark"], from_version = v"0.19.6", to_version = v"0.19.6")
elseif mode == "history"
    plan = filter_suite_plan(plan; features = ["heap_2048_benchmark", "vector_2048_benchmark", "counter_2048_benchmark", "buffer_2048_benchmark", "heap_2048_chairmark"])
elseif mode == "profiles"
    plan = filter_suite_plan(plan; features = ["heap_32768_profile_alloc", "heap_32768_profile", "heap_32768_wall_profile", "heap_32768_alloc"], from_version = v"0.19.6", to_version = v"0.19.6")
end
if length(ARGS) >= 2
    plan = filter_suite_plan(plan; from_version = VersionNumber(ARGS[2]),
        to_version = length(ARGS) == 3 ? VersionNumber(ARGS[3]) : nothing)
end
print_suite_plan(plan)
if mode != "plan"
    parent = joinpath(@__DIR__, "results")
    mkpath(parent)
    output = mktempdir(parent; prefix = mode * "-", cleanup = false)
    overrides = Dict{Symbol, Any}(:threads => 1, :samples => 30, :evals => 1, :seconds => 0.25)
    result = mode == "history" ? checkpointed_history(plan, output; overrides) :
        run_suite_repl(plan; reports = output, strict = false, overrides)
    println("Reports: ", output)
    suite_passed(result) || error("At least one check failed; inspect the saved report")
end
