using PerfChecker, CairoMakie, JSON, UnicodePlots
include(joinpath(@__DIR__, "replay.jl"))
length(ARGS) == 3 || error("Pass BenchmarkTools reports, Chairmarks reports and an export directory")
sources = abspath.(ARGS[1:2])
output = abspath(ARGS[3])
mkpath(output)
bundles = example_bundle.(sources)
for source in sources
    result = JSON.parsefile(joinpath(source, "suite-result.json"))
    all(run["status"] == "pass" for run in result["runs"]) || error("Unsuccessful collector campaign")
end
collectors = ("BenchmarkTools", "Chairmarks")
version = "0.19.6"
records = Dict{String, Any}[]
for (collector, bundle) in zip(collectors, bundles)
    expected = collector == "BenchmarkTools" ? "benchmarktools-v1/" : "chairmarks-v1/"
    for entry in filter(item -> item["kind"] == "normalized_metrics", plot_catalog(bundle))
        startswith(entry["collector"], expected) || error("Unexpected collector in $collector reports")
        model = performance_plot(bundle, entry["id"])
        for row in model.data
            row["version"] == version || continue
            metric, value, unit = row["metric"], row["value"], row["unit"]
            derivation = "recorded minimum"
            if metric == "julia.wall.time"
                value *= unit == "s" ? 1e6 : unit == "ns" ? 1e-3 : error("Unexpected time unit: $unit")
                unit = "µs"
            elseif metric == "julia.gc.time"
                selected = filter(obs -> obs["target_id"] == version &&
                    get(obs["attributes"], "feature", "") == entry["feature"], bundle.observations)
                times = Dict(obs["sample_index"] => obs["value"] for obs in selected if obs["metric"] == "julia.wall.time")
                gc = filter(obs -> obs["metric"] == "julia.gc.time", selected)
                @assert length(times) == length(gc) == 30
                @assert all(obs["unit"] == row["unit"] for obs in selected if obs["metric"] in ("julia.gc.time", "julia.wall.time"))
                value = minimum(obs["value"] / times[obs["sample_index"]] for obs in gc) * 100
                metric, unit = "julia.gc.fraction", "%"
                derivation = "minimum of paired per-sample gc.time / wall.time; not a ratio of separate minima"
            elseif metric == "julia.gc.fraction"
                value *= 100
                unit = "%"
            end
            push!(records, Dict("workload" => entry["workload"], "collector" => collector,
                "metric" => metric, "value" => value, "unit" => unit, "derivation" => derivation,
                "source_metric" => row["metric"], "source_unit" => row["unit"],
                "samples" => row["samples"], "statistic" => row["statistic"], "version" => version,
                "comparison_key" => entry["comparison_key"], "collector_definition" => entry["collector"]))
        end
    end
end
@assert length(records) == 70 * 4 * 2
@assert all(row["samples"] == 30 for row in records)
for workload in unique(row["workload"] for row in records)
    @assert length(unique(row["comparison_key"] for row in records if row["workload"] == workload)) == 1
end
metrics = [("julia.wall.time", "Wall time (µs)", 1.0),
    ("julia.gc.fraction", "GC share (%)", 1.0),
    ("julia.alloc.bytes", "Allocated bytes", 1.0),
    ("julia.alloc.count", "Allocation count", 1.0)]
families = sort!(unique(first(split(row["workload"], '_')) for row in records))
views = Dict{String, Any}[]
for family in families
    rows = filter(row -> startswith(row["workload"], family * "_"), records)
    operations = sort!(unique(row["workload"] for row in rows))
    figure = Figure(size=(1100, 760))
    Label(figure[0, 1:2], "$family · two collectors · DataStructures $version"; fontsize=22)
    terminal = IOBuffer()
    for (index, (metric, label, scale)) in enumerate(metrics)
        values = [only(filter(row -> row["workload"] == operation && row["collector"] == collector && row["metric"] == metric, rows))["value"] * scale
            for operation in operations for collector in collectors]
        axis = Axis(figure[cld(index, 2), mod1(index, 2)]; ylabel=label,
            xticks=(1:2, [last(split(operation, '_')) for operation in operations]))
        CairoMakie.barplot!(axis, [1, 1, 2, 2], values; dodge=[1, 2, 1, 2],
            color=[:steelblue, :darkorange, :steelblue, :darkorange])
        axis.limits = (nothing, (0, maximum(values; init=0) > 0 ? maximum(values) * 1.15 : 1))
        labels = [last(split(operation, '_')) * " · " * collector for operation in operations for collector in collectors]
        println(terminal, label)
        show(terminal, MIME"text/plain"(), UnicodePlots.barplot(labels, values; title=family, width=60))
        println(terminal)
    end
    Legend(figure[3, 1:2], [PolyElement(color=:steelblue), PolyElement(color=:darkorange)], collect(collectors); orientation=:horizontal)
    Label(figure[4, 1:2], "Minimum of 30 samples · fresh state · one evaluation · separate collector semantics"; fontsize=13)
    name = lowercase(family)
    save(joinpath(output, name * ".svg"), figure)
    open(io -> JSON.print(io, Dict("version"=>version, "family"=>family, "records"=>rows,
        "correctness"=>"passed", "scope"=>"Separate collector sessions on one local machine; not a collector speed verdict",
        "run_ids"=>[bundle.manifest["run_id"] for bundle in bundles]), 2), joinpath(output, name * ".json"), "w")
    write(joinpath(output, name * ".txt"), join(rstrip.(split(String(take!(terminal)), '\n')), '\n'))
    push!(views, Dict("id"=>name, "title"=>family, "label"=>"BenchmarkTools and Chairmarks",
        "svg"=>name*".svg", "json"=>name*".json", "terminal"=>name*".txt"))
end
open(io -> JSON.print(io, Dict("views"=>views, "version"=>version, "samples"=>30,
    "operations"=>70, "collectors"=>collect(collectors)), 2), joinpath(output, "catalog.json"), "w")
println("Exported ", length(views), " collector comparison figures with all four measurements")
