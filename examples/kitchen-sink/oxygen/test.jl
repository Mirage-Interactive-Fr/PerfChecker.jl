using Test, HTTP, JSON
include(joinpath(@__DIR__, "service.jl"))
@testset "Oxygen request oracles" begin
    for kind in ("heap", "counter", "buffer"), n in (0, 1, 64, 2048)
        case = EventService.request_case(kind, n)
        request = case.prepare()
        @test case.verify(request, case.operation(request))
        @test !case.verify(request, HTTP.Response(500))
    end
    @test EventService.internalrequest(HTTP.Request("GET", "/missing")).status == 404
    shared = EventService.scenario(Dict("kind" => "heap", "n" => 64))
    state = shared.prepare()
    @test shared.verify(state, shared.operation(state))
end
port = parse(Int, get(ENV, "OXYGEN_EXAMPLE_PORT", "18872"))
try
    EventService.start(port)
    @testset "Oxygen loopback oracles" begin
        for kind in ("heap", "counter", "buffer")
            case = EventService.request_case(kind)
            response = HTTP.post("http://127.0.0.1:$port/events/$kind",
                ["Content-Type" => "application/json"], case.payload)
            @test case.verify(nothing, response)
        end
    end
finally
    EventService.stop()
end
