using Test
include("../cases.jl")

@testset "The same scenarios without PerfChecker" begin
    for method in ("inplace", "copy")
        case = SharedCases.sorting(Dict("method" => method, "n" => 100))
        state = case.prepare()
        result = case.operation(state)
        @test case.verify(state, result)
    end
    case = SharedCases.asynchronous(Dict())
    state = case.prepare()
    result = case.operation(state)
    case.synchronize(state, result)
    @test case.verify(state, result)
end
