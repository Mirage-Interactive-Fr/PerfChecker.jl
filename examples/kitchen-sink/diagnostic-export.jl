using JSON
include(joinpath(@__DIR__, "observation-export.jl"))
length(ARGS) == 2 || error("Pass diagnosis.json and an export directory")
source, output = abspath.(ARGS)
mkpath(output)
raw = JSON.parsefile(source)["records"]
keep = ("tool", "tool_version", "status", "correctness", "analysis_scope",
    "summary", "measurements", "findings", "runtime")
function public_value(value)
    if value isa AbstractDict
        return Dict(string(k) => public_value(v)
        for (k, v) in value if !(k in ("pid", "timestamp_ns", "source", "project", "path")))
    elseif value isa AbstractVector
        return public_value.(value)
    elseif value isa AbstractString
        # Native/source paths are useful locally, but unnecessary in public projections.
        return replace(value, r"[A-Za-z]:[\\/][^\s\n\"<>]+" => "<local-source>")
    end
    value
end
records = [public_value(Dict(k => r[k] for k in keep if haskey(r, k))) for r in raw]
open(io -> JSON.print(io, Dict("records" => records), 2),
    joinpath(output, "diagnosis.json"), "w")
export_diagnostic_observations(output)
println("Published seven diagnostic reports and four figures")
