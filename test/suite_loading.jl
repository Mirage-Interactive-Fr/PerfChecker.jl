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
        write(joinpath(root, "factory.jl"),
            "eval(:(build_suite() = SoftwareSuite(:factory, [package])))\n")
        write(definition, prelude * "include(\"factory.jl\")\n")
        @test load_software_suite(definition).id == :factory
        write(definition, prelude * "suite = SoftwareSuite(:binding, [package])\n")
        @test load_software_suite(definition).id == :binding
        write(
            definition, prelude * "custom_factory() = SoftwareSuite(:custom, [package])\n")
        @test load_software_suite(definition; factory = :custom_factory).id == :custom
        @test_throws ArgumentError load_software_suite(definition)
    end
end

@testitem "A suite resolves defaults when it loads BenchmarkTools itself" tags=[
    :integration, :suites] begin
    using PerfChecker
    mktempdir() do root
        source = mkpath(joinpath(root, "SuiteDefaultsFixture", "src"))
        write(joinpath(dirname(source), "Project.toml"),
            "name = \"SuiteDefaultsFixture\"\nuuid = \"37f9eae5-7188-47c8-b5dd-47743a5062a1\"\nversion = \"0.1.0\"\n")
        write(joinpath(source, "SuiteDefaultsFixture.jl"), "module SuiteDefaultsFixture\nend\n")
        worker = mkpath(joinpath(root, "worker"))
        write(joinpath(worker, "Project.toml"),
            "[deps]\nBenchmarkTools = \"6e4b80f9-dd63-53aa-95a3-0cdb28fa8baf\"\n")
        entrypoint = joinpath(root, "workload.jl")
        write(entrypoint, "perf_setup() = [41]\nperf_workload(state) = only(state) + 1\nperf_oracle(state) = perf_workload(state) == 42\n")
        code = """
        using PerfChecker
        @assert Base.get_extension(PerfChecker, :BenchmarkToolsExt) === nothing
        feature = FeatureSpec(:benchmark_defaults; entrypoint = $(repr(entrypoint)),
            state_policy = :reuse, oracle = OracleSpec(),
            options = Dict(:samples => 3, :seconds => 0.1))
        package = PackageSuite("SuiteDefaultsFixture"; source = $(repr(dirname(source))),
            worker_environment = $(repr(worker)), versions = VersionNumber[],
            features = [feature])
        result = run_suite(SoftwareSuite(:suite_defaults, [package]))
        @assert suite_verdict(result) === :validated
        """
        project = dirname(Base.active_project())
        @test success(`$(Base.julia_cmd()) --startup-file=no --project=$project -e $code`)
    end
end
