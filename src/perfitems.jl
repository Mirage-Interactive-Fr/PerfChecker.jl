"""
    run_perfitem(catalog, id; implementation="default", kwargs...)

Run exactly one declared performance item with the shared isolated lifecycle.
Keywords are forwarded to `run_scenarios`; unknown identities fail before execution.
"""
function run_perfitem(catalog::ScenarioCatalog, id::AbstractString;
        implementation::AbstractString = "default", kwargs...)
    selected = select_scenarios(catalog,
        [Dict("id" => String(id), "implementation" => String(implementation))])
    run_scenarios(selected; kwargs...)
end
