using Test
include("cases.jl")

# These tests intentionally do not load PerfChecker.
@testset "Shared Étendue operations and independent oracles" begin
    for factory in (EtendueCases.translation, EtendueCases.verification)
        implementations = factory === EtendueCases.translation ?
                          ("allocating", "inplace") : ("allocating", "workspace")
        for implementation in implementations
            case = factory(Dict("implementation" => implementation, "n" => 100))
            state = case.prepare()
            try
                @test case.verify(state, case.operation(state))
            finally
                case.cleanup(state)
            end
        end
    end
    case = EtendueCases.verification(Dict("n" => 10, "valid" => false))
    state = case.prepare()
    try
        @test case.verify(state, case.operation(state))
    finally
        case.cleanup(state)
    end
end
