using JSON
include(joinpath(@__DIR__, "observation-export.jl"))
length(ARGS) == 2 ||
    error("Pass an additional-diagnostics directory and an export directory")
source, output = abspath.(ARGS)
mkpath(output)
function redact(value)
    value isa AbstractDict && return Dict(string(k) => redact(v)
    for (k, v) in value
    if !(k in ("path", "source", "configuration", "environment_provenance",
        "source_provenance", "input_fingerprints")))
    value isa AbstractVector && return redact.(value)
    value isa AbstractString &&
        return replace(value, r"[A-Za-z]:[\\/][^\s\n\"<>]+" => "<local-source>")
    value
end
quality = JSON.parsefile(joinpath(source, "quality.json"))["records"]
heap = JSON.parsefile(joinpath(source, "heap.json"))["records"]
records = redact(vcat(quality, heap))
open(io -> JSON.print(io, Dict("records" => records), 2),
    joinpath(output, "additional.json"), "w")

function heap_summary(path)
    snapshot = JSON.parsefile(path)
    metadata = snapshot["snapshot"]["meta"]
    fields = metadata["node_fields"]
    stride = length(fields)
    type_index = findfirst(==("type"), fields)
    size_index = findfirst(==("self_size"), fields)
    names = metadata["node_types"][type_index]
    bytes = Dict{String, Int}()
    counts = Dict{String, Int}()
    nodes = snapshot["nodes"]
    for offset in 0:stride:(length(nodes) - stride)
        name = String(names[Int(nodes[offset + type_index]) + 1])
        bytes[name] = get(bytes, name, 0) + Int(nodes[offset + size_index])
        counts[name] = get(counts, name, 0) + 1
    end
    [Dict("type" => name, "objects" => counts[name], "shallow_bytes" => bytes[name])
     for name in sort!(collect(keys(bytes)); by = n -> bytes[n], rev = true)]
end
if first(heap)["status"] == "complete"
    artifact = only(first(heap)["artifacts"])
    summary = heap_summary(artifact["path"])
    open(
        io -> JSON.print(io,
            Dict("types" => summary, "artifact_sha256" => artifact["sha256"],
                "scope" => "GC-managed objects in the whole worker; shallow sizes, not retained dominator sizes"),
            2),
        joinpath(output, "heap-types.json"),
        "w")
    export_heap_observations(output)
end
println("Published quality findings and heap-category observations")
