using PerfChecker
const OXYGEN_VERSIONS = [v"1.0.0", v"1.1.0", v"1.2.0", v"1.3.0", v"1.4.0", v"1.5.0",
    v"1.6.0", v"1.7.0", v"1.8.0", v"1.9.0", v"1.10.0", v"1.11.0"]

"Compare the same in-process HTTP requests from Oxygen's first release to HTTP.jl 2."
function build_suite()
    features = FeatureSpec[]
    for kind in ("heap", "counter", "buffer"), backend in (:benchmark, :chairmark, :profile, :wall_profile, :profile_alloc)
        push!(features, FeatureSpec(Symbol(kind, "_", backend);
            workload = Symbol(kind, "_request"), backend,
            entrypoint = joinpath(@__DIR__, kind * ".jl"),
            comparison_key = "oxygen/events/$(kind)/2048/seed42/v1",
            oracle = OracleSpec(), state_policy = :fresh,
            options = Dict(:threads => 1, :samples => 30, :evals => 1, :seconds => 0.25)))
    end
    package = PackageSuite("Oxygen"; worker_environment = joinpath(@__DIR__, "workers"),
        versions = OXYGEN_VERSIONS, include_dev = false, features)
    SoftwareSuite(:oxygen_event_lab, [package];
        description = "Oxygen router, JSON decoding, event processing and response encoding; no socket")
end
