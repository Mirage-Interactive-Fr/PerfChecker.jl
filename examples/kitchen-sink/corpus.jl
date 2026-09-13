using PerfChecker, PerfCheckerKitchenSink, PropCheck, Supposition, Test
output = joinpath(@__DIR__, "results", "corpora")
mkpath(output)
mode = isempty(ARGS) ? "freeze" : only(ARGS)
paths = [joinpath(output, name * ".json") for name in ("propcheck", "supposition")]
if mode == "freeze"
    encode = value -> Dict("kind" => "heap", "n" => 1 + abs(Int(value)), "seed" => 42)
    freeze_propcheck_corpus(paths[1], PropCheck.itype(Int16);
        count = 20, seed = 42, encode, metadata = Dict("workload" => "events/heap/v1"))
    freeze_supposition_corpus(paths[2], Supposition.Data.Integers{Int16}();
        count = 20, encode, metadata = Dict("workload" => "events/heap/v1"))
elseif mode != "replay"
    error("Choose freeze or replay. Existing corpora are never silently overwritten.")
end
@testset "Frozen property inputs" begin
    for file in paths, parameters in read_property_corpus(file)["cases"]
        case = event_case(parameters)
        state = case.prepare()
        @test case.verify(state, case.operation(state))
    end
end
