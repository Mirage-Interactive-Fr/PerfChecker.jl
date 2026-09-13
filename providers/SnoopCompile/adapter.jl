import SnoopCompile

function _analyze_scenario(::Val{:snoopcompile}, case, options)
    # SnoopCompile reexports the core instrumentation macros on the supported 3.x line.
    result = SnoopCompile.@snoop_inference SharedScenarioRuntime.once(case)
    total = SnoopCompile.inclusive(result)
    return Dict{String, Any}("status" => "complete",
        "measurements" => Dict("inference_seconds" => Float64(total)),
        "analysis_scope" => "first complete scenario lifecycle in diagnostic process",
        "findings" => [_analyzer_finding(
            "compilation.inference", sprint(show, result);
            evidence = Dict("inference_seconds" => Float64(total)))])
end
