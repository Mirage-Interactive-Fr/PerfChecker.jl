"""
    tool_catalog(; category=nothing)

Read the bundled `data/tool-catalog.json` and attach current
[`diagnostic_capabilities`](@ref) under `analyzers`. Return a dictionary; a
category string or symbol filters `tools` by exact category, while `nothing`
retains all tools. Unknown categories produce an empty tools list.
Installed, candidate and qualified statuses remain distinct: listing a tool
does not execute, install or qualify it. Bundled-file errors propagate.
"""
function tool_catalog(; category = nothing)
    catalog = _json_parsefile(joinpath(pkgdir(@__MODULE__), "data", "tool-catalog.json"))
    catalog["analyzers"] = diagnostic_capabilities()
    category === nothing ||
        filter!(t -> t["category"] == string(category), catalog["tools"])
    return catalog
end
