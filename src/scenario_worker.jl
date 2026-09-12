using TOML
include("scenario_runtime.jl")
request = TOML.parsefile(ARGS[1])
result = try
    collector = request["collector"]
    package = collector == "benchmark" ? "BenchmarkTools" :
              collector == "chairmark" ? "Chairmarks" : "Profile"
    if Base.find_package(package) === nothing
        Dict{String, Any}("status" => "unavailable", "correctness" => "not_checked",
            "collector" => collector, "message" => "$package is not installed in the worker project")
    else
        SharedScenarioRuntime.execute(request["scenario"], collector, request["samples"])
    end
catch error
    callback_failure = error isa SharedScenarioRuntime.ScenarioFailure
    correctness_failed = callback_failure &&
                         error.phase in (:operation, :synchronize, :verify)
    Dict{String, Any}(
        "status" => error isa SharedScenarioRuntime.ScenarioUnavailable ? "unavailable" :
                    callback_failure ? "invalid" : "error",
        "correctness" => correctness_failed ? "failed" : "not_checked",
        "collector" => request["collector"], "message" => sprint(
            showerror, error, catch_backtrace()))
end
open(io -> TOML.print(io, result), ARGS[2], "w")
