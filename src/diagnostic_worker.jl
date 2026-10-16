using TOML
include("worker_privacy.jl")
module PerfCheckerDiagnosticRuntime
using TOML, Profile, Libdl, SHA
using UUIDs: uuid4
using ..PerfCheckerWorkerPrivacy
const _SCENARIO_ANALYZERS = Dict(
    :jet => "JET", :alloccheck => "AllocCheck", :aqua => "Aqua",
    :snoopcompile => "SnoopCompile", :latency => "builtin", :gc => "builtin",
    :memory => "builtin", :heap => "builtin", :locks => "builtin")
include("scenario_runtime.jl")
include("process_resources.jl")
include("diagnostic_runtime.jl")
include("memory_diagnostics.jl")
end
request = TOML.parsefile(ARGS[1])
runtime = PerfCheckerDiagnosticRuntime
result = try
    runtime._diagnostic_inprocess(request)
catch error
    callback_failure = error isa runtime.SharedScenarioRuntime.ScenarioFailure
    correctness_failed = callback_failure &&
                         error.phase in (:operation, :synchronize, :verify)
    status = error isa runtime.SharedScenarioRuntime.ScenarioUnavailable ?
             "unavailable" : callback_failure ? "invalid" : "error"
    merge(PerfCheckerWorkerPrivacy.failure_result(error, catch_backtrace(); status,
            stage = :diagnostic_execution,
            callback_phase = callback_failure ? error.phase : nothing,
            callback_cause = callback_failure ? error.cause : nothing), Dict{String, Any}(
        "correctness" => correctness_failed ? "failed" : "not_checked",
        "quality" => "not_checked", "performance" => "not_compared"))
end
result["controller_loaded"] = any(nameof(m) == :PerfChecker
for m in values(Base.loaded_modules))
PerfCheckerWorkerPrivacy.write_response(ARGS[2], result)
