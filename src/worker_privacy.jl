"""Private worker transport diagnostics shared by controller and entry points.
Never render exception messages, objects, argument values, commands or environments.
Worker stdout/stderr can contain arbitrary workload data and is not public evidence.
"""
module PerfCheckerWorkerPrivacy
using TOML

const FAILURE_STAGES = (:scenario_execution, :diagnostic_execution, :analyzer_loading,
    :worker_transport, :request_write, :worker_launch, :worker_wait, :response_read,
    :worker_cleanup, :provenance_capture)
const CALLBACK_PHASES = (:prepare, :operation, :synchronize, :verify, :cleanup)

function failure_diagnostic(error, trace; stage::Symbol = :worker_transport,
        callback_phase = nothing, callback_cause = nothing)
    frames = try
        source = stacktrace(trace)
        [Dict("function" => String(frame.func), "file" => String(frame.file),
             "line" => frame.line) for frame in first(source, min(12, length(source)))]
    catch
        Dict{String, Any}[]
    end
    result = Dict{String, Any}("schema_version" => "perfchecker-worker-failure/1",
        "exception_type" => string(nameof(typeof(error))), "source_frames" => frames,
        "stage" => string(stage in FAILURE_STAGES ? stage : :worker_transport))
    if callback_phase in CALLBACK_PHASES
        result["callback_phase"] = string(callback_phase)
        callback_cause === nothing ||
            (result["cause_type"] = string(nameof(typeof(callback_cause))))
    end
    result
end

function failure_result(error, trace; status::String = "error", kwargs...)
    status in ("error", "invalid", "unavailable") ||
        throw(ArgumentError("unsupported worker failure status"))
    Dict{String, Any}("status" => status,
        "message" => "Private worker failed; exception messages and values are not exported.",
        "failure" => failure_diagnostic(error, trace; kwargs...))
end

function write_response(path, result)
    open(path, "w") do io
        Sys.isunix() && chmod(path, 0o600)
        TOML.print(io, result)
    end
end

end
