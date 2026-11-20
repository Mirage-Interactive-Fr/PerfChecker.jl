using JSON
include(joinpath(@__DIR__, "observation-export.jl"))
length(ARGS) == 2 ||
    error("Pass a network JSON file (or history directory) and an export directory")
source, output = abspath.(ARGS)
files = isdir(source) ? filter(f -> endswith(f, ".json"), readdir(source; join = true)) :
        [source]
records = [JSON.parsefile(file) for file in files]
sort!(records; by = r -> VersionNumber(r["version"]))
isempty(records) && error("No network observations")
mkpath(output)
latest = last(records)
open(io -> JSON.print(io, latest, 2), joinpath(output, "latest.json"), "w")
open(io -> JSON.print(io, Dict("versions" => records), 2),
    joinpath(output, "history.json"), "w")

export_network_observations(output)
println("Exported actual network observations for ", length(records), " releases")
