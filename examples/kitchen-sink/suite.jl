using PerfChecker

const KITCHEN_VERSIONS = [v"0.11.0", v"0.12.0", v"0.13.0", v"0.14.0", v"0.15.0",
    v"0.16.1", v"0.17.0", v"0.17.20", v"0.18.0", v"0.18.10", v"0.18.13",
    v"0.18.15", v"0.18.22", v"0.19.0", v"0.19.1", v"0.19.2", v"0.19.3", v"0.19.4", v"0.19.5", v"0.19.6"]
const KITCHEN_COLLECTORS = (:benchmark, :chairmark, :alloc, :profile_alloc, :profile, :wall_profile)

"The same twelve workloads across tagged DataStructures releases and six collectors."
function build_suite()
    features = FeatureSpec[]
    for kind in ("heap", "vector", "counter", "buffer"), n in (64, 2048, 32768), collector in KITCHEN_COLLECTORS
        workload = Symbol(kind, "_", n)
        push!(features, FeatureSpec(Symbol(workload, "_", collector);
            workload, backend = collector,
            entrypoint = joinpath(@__DIR__, "workloads", string(workload) * ".jl"),
            comparison_key = "events/$(kind)/$(n)/seed42/v1",
            oracle = OracleSpec(),
            state_policy = collector in (:profile, :wall_profile) ? :reuse : :fresh,
            options = Dict(:samples => 30, :evals => 1, :seconds => 0.25, :threads => 1)))
    end
    package = PackageSuite("DataStructures"; worker_environment = joinpath(@__DIR__, "workers"),
        versions = KITCHEN_VERSIONS, include_dev = false, features)
    return SoftwareSuite(:event_lab, [package];
        description = "Deterministic event processing with DataStructures; Oxygen is measured separately")
end
