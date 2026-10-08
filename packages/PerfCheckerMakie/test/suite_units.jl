@testitem "Absolute suite timings use known units without changing evidence" tags=[:plots] begin
    using PerfChecker, PerfCheckerMakie, CairoMakie
    using PerfCheckerMakie: Makie
    CairoMakie.activate!()
    mktempdir() do directory
        write(joinpath(directory, "Project.toml"), """
name = "SuiteUnitsFixture"
uuid = "a9badcc7-6e8e-43b8-8b84-ed3ed10dc651"
version = "0.1.0"
""")
        entrypoint = joinpath(directory, "workload.jl")
        write(entrypoint, "perf_workload(state) = nothing\n")
        features = [FeatureSpec(id; entrypoint, backend)
                    for (id, backend) in ((:benchmark_time, :benchmark),
            (:chairmark_time, :chairmark), (:legacy_time, :legacy_unknown))]
        package = PackageSuite("SuiteUnitsFixture"; worker_environment = directory,
            source = directory, versions = VersionNumber[], features)
        plan = plan_suite(SoftwareSuite(:units, [package]); profile = :quick,
            version_provider = _ -> VersionNumber[])
        runs = FeatureRun[]
        for planned in plan.runs
            backend = planned.feature.backend
            times = backend === :benchmark ? [1.0e9, 2.0e9] :
                    backend === :chairmark ? [1.0, 2.0] : [7.0, 14.0]
            table = backend === :chairmark ?
                    PerfChecker.Table(
                times = times, gctimes = [0.0, 0.0], bytes = [0, 0], allocs = [0, 0]) :
                    PerfChecker.Table(
                times = times, gctimes = [0.0, 0.0], memory = [0, 0], allocs = [0, 0])
            checker = PerfChecker.CheckerResult([table], nothing, [:recorded],
                [PerfChecker.PackageSpec(name = "SuiteUnitsFixture", version = v"0.1.0")])
            push!(runs, FeatureRun(planned, :pass, 0.01, checker, "", Dict{String, Any}()))
        end
        result = SoftwareSuiteResult(plan, "start", "finish", runs)
        evidence = deepcopy([run.result.tables for run in runs])
        summaries = [PerfChecker._first_summary_row(run) for run in runs]
        figure = suite_dashboard(result; view = :absolute,
            figure_kwargs = (size = (800, 500),), plot_kwargs = (color = :red,))
        axis = only(filter(item -> item isa Axis, figure.content))
        @test axis.ylabel[] == "minimum elapsed time (s)"
        @test axis.subtitle[] == "Tags: recorded"
        @test occursin("BenchmarkTools", axis.title[])
        @test occursin("Chairmarks", axis.title[])
        bars = only(filter(item -> item isa Makie.BarPlot, axis.scene.plots))
        @test [point[2] for point in bars[1][]] == [1.0, 1.0]
        @test any(
            item -> item isa Label && occursin("legacy_unknown", item.text[]) &&
                        occursin("time unit unspecified", item.text[]),
            figure.content)
        rendered = Makie.colorbuffer(figure)
        red(pixel) = begin
            rgb = Makie.RGBf(pixel)
            rgb.r > 0.9 && rgb.g < 0.1 && rgb.b < 0.1
        end
        midpoint = size(rendered, 2) ÷ 2
        left = findall(red, rendered[:, 1:midpoint])
        right = findall(red, rendered[:, (midpoint + 1):end])
        @test length(left) > 100 && length(right) > 100
        function height(indices)
            maximum(index -> index[1], indices) - minimum(index -> index[1], indices)
        end
        @test abs(height(left) - height(right)) <= 1 # Equal physical bar heights.
        @test [run.result.tables for run in runs] == evidence
        @test [PerfChecker._first_summary_row(run) for run in runs] == summaries
        unknown = only(filter(run -> run.planned.feature.backend === :legacy_unknown, runs))
        unknown_figure = suite_dashboard(
            SoftwareSuiteResult(plan, "start", "finish", [unknown]); view = :absolute)
        unknown_axis = only(filter(item -> item isa Axis, unknown_figure.content))
        @test !any(item -> item isa Makie.BarPlot, unknown_axis.scene.plots)
        @test any(item -> item isa Label && occursin("known units", item.text[]),
            unknown_figure.content)
        @test any(item -> item isa Label && occursin("time unit unspecified", item.text[]),
            unknown_figure.content)
        @test length(unique(vec(Makie.colorbuffer(unknown_figure)))) > 20
        default_unknown = suite_dashboard(SoftwareSuiteResult(
            plan, "start", "finish", [unknown]))
        default_axis = only(filter(item -> item isa Axis, default_unknown.content))
        @test !any(item -> item isa Makie.BarPlot, default_axis.scene.plots)
        @test any(item -> item isa Label && occursin("time unit unspecified", item.text[]),
            default_unknown.content)
    end
end
