using PerfChecker, DrWatson
include(joinpath(@__DIR__, "suite.jl"))
plan = plan_suite(build_suite(); profile = :historical, version_provider = _ -> KITCHEN_VERSIONS)
parameters = first(drwatson_parameters(plan))
println("Example run name: ", drwatson_savename(first(plan.runs)))
directory = joinpath(@__DIR__, "results", "drwatson")
# Cache experiment configuration first. Reuse of this file is not a fresh measurement.
saved, file = drwatson_produce_or_load(parameters; directory, tag = false) do configuration
    Dict("parameters" => configuration, "measurement_executed" => false)
end
@assert saved["measurement_executed"] == false
println(file)
if !isempty(ARGS)
    ARGS[1] == "run" || error("Use run [datastructures|oxygen] for an actual cached measurement")
    example = length(ARGS) == 1 ? "datastructures" : ARGS[2]
    example in ("datastructures", "oxygen") || error("Choose datastructures or oxygen")
    is_oxygen = example == "oxygen"
    source = load_software_suite(joinpath(@__DIR__, is_oxygen ? "oxygen/suite.jl" : "suite.jl"))
    original = only(source.packages)
    selected = filter(f -> f.id == (is_oxygen ? :heap_benchmark : :heap_2048_benchmark), original.features)
    version = is_oxygen ? v"1.11.0" : last(KITCHEN_VERSIONS)
    package = PackageSuite(is_oxygen ? "Oxygen" : "DataStructures";
        worker_environment = joinpath(@__DIR__, is_oxygen ? "oxygen/workers" : "workers"),
        versions = [version], include_dev = false, features = selected)
    small = SoftwareSuite(Symbol(example, "_cached"), [package])
    result, cached_file = drwatson_run_suite(small; profile = :quick, tag = false,
        directory = joinpath(directory, example), version_provider = _ -> [version],
        force = get(ENV, "PERFCHECKER_FORCE", "false") == "true")
    @assert result["passed"]
    println("Cached measurement: ", cached_file)
end
