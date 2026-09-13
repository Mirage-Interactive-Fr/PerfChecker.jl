include(joinpath(@__DIR__, "src/PerfCheckerKitchenSink.jl"))
case = PerfCheckerKitchenSink.event_case(Dict("kind" => "heap", "n" => 32768))
for _ in 1:100
    state = case.prepare()
    @assert case.verify(state, case.operation(state))
end
