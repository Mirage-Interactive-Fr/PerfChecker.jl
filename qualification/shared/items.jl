using TestItems

@testitem "Shared assertion" begin
    if haskey(ENV, "PERFCHECKER_HOST_MARKER")
        open(io -> println(io, "shared"), ENV["PERFCHECKER_HOST_MARKER"], "a")
    end
    @test sum(1:10) == 55
end

@testitem "Only performance" tags=[:perf_only] begin
    if haskey(ENV, "PERFCHECKER_HOST_MARKER")
        open(io -> println(io, "performance"), ENV["PERFCHECKER_HOST_MARKER"], "a")
    end
    @test length(collect(1:10)) == 10
end

@testitem "Only correctness" tags=[:test_only] begin
    @test 2 + 2 == 4
end
