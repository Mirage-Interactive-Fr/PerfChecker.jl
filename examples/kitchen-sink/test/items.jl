using TestItems

@testitem "Heap and vector preserve event order" begin
    for n in (0, 1, 64, 2048)
        input = events(n)
        @test drain_heap(input) == drain_vector(input) == sort(input)
    end
end

@testitem "Counter and ring buffer keep the expected data" begin
    for kind in ("counter", "buffer")
        case = event_case(Dict("kind" => kind, "n" => 2048))
        state = case.prepare()
        @test case.verify(state, case.operation(state))
    end
end

@testitem "Representative event queue" tags=[:perf_only, :queue] begin
    input = events(32768)
    @test drain_heap(input) == sort(input)
end

@testitem "Reject negative event count" tags=[:test_only] begin
    @test_throws ArgumentError events(-1)
end
