using TestItems

@testitem "Parse a small document" begin
    @test parse_total("12, 7, -3") == 16
end

@testitem "Parse a representative document" tags=[:perf_only] begin
    input = join(1:1000, ',')
    @test parse_total(input) == 500500
end

@testitem "Reject malformed input" tags=[:test_only] begin
    @test_throws ArgumentError parse_total("12, not-an-integer")
end
