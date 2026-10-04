@testitem "REPL selection reads numeric settings and preserves the workload filter" tags=[
    :unit, :suites] begin
    using PerfChecker
    mktempdir() do root
        write(joinpath(root, "Project.toml"), "name = \"Example\"\nversion = \"0.4.0\"\n")
        entrypoint = joinpath(root, "export.jl")
        write(entrypoint, "perf_workload(state) = 1\n")
        features = [FeatureSpec(:export_bibtex; entrypoint),
            FeatureSpec(:export_bibtex_allocations; entrypoint,
                workload = :export_bibtex, backend = :profile_alloc)]
        package = PackageSuite("Example"; source = root, worker_environment = root,
            versions = VersionNumber[], include_dev = true, features)
        suite = SoftwareSuite(:repl_example, [package])
        answers = ["Example", "export_bibtex", "benchmark",
            "", "", "", "", "50", "0.5", "1", "yes"]
        output = IOBuffer()
        plan, overrides = configure_suite_repl(suite; profile = :quick,
            input = IOBuffer(join(answers, '\n') * "\n"), output)
        @test length(plan.runs) == 1
        @test only(plan.runs).feature.backend == :benchmark
        @test overrides == Dict(:samples => 50, :seconds => 0.5, :threads => 1)
        @test occursin("Keep this selection?", String(take!(output)))
        answers[end] = "no"
        @test_throws InterruptException configure_suite_repl(suite; profile = :quick,
            input = IOBuffer(join(answers, '\n') * "\n"), output = IOBuffer())
        answers[end] = "yes"
        for (index, value) in ((8, "0"), (9, "NaN"), (10, "-1"))
            invalid = copy(answers)
            invalid[index] = value
            @test_throws ArgumentError configure_suite_repl(suite; profile = :quick,
                input = IOBuffer(join(invalid, '\n') * "\n"), output = IOBuffer())
        end
    end
end
