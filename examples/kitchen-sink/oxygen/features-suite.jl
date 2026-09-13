include(joinpath(@__DIR__, "suite.jl"))
const HTTP_FEATURE_NAMES = ("plain", "path", "query", "json", "html", "binary", "not_found")
"Compare routing, parsing and response handling independently across registered patches."
function build_http_feature_suite()
    features = [FeatureSpec(Symbol(kind, "_benchmark"); workload = Symbol(kind, "_http"),
        backend = :benchmark, oracle = OracleSpec(), state_policy = :fresh,
        entrypoint = joinpath(@__DIR__, "features", kind * ".jl"),
        comparison_key = "oxygen/http/$(kind)/v1",
        options = Dict(:threads => 1, :samples => 30, :evals => 1, :seconds => 0.25)) for kind in HTTP_FEATURE_NAMES]
    SoftwareSuite(:oxygen_http_features, [PackageSuite("Oxygen";
        versions = OXYGEN_VERSIONS, include_dev = false,
        worker_environment = joinpath(@__DIR__, "workers"), features)];
        description = "Separate HTTP features across 14 Oxygen releases, with all 1.10 and 1.11 patches")
end
