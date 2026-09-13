

@testitem "Signed terminal version changes" tags=[:unit, :plots] begin
    using PerfChecker, UnicodePlots
    rows = Dict{String, Any}[
        Dict("candidate_version" => "1.1.0", "relative_delta" => -0.25),
        Dict("candidate_version" => "1.2.0", "relative_delta" => 0.0),
        Dict("candidate_version" => "1.3.0", "relative_delta" => 0.5),
        Dict("candidate_version" => "1.4.0", "relative_delta" => nothing),
    ]
    model = PerfChecker.PerformancePlot("signed-test", :version_delta, "Signed deltas", "",
        Dict{String, Any}(), rows, Dict{String, Any}())
    text = sprint(show, MIME"text/plain"(), terminal_plot(model))
    @test occursin("signed change", text)
    @test occursin("-", text)
    @test occursin("1.3.0", text)
    @test !occursin("1.4.0", text)
    @test model.data[1]["relative_delta"] == -0.25
    missing = PerfChecker.PerformancePlot("missing-test", :version_delta, "Zero baseline", "",
        Dict{String, Any}(), rows[4:4], Dict{String, Any}())
    missing_text = sprint(show, MIME"text/plain"(), terminal_plot(missing))
    @test occursin("relative change unavailable", missing_text)
    @test !occursin("baseline = 0", missing_text)
end
