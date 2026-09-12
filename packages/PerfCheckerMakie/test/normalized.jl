@testitem "Normalized legacy collector figures" tags=[:plots] begin
    using PerfChecker, PerfCheckerMakie, Makie
    tables = [
        PerfChecker.Table(
            times = [20.0, 40.0], gctimes = [0.0, 0.0], memory = [10, 20], allocs = [2, 4]),
        PerfChecker.Table(
            times = [10.0, 30.0], gctimes = [0.0, 0.0], memory = [20, 30], allocs = [1, 3])]
    packages = [PerfChecker.PackageSpec(name = "Demo", version = v"0.2.9"),
        PerfChecker.PackageSpec(name = "Demo", version = v"0.2.10")]
    result = PerfChecker.CheckerResult(tables, nothing, nothing, packages)
    for collector in (:benchmark, :chairmark)
        figure = PerfChecker.checkres_to_scatterlines(result, Val(collector))
        axis = only(filter(item -> item isa Axis, figure.content))
        curves = filter(item -> item isa Makie.ScatterLines, axis.scene.plots)
        @test length(curves) == 4
        @test all(curve -> all(point -> isfinite(point[2]), curve[1][]), curves)
        @test axis.xticks[][2] == ["0.2.9", "0.2.10"]
    end
end

@testitem "Suite dashboard retains absolute view" tags=[:plots] begin
    using PerfChecker, PerfCheckerMakie, Makie
    mktempdir() do dir
        write(joinpath(dir, "Project.toml"), """
name = "DashboardFixture"
uuid = "a9badcc7-6e8e-43b8-8b84-ed3ed10dc651"
version = "0.1.0"
""")
        entrypoint = joinpath(dir, "workload.jl")
        write(entrypoint, "perf_workload(state) = nothing\n")
        feature = FeatureSpec(:render; entrypoint)
        package = PackageSuite("DashboardFixture"; worker_environment = dir,
            source = dir, versions = VersionNumber[], features = [feature])
        plan = plan_suite(SoftwareSuite(:dashboard, [package]); profile = :quick,
            version_provider = _ -> VersionNumber[])
        checker = PerfChecker.CheckerResult(
            [PerfChecker.Table(times = [10.0, 20.0], gctimes = [0.0, 0.0],
                memory = [100, 200], allocs = [1, 2])], nothing, nothing,
            [PerfChecker.PackageSpec(name = "DashboardFixture", version = v"0.1.0")])
        run = FeatureRun(only(plan.runs), :pass, 0.25, checker, "", Dict{String, Any}())
        result = SoftwareSuiteResult(plan, "start", "finish", [run])
        combined = suite_dashboard(result)
        axis = only(filter(item -> item isa Axis, combined.content))
        @test axis.ylabel[] == "ratio to minimum (reference = 1)"
        absolute = suite_dashboard(result; view = :absolute)
        axis = only(filter(item -> item isa Axis, absolute.content))
        @test axis.ylabel[] == "minimum time"
        @test any(plot -> plot isa Makie.BarPlot, axis.scene.plots)
        @test_throws ArgumentError suite_dashboard(result; view = :invalid)
    end
end
