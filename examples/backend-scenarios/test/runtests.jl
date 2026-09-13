using Test
include("../cases.jl")
for backend in ("cpu", "threads")
    case = BackendCases.affine(Dict("backend" => backend))
    state = case.prepare()
    try
        result = case.operation(state)
        case.synchronize(state, result)
        @test case.verify(state, result)
    finally
        case.cleanup(state)
    end
end
