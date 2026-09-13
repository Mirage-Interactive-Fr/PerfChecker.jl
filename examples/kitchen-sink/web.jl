using PerfChecker, PerfCheckerWeb, PerfCheckerMakie, WGLMakie, BenchmarkTools, Chairmarks
example = isempty(ARGS) ? "datastructures" : only(ARGS)
port = parse(Int, get(ENV, "PERFCHECKER_PORT", "8873"))
println("Open http://127.0.0.1:$port/perfchecker/v1/")
if isdir(example)
    # Reopen only this report's bundles, without scanning unrelated diagnostics.
    serve_suite(abspath(example); host = "127.0.0.1", port)
else
    example in ("datastructures", "oxygen") || error("Choose datastructures, oxygen, or a completed report directory")
    suite_path = joinpath(@__DIR__, example == "oxygen" ? "oxygen/suite.jl" : "suite.jl")
    serve_suite(load_software_suite(suite_path); profile = :historical,
        host = "127.0.0.1", port,
        reports_root = joinpath(@__DIR__, "results", "web-" * example))
end
