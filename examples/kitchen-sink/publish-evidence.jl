using JSON, SHA
root = normpath(joinpath(@__DIR__, "../../website/src/public/examples/real-packages"))
for package in ("datastructures", "oxygen")
    directory = joinpath(root, package)
    catalog = JSON.parsefile(joinpath(directory, "catalog.json"))
    entry = only(filter(catalog["views"]) do row
        row["kind"] == "normalized_metrics" &&
            get(row, "workload", "") in ("heap_2048", "heap_request") &&
            startswith(get(row, "collector", ""), "benchmarktools-v1")
    end)
    for format in ("json", "svg")
        cp(joinpath(directory, entry[format]), joinpath(directory, "normalized." * format); force = true)
    end
end
cp(joinpath(@__DIR__, "notebook.jl"), joinpath(root, "notebook.jl"); force = true)
for name in ("datastructures-notebook.jl", "oxygen-notebook.jl")
    cp(joinpath(@__DIR__, name), joinpath(root, name); force = true)
end
println("Published the overlay aliases and the three downloadable notebooks")
