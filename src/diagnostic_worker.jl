using TOML
module PerfCheckerDiagnosticRuntime
using TOML, Profile, Libdl, SHA
using UUIDs: uuid4
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
    Dict{String, Any}(
        "status" => error isa runtime.SharedScenarioRuntime.ScenarioUnavailable ?
                    "unavailable" : callback_failure ? "invalid" : "error",
        "message" => sprint(showerror, error, catch_backtrace()),
        "correctness" => correctness_failed ? "failed" : "not_checked",
        "quality" => "not_checked", "performance" => "not_compared")
end
result["controller_loaded"] = any(nameof(m) == :PerfChecker
for m in values(Base.loaded_modules))
open(io -> TOML.print(io, result), ARGS[2], "w")
