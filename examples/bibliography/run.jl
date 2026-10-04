using PerfChecker, BenchmarkTools, Chairmarks, TOML

mode = isempty(ARGS) ? "plan" : first(ARGS)
mode in (
    "plan", "benchmark", "chairmark", "profile_alloc", "profile", "wall_profile", "all") ||
    error("Choose plan, benchmark, chairmark, profile_alloc, profile, wall_profile or all")
suite = load_software_suite(joinpath(@__DIR__, "suite.jl"))
plan = plan_suite(suite; profile = :quick)
packages = length(ARGS) >= 2 ? split(ARGS[2], ',') : nothing
features = length(ARGS) >= 3 ? split(ARGS[3], ',') : nothing
plan = filter_suite_plan(plan; packages, features,
    backends = mode in ("plan", "all") ? nothing : Symbol(mode))
print_suite_plan(plan)
isempty(plan.runs) && error("The selection contains no runs")
if mode != "plan"
    # New directories preserve earlier measurements when users repeat the tutorial.
    parent = joinpath(@__DIR__, "results")
    mkpath(parent)
    output = mktempdir(parent; prefix = mode * "-", cleanup = false)
    cp(joinpath(@__DIR__, "sources.toml"), joinpath(output, "sources.toml"))
    result = run_suite_repl(plan; reports = output, strict = false,
        overrides = Dict{Symbol, Any}(:threads => 1, :samples => 50,
            :evals => 1, :seconds => 0.5))
    println("Reports: ", output)
    suite_passed(result) || throw(PerfChecker.SuiteRunError(result))
end
