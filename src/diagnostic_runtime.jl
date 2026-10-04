function _analyze_scenario(tool, case, options)
    Dict{String, Any}(
        "status" => "unavailable", "message" => "analyzer extension not loaded")
end

function _analyzer_finding(rule, message; file = "", line = 0, evidence = Dict())
    Dict{String, Any}("rule_id" => rule, "severity" => "warning",
        "message" => message, "location" => Dict("file" => file, "line" => line),
        "evidence" => evidence)
end

function _analysis_operation(case, callback)
    state = case.prepare()
    try
        return callback(case.operation, state)
    finally
        hasproperty(case, :cleanup) && case.cleanup(state)
    end
end

function _diagnostic_inprocess(request)
    tool = Symbol(request["tool"])
    package = _SCENARIO_ANALYZERS[tool]
    result = Dict{String, Any}("tool" => string(tool), "status" => "unavailable",
        "correctness" => "not_checked", "quality" => "not_checked",
        "performance" => "not_compared", "findings" => Dict{String, Any}[],
        "runtime" => Dict("language" => "julia", "version" => string(VERSION),
            "threads" => Threads.nthreads()))
    if package != "builtin"
        Base.find_package(package) === nothing && return merge(result,
            Dict("message" => "$package is absent from the diagnostic environment"))
        try
            loaded_tool = Base.require(Main, Symbol(package))
            result["tool_version"] = string(Base.pkgversion(loaded_tool))
            include(joinpath(@__DIR__, "..", "providers", package, "adapter.jl"))
        catch error
            return merge(result,
                Dict("message" => sprint(showerror, error),
                    "status" => "unavailable"))
        end
    end
    options = get(request, "options", Dict{String, Any}())
    if tool == :aqua
        merge!(result, Base.invokelatest(_analyze_scenario, Val(tool), nothing, options))
        return result
    end
    spec = request["scenario"]
    started = time_ns()
    case = SharedScenarioRuntime.load_case(spec)
    load_seconds = Float64(time_ns() - started) / 1e9
    if tool == :latency
        started = time_ns()
        Base.invokelatest(SharedScenarioRuntime.once, case)
        first_seconds = Float64(time_ns() - started) / 1e9
        started = time_ns()
        Base.invokelatest(SharedScenarioRuntime.once, case)
        warm_seconds = Float64(time_ns() - started) / 1e9
        merge!(result,
            Dict("status" => "complete", "correctness" => "passed",
                "measurements" => Dict("load_seconds" => load_seconds,
                    "first_case_seconds" => first_seconds, "warm_case_seconds" => warm_seconds),
                "measurement_scope" => "fresh process; source loading; full lifecycle including preparation and verification"))
    else
        # Verify independently before static analysis. Analysis itself is not a correctness oracle.
        if tool != :snoopcompile
            Base.invokelatest(SharedScenarioRuntime.once, case)
            result["correctness"] = "passed"
        end
        merge!(result, Base.invokelatest(_analyze_scenario, Val(tool), case, options))
        if tool == :snoopcompile
            Base.invokelatest(SharedScenarioRuntime.once, case)
            result["correctness"] = "passed"
        end
    end
    return result
end
