using PerfChecker, BenchmarkTools, TOML
include(joinpath(@__DIR__, "history-suite.jl"))
mode = isempty(ARGS) ? "plan" : only(ARGS)
mode in ("plan", "run") || error("Choose plan or run")
plan = plan_suite(build_suite(); profile = :historical)
print_suite_plan(plan)
if mode == "run"
    parent = joinpath(@__DIR__, "results")
    mkpath(parent)
    output = mktempdir(parent; prefix = "history-", cleanup = false)
    _, sources = history_sources()
    open(io -> TOML.print(io, Dict("targets" => sources)),
        joinpath(output, "sources.toml"), "w")
    result = run_suite_repl(plan; reports = output, strict = false,
        overrides = Dict{Symbol, Any}(
            :threads => 1, :samples => 100, :evals => 1, :seconds => 1.0))
    println("Reports: ", output)
    suite_passed(result) || throw(PerfChecker.SuiteRunError(result))
end
