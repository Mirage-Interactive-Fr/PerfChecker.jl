using PerfChecker, UnicodePlots, JSON

"Load one saved bundle from a report directory, or a bundle directory itself."
function example_bundle(path)
    directory = isfile(joinpath(path, "manifest.json")) ? path :
        only(filter(isdir, readdir(joinpath(path, "bundles"); join = true)))
    verify_run_bundle(directory; require_integrity = true)
    read_run_bundle(directory)
end

"Restore a published, backend-neutral plot without running its workload."
function saved_plot(path)
    record = JSON.parsefile(path)
    d = get(record, "plot", record)
    d["schema_version"] == "perfchecker-plot/1" || error("Unsupported plot format")
    PerfChecker.PerformancePlot(d["id"], Symbol(d["kind"]), d["title"], d["description"],
        Dict{String, Any}(d["encoding"]), Dict{String, Any}[Dict(row) for row in d["data"]],
        Dict{String, Any}(d["options"]))
end

if abspath(PROGRAM_FILE) == @__FILE__
    isempty(ARGS) && error("Pass a report directory or a published plot.json, optionally an output directory")
    output = length(ARGS) > 1 ? abspath(ARGS[2]) : joinpath(@__DIR__, "exports", "terminal")
    mkpath(output)
    plots = if endswith(ARGS[1], ".json")
        [saved_plot(ARGS[1])]
    else
        bundle = example_bundle(abspath(ARGS[1]))
        [performance_plot(bundle, entry["id"]) for entry in plot_catalog(bundle)]
    end
    for model in plots
        text = sprint(show, MIME"text/plain"(), terminal_plot(model); context = :color => false)
        write(joinpath(output, model.id * ".txt"), text)
        println(model.title, "\n", text)
    end
    println("Saved ", length(plots), " terminal plots to ", output)
end
