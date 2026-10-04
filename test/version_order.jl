@testitem "Version-labelled Git targets sort chronologically" tags=[:unit, :plots] begin
    using PerfChecker
    points = [Dict("target_kind" => "candidate", "version" => version)
              for version in ["0.2.10", "0.3.0", "0.2.5", "0.1.0"]]
    sort!(points; by = PerfChecker._version_point_key)
    @test getindex.(points, "version") == ["0.1.0", "0.2.5", "0.2.10", "0.3.0"]
    named = [Dict("target_kind" => "candidate", "version" => label)
             for label in ["before-streaming", "after-streaming"]]
    sort!(named; by = PerfChecker._version_point_key)
    @test getindex.(named, "version") == ["after-streaming", "before-streaming"]
end
