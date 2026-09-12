using PerfChecker, BenchmarkTools, Chairmarks, UnicodePlots

suite = load_software_suite(joinpath(@__DIR__, "suite.jl"))
plan, overrides = configure_suite_repl(suite; profile = :quick)
overrides[:threads] <= 4 || error("This tutorial allows at most four worker threads")
parent = joinpath(@__DIR__, "results")
mkpath(parent)
output = mktempdir(parent; prefix = "repl-", cleanup = false)
result = run_suite_repl(plan; overrides, reports = output)
println("Reports: ", output)
