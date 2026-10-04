using TestItems

@testitem "HTTP plain" tags=[:perf_only, :oxygen, :http_plain] begin
    include(joinpath(@__DIR__, "../oxygen/service.jl"))
    case = EventService.feature_case("plain")
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "HTTP path" tags=[:perf_only, :oxygen, :http_path] begin
    include(joinpath(@__DIR__, "../oxygen/service.jl"))
    case = EventService.feature_case("path")
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "HTTP query" tags=[:perf_only, :oxygen, :http_query] begin
    include(joinpath(@__DIR__, "../oxygen/service.jl"))
    case = EventService.feature_case("query")
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "HTTP json" tags=[:perf_only, :oxygen, :http_json] begin
    include(joinpath(@__DIR__, "../oxygen/service.jl"))
    case = EventService.feature_case("json")
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "HTTP html" tags=[:perf_only, :oxygen, :http_html] begin
    include(joinpath(@__DIR__, "../oxygen/service.jl"))
    case = EventService.feature_case("html")
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "HTTP binary" tags=[:perf_only, :oxygen, :http_binary] begin
    include(joinpath(@__DIR__, "../oxygen/service.jl"))
    case = EventService.feature_case("binary")
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end

@testitem "HTTP not_found" tags=[:perf_only, :oxygen, :http_not_found] begin
    include(joinpath(@__DIR__, "../oxygen/service.jl"))
    case = EventService.feature_case("not_found")
    state = case.prepare()
    @test case.verify(state, case.operation(state))
end
