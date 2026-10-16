using TOML
include("worker_privacy.jl")
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
    status = error isa SharedScenarioRuntime.ScenarioUnavailable ? "unavailable" :
             callback_failure ? "invalid" : "error"
    merge(PerfCheckerWorkerPrivacy.failure_result(error, catch_backtrace(); status,
            stage = :scenario_execution,
            callback_phase = callback_failure ? error.phase : nothing,
            callback_cause = callback_failure ? error.cause : nothing), Dict{String, Any}(
        "correctness" => correctness_failed ? "failed" : "not_checked",
        "collector" => request["collector"]))
end
PerfCheckerWorkerPrivacy.write_response(ARGS[2], result)
