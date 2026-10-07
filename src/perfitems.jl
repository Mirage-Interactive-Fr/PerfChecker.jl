"""
    run_perfitem(catalog, id; implementation="default", kwargs...)

Run exactly one declared performance item with the shared isolated lifecycle.
Keywords are forwarded to [`run_scenarios`](@ref), including prepared `project`,
samples, timeout, cancellation and reports. Return the vector of `RunBundle`s
from the selected item's declared collectors, not a single scalar result.
Unknown scenario/implementation identities fail during selection before a
worker starts. Worker outcomes, cancellation and report side effects follow
`run_scenarios`; this function does not adopt discovered proposals.
"""
function run_perfitem(catalog::ScenarioCatalog, id::AbstractString;
        implementation::AbstractString = "default", kwargs...)
    selected = select_scenarios(catalog,
        [Dict("id" => String(id), "implementation" => String(implementation))])
    run_scenarios(selected; kwargs...)
end
