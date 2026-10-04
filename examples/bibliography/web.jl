using PerfChecker, PerfCheckerWeb, PerfCheckerMakie, WGLMakie
using BenchmarkTools, Chairmarks

mode = isempty(ARGS) ? "quick" : only(ARGS)
mode in ("quick", "history") || error("Choose quick or history")
suite = load_software_suite(joinpath(
    @__DIR__, mode == "history" ? "history-suite.jl" : "suite.jl"))
serve_suite(suite; profile = mode == "history" ? :historical : :quick, host = "127.0.0.1",
    port = parse(Int, get(ENV, "PERFCHECKER_PORT", "8871")),
    reports_root = joinpath(@__DIR__, "results"))
