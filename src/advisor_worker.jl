using TOML, PerfChecker
request = TOML.parsefile(ARGS[1])
result = try
    PerfChecker._advisor_inprocess(request)
catch error
    # Keep credentials and transport headers out of saved logs.
    Dict{String, Any}(
        "status" => "error", "message" => string(typeof(error)), "cards" => [])
end
open(
    io -> TOML.print(
        io, Dict("payload_json" => sprint(s -> PerfChecker.JSON.print(s, result)))),
    ARGS[2],
    "w")
