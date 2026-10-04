@testitem "Suite definitions expose newly included factories and bindings" tags=[
    :unit, :suites] begin
    using PerfChecker
    mktempdir() do root
        write(joinpath(root, "Project.toml"), "name = \"Example\"\nversion = \"0.1.0\"\n")
        write(joinpath(root, "workload.jl"), "perf_workload(state) = 1\n")
        prelude = """
        using PerfChecker
        package = PackageSuite("Example"; source=@__DIR__, worker_environment=@__DIR__,
            features=[FeatureSpec(:example; entrypoint=joinpath(@__DIR__, "workload.jl"))])
        """
        definition = joinpath(root, "suite.jl")
        write(definition, prelude * "build_suite() = SoftwareSuite(:factory, [package])\n")
        @test load_software_suite(definition).id == :factory
        write(definition, prelude * "suite = SoftwareSuite(:binding, [package])\n")
        @test load_software_suite(definition).id == :binding
        write(
            definition, prelude * "custom_factory() = SoftwareSuite(:custom, [package])\n")
        @test load_software_suite(definition; factory = :custom_factory).id == :custom
        @test_throws ArgumentError load_software_suite(definition)
    end
end
