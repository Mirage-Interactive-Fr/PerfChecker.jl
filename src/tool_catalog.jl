"Inventory of implemented integrations and candidates; listing is never qualification."
function tool_catalog(; category = nothing)
    catalog = _json_parsefile(joinpath(pkgdir(@__MODULE__), "data", "tool-catalog.json"))
    catalog["analyzers"] = diagnostic_capabilities()
    category === nothing ||
        filter!(t -> t["category"] == string(category), catalog["tools"])
    return catalog
end
