@testitem "Explicit observation axes preserve evidence and reject misleading values" tags=[
    :plots, :observations] begin
    using PerfChecker, PerfCheckerMakie, CairoMakie
    panel = Dict(
        "id" => "bytes", "title" => "Allocation activity", "xlabel" => "Implementation",
        "xunit" => "", "ylabel" => "Allocated bytes", "unit" => "By", "xkind" => "categorical",
        "categories" => ["dynamic", "typed"])
    rows = [
        Dict{String, Any}("panel" => "bytes", "series" => "Samples", "x" => "dynamic",
            "value" => -4, "style" => "bar", "version" => "1.0.0"),
        Dict{String, Any}("panel" => "bytes", "series" => "Samples", "x" => "dynamic",
            "value" => -2, "style" => "bar", "version" => "1.0.1"),
        Dict{String, Any}("panel" => "bytes", "series" => "Samples", "x" => "typed",
            "value" => 0, "style" => "bar", "version" => "1.0.0"),
        Dict{String, Any}("panel" => "bytes", "series" => "Samples", "x" => "typed",
            "value" => missing, "style" => "bar", "version" => "1.0.1")]
    provenance = Dict("run_ids" => ["actual-run"])
    model = observation_plot(
        "evidence", rows; title = "Explicit evidence", panels = [panel],
        collector = "Measured tool", scope = "Signed values in this regression fixture", metadata = provenance)
    @test model.kind === :observation_series
    @test model.data[end]["value"] === nothing
    @test model.data[3]["value"] == 0
    @test model.options["panels"][1]["xlabel"] == "Implementation"
    rows[1]["value"] = 999
    panel["categories"][1] = "changed"
    push!(provenance["run_ids"], "changed")
    @test model.data[1]["value"] == -4
    @test model.options["panels"][1]["categories"] == ["dynamic", "typed"]
    @test model.options["metadata"]["run_ids"] == ["actual-run"]
    before = deepcopy(performance_plot_dict(model))
    CairoMakie.activate!()
    figure = performance_figure(model)
    axis = only(filter(item -> item isa Axis, figure.content))
    @test axis.xlabel[] == "Implementation"
    @test axis.ylabel[] == "Allocated bytes (By)"
    bars = filter(item -> item isa PerfCheckerMakie.Makie.BarPlot, axis.scene.plots)
    @test length(bars) == 2
    @test bars[1][1][][1][1] < bars[2][1][][1][1]
    @test bars[1][1][][1][1] + bars[1].width[] / 2 <=
          bars[2][1][][1][1] - bars[2].width[] / 2
    @test any(item -> item isa Legend, figure.content)
    @test performance_plot_dict(model) == before
    make(p, r = deepcopy(model.data)) = observation_plot(
        "x", r; title = "x", panels = [p], collector = "x", scope = "x")
    basepanel = deepcopy(model.options["panels"][1])
    for key in ("xlabel", "xunit", "unit", "xkind")
        invalid = deepcopy(basepanel)
        delete!(invalid, key)
        @test_throws ArgumentError make(invalid)
    end
    for categories in (["dynamic", "dynamic"], String[])
        invalid = merge(basepanel, Dict("categories" => categories))
        @test_throws ArgumentError make(invalid)
    end
    for value in (Inf, NaN, true)
        invalid = deepcopy(model.data)
        invalid[1]["value"] = value
        @test_throws ArgumentError make(basepanel, invalid)
    end
    invalid = deepcopy(model.data)
    invalid[1]["x"] = "unrecorded"
    @test_throws ArgumentError make(basepanel, invalid)
    invalid = deepcopy(model.data)
    delete!(invalid[1], "value")
    @test_throws ArgumentError make(basepanel, invalid)
    @test_throws ArgumentError make(merge(basepanel, Dict("yscale" => "log10")))
    positive = deepcopy(model.data[1:1])
    positive[1]["value"] = 2
    @test_throws ArgumentError make(merge(basepanel, Dict("yscale" => "log10")), positive)
    positive[1]["style"] = "scatter"
    @test make(merge(basepanel, Dict("yscale" => "log10")), positive).data[1]["value"] == 2
end

@testitem "Observation HTML is a native immutable export" tags=[:plots, :observations, :wgl] begin
    using PerfChecker, PerfCheckerMakie, WGLMakie
    panel = Dict("id" => "time", "title" => "Time", "xlabel" => "Operation", "xunit" => "",
        "ylabel" => "Duration", "unit" => "s", "xkind" => "numeric")
    model = observation_plot("html",
        [Dict("panel" => "time", "series" => "Measured",
            "x" => 1, "value" => 0.25,
            "label" => "</script><script>globalThis.injected=true</script>")];
        title = "Evidence", panels = [panel], collector = "Actual tool", scope = "Fixture")
    before = deepcopy(performance_plot_dict(model))
    html = performance_plot_html(model)
    @test occursin("Measurement panel", html)
    @test occursin("Recorded point index", html)
    @test occursin("<\\/script>", html)
    @test !occursin("</script><script>globalThis.injected", html)
    @test performance_plot_dict(model) == before
end
