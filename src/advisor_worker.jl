started = time()
println(stderr, "PERFCHECKER_ADVISOR_PHASE dependencies_loading 0.0")
flush(stderr)
using TOML, PerfChecker
PerfChecker._advisor_phase_hook[] = phase -> begin
    println(stderr, "PERFCHECKER_ADVISOR_PHASE ", phase, " ", time() - started)
    flush(stderr)
end
PerfChecker._advisor_phase(:request_loading)
request = PerfChecker._json_plain_value(TOML.parsefile(ARGS[1]))
result = try
    PerfChecker._advisor_inprocess(request)
catch error
    PerfChecker._advisor_phase(:failed)
    # Keep credentials and transport headers out of saved logs.
    Dict{String, Any}(
        "status" => "error", "message" => string(typeof(error)), "cards" => [])
end
PerfChecker._advisor_phase(:response_write)
open(
    io -> TOML.print(
        io, Dict("payload_json" => sprint(s -> PerfChecker.JSON.print(s, result)))),
    ARGS[2],
    "w")
PerfChecker._advisor_phase(:complete)
