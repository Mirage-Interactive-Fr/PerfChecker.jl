using PerfChecker
include(joinpath(@__DIR__, "src/containers.jl"))
const CONTAINER_VERSIONS = [VersionNumber(0, 19, patch) for patch in 0:6]

"Seventy independent construction/access cases across every DataStructures 0.19 patch."
function build_container_suite(; backends = (:benchmark,))
    features = FeatureSpec[]
    for family in ContainerCases.FAMILIES, operation in ("build", ContainerCases.operation_name(family)), backend in backends
        id = family * "_" * operation
        push!(features, FeatureSpec(Symbol(id, "_", backend);
            workload = Symbol(id), backend, oracle = OracleSpec(), state_policy = :fresh,
            entrypoint = joinpath(@__DIR__, "containers", id * ".jl"),
            comparison_key = "containers/$(family)/$(operation)/512/seed42/v1",
            options = Dict(:samples => 30, :evals => 1, :seconds => 0.25, :threads => 1)))
    end
    SoftwareSuite(:container_catalogue, [PackageSuite("DataStructures";
        versions = CONTAINER_VERSIONS, include_dev = false,
        worker_environment = joinpath(@__DIR__, "workers"), features)];
        description = "Independent construction and use of 35 containers; all 0.19 patches")
end
