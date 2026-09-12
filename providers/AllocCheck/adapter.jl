import AllocCheck

function _analyze_scenario(::Val{:alloccheck}, case, options)
    _analysis_operation(case,
        function (operation, state)
            reports = AllocCheck.check_allocs(operation, Tuple{typeof(state)})
            findings = Dict{String, Any}[]
            for item in reports
                stack = hasproperty(item, :backtrace) ? item.backtrace : []
                frame = isempty(stack) ? nothing : first(stack)
                push!(findings,
                    _analyzer_finding(
                        "allocation.potential", sprint(show, item);
                        file = frame === nothing ? "" : string(frame.file),
                        line = frame === nothing ? 0 : Int(frame.line),
                        evidence = Dict("analysis" => "AllocCheck.check_allocs",
                            "report_type" => string(typeof(item)))))
            end
            Dict{String, Any}("status" => "complete", "findings" => findings,
                "analysis_scope" => "static operation specialization; tool exception-path defaults; not a universal allocation guarantee")
        end)
end
