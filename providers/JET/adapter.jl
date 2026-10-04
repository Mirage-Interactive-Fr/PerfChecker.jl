import JET

function _analyze_scenario(::Val{:jet}, case, options)
    _analysis_operation(case,
        function (operation, state)
            report = JET.report_opt(operation, Tuple{typeof(state)})
            findings = Dict{String, Any}[]
            for item in JET.get_reports(report)
                stack = hasproperty(item, :vst) ? item.vst : []
                frame = isempty(stack) ? nothing : last(stack)
                rule = nameof(typeof(item)) == :RuntimeDispatchReport ?
                       "inference.runtime_dispatch" : "inference.optimization"
                push!(findings,
                    _analyzer_finding(rule, sprint(show, item);
                        file = frame === nothing ? "" : string(frame.file),
                        line = frame === nothing ? 0 : Int(frame.line),
                        evidence = Dict("analysis" => "JET.report_opt",
                            "report_type" => string(typeof(item)))))
            end
            Dict{String, Any}("status" => "complete", "findings" => findings,
                "analysis_scope" => "operation specialized for prepared state type; synchronization excluded")
        end)
end
