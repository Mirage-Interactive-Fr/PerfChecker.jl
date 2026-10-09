@testitem "Tradeoff renderers use verified dimensions or mark legacy units unknown" tags=[:plots] begin
    using PerfChecker, PerfCheckerMakie, Makie, UnicodePlots
    data = [Dict{String, Any}("version" => "1.0.0", "bytes" => 2048.0, "time" => 400.0),
        Dict{String, Any}("version" => "1.1.0", "bytes" => 4096.0, "time" => 800.0)]
    for unit in ("ns", "s", nothing)
        options = Dict{String, Any}("unit" => "s+By")
        if unit !== nothing
            options["time_unit"] = unit
            options["allocation_unit"] = "By"
        end
        model = PerfChecker.PerformancePlot("units", :time_allocation_tradeoff,
            "Recorded tradeoff", "Unit regression fixture", Dict{String, Any}(), data, options)
        before = deepcopy(performance_plot_dict(model))
        figure = performance_figure(model)
        axis = only(filter(item -> item isa Axis, figure.content))
        expected_time = isnothing(unit) ? "unit unspecified" : unit
        expected_allocation = isnothing(unit) ? "unit unspecified" : "By"
        @test axis.ylabel[] == "wall time ($expected_time)"
        @test axis.xlabel[] == "allocation ($expected_allocation)"
        terminal = sprint(show, MIME"text/plain"(), terminal_plot(model))
        @test occursin("time ($expected_time)", terminal)
        @test performance_plot_dict(model) == before
    end
end

@testitem "Tradeoff Core compatibility includes the required unit contract" tags=[:plots] begin
    using PerfChecker, PerfCheckerMakie
    project = PerfChecker.Pkg.Types.read_project(joinpath(
        pkgdir(PerfCheckerMakie), "Project.toml"))
    compatible = project.compat["PerfChecker"].val
    @test v"1.0.0" ∉ compatible
    @test v"1.0.1" in compatible
    @test pkgversion(PerfChecker) in compatible
    @test isdefined(PerfChecker, :_tradeoff_plot_units)
end
