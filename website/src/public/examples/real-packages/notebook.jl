### A Pluto.jl notebook ###
# v0.20.0

using Markdown
using InteractiveUtils

# ╔═╡ 79c7db1d-20e8-4607-9607-c32bb3bcab01
begin
    import Pkg
    # Run setup.jl pluto once before opening this notebook.
    example_root = get(ENV, "PERFCHECKER_EXAMPLE_ROOT", @__DIR__)
    Pkg.activate(joinpath(example_root, ".controller", "pluto"))
    using PerfChecker, PerfCheckerMakie, WGLMakie, PlutoUI, JSON, UnicodePlots
    include(joinpath(example_root, "replay.jl"))
end

# ╔═╡ 79c7db1d-20e8-4607-9607-c32bb3bcab02
md"""# Explore a recorded package experiment
Choose the published DataStructures/Oxygen measurements, or a completed local report. Changing a plot only
reads saved measurements. No benchmarks or HTTP services start in this notebook.
For a controller with launch buttons, use `controller-notebook.jl`.
"""

# ╔═╡ 79c7db1d-20e8-4607-9607-c32bb3bcab03
report_paths = let
    public_root = normpath(joinpath(example_root, "../../website/src/public/examples/real-packages"))
    published = [joinpath(public_root, name) for name in
        ("datastructures", "oxygen", "datastructures-profiles", "oxygen-profiles")
        if isfile(joinpath(public_root, name, "catalog.json"))]
    local_root = joinpath(example_root, "results")
    local_reports = isdir(local_root) ? filter(path -> isfile(joinpath(path, "suite-result.json")),
        readdir(local_root; join = true)) : String[]
    vcat(published, local_reports)
end

# ╔═╡ 79c7db1d-20e8-4607-9607-c32bb3bcab04
@bind report Select(report_paths .=> basename.(report_paths))

# ╔═╡ 79c7db1d-20e8-4607-9607-c32bb3bcab05
bundle = isfile(joinpath(report, "catalog.json")) ? nothing : example_bundle(report)

# ╔═╡ 79c7db1d-20e8-4607-9607-c32bb3bcab06
catalog = bundle === nothing ? JSON.parsefile(joinpath(report, "catalog.json"))["views"] : plot_catalog(bundle)

# ╔═╡ 79c7db1d-20e8-4607-9607-c32bb3bcab07
@bind selected Select([row["id"] => string(row["title"], " · ", row["label"]) for row in catalog])

# ╔═╡ 79c7db1d-20e8-4607-9607-c32bb3bcab08
model = bundle === nothing ? saved_plot(joinpath(report, selected * ".json")) : performance_plot(bundle, selected)

# ╔═╡ 79c7db1d-20e8-4607-9607-c32bb3bcab09
performance_figure(model)

# ╔═╡ 79c7db1d-20e8-4607-9607-c32bb3bcab10
terminal_plot(model)

# ╔═╡ 79c7db1d-20e8-4607-9607-c32bb3bcab11
md"""The overlay divides each metric by its own minimum across versions.
Time, GC time, bytes and allocation count retain their different units in the
raw data. A zero GC minimum does not mean that garbage collection is free:
the recorded samples may simply contain no collection. Profiles describe where
sampled work occurred; their overhead makes them unsuitable as timing baselines.
"""

# ╔═╡ Cell order:
# ╠═79c7db1d-20e8-4607-9607-c32bb3bcab01
# ╟─79c7db1d-20e8-4607-9607-c32bb3bcab02
# ╠═79c7db1d-20e8-4607-9607-c32bb3bcab03
# ╠═79c7db1d-20e8-4607-9607-c32bb3bcab04
# ╠═79c7db1d-20e8-4607-9607-c32bb3bcab05
# ╠═79c7db1d-20e8-4607-9607-c32bb3bcab06
# ╠═79c7db1d-20e8-4607-9607-c32bb3bcab07
# ╠═79c7db1d-20e8-4607-9607-c32bb3bcab08
# ╠═79c7db1d-20e8-4607-9607-c32bb3bcab09
# ╠═79c7db1d-20e8-4607-9607-c32bb3bcab10
# ╟─79c7db1d-20e8-4607-9607-c32bb3bcab11
