using PerfChecker, PerfCheckerPluto
example = isempty(ARGS) ? "datastructures" : only(ARGS)
example in ("datastructures", "oxygen") || error("Choose datastructures or oxygen")
path = joinpath(@__DIR__, "exports", example * "-controller.jl")
mkpath(dirname(path))
write_suite_notebook(path;
    suite_path = joinpath(@__DIR__, example == "oxygen" ? "oxygen/suite.jl" : "suite.jl"),
    profile = :historical, reports_root = "../results", force = true)
println(path)
