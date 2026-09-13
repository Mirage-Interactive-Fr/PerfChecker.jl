using PerfChecker, PerfCheckerPluto
example = isempty(ARGS) ? "datastructures" : only(ARGS)
definitions = Dict("datastructures" => ("suite.jl", :build_suite),
    "oxygen" => ("oxygen/suite.jl", :build_suite),
    "containers" => ("containers-suite.jl", :build_container_suite),
    "oxygen-features" => ("oxygen/features-suite.jl", :build_http_feature_suite))
haskey(definitions, example) || error("Choose datastructures, containers, oxygen or oxygen-features")
source, factory = definitions[example]
path = joinpath(@__DIR__, "exports", example * "-controller.jl")
mkpath(dirname(path))
write_suite_notebook(path;
    suite_path = joinpath(@__DIR__, source), factory,
    profile = :historical, reports_root = "../results", force = true)
println(path)
