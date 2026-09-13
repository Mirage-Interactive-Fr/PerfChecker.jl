using PerfChecker, PerfCheckerWeb, PerfCheckerMakie, WGLMakie, BenchmarkTools, Chairmarks
example = isempty(ARGS) ? "datastructures" : only(ARGS)
port = parse(Int, get(ENV, "PERFCHECKER_PORT", "8873"))
println("Open http://127.0.0.1:$port/perfchecker/v1/")
definitions = Dict("datastructures" => ("suite.jl", :build_suite),
        "oxygen" => ("oxygen/suite.jl", :build_suite),
        "containers" => ("containers-suite.jl", :build_container_suite),
        "oxygen-features" => ("oxygen/features-suite.jl", :build_http_feature_suite))
if haskey(definitions, example)
    path, factory = definitions[example]
    suite_path = joinpath(@__DIR__, path)
    serve_suite(load_software_suite(suite_path; factory); profile = :historical,
        host = "127.0.0.1", port,
        reports_root = joinpath(@__DIR__, "results", "web-" * example))
elseif isdir(example)
    # Explicit modes take priority over same-named source directories.
    serve_suite(abspath(example); host = "127.0.0.1", port)
else
    error("Choose datastructures, containers, oxygen, oxygen-features, or a completed report directory")
end
