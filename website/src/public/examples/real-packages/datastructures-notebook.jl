### A Pluto.jl notebook ###
# v0.20.0
using Markdown
using InteractiveUtils

# ╔═╡ d94ace53-1a4d-4c46-91c7-444570010001
begin
    import Pkg
    example_root = get(ENV, "PERFCHECKER_EXAMPLE_ROOT", @__DIR__)
    Pkg.activate(joinpath(example_root, ".controller/pluto"))
    using PerfChecker, PerfCheckerMakie, WGLMakie, PlutoUI, JSON, UnicodePlots
    include(joinpath(example_root, "src/containers.jl"))
    include(joinpath(example_root, "replay.jl"))
end

# ╔═╡ d94ace53-1a4d-4c46-91c7-444570010002
md"""# DataStructures: construct, check, compare, investigate
Run `julia +1.12 setup.jl pluto` from the example directory before opening this file.
Keep the downloaded notebook in `examples/kitchen-sink`, or set `PERFCHECKER_EXAMPLE_ROOT`.

We compare 35 containers on all seven 0.19 releases. Construction and subsequent
use are separate experiments. Every measured sample gets fresh prepared state;
the correctness oracle runs outside the measured operation.
"""

# ╔═╡ d94ace53-1a4d-4c46-91c7-444570010003
@bind family Select(ContainerCases.FAMILIES)

# ╔═╡ d94ace53-1a4d-4c46-91c7-444570010004
@bind operation Select(["build", ContainerCases.operation_name(family)])

# ╔═╡ d94ace53-1a4d-4c46-91c7-444570010005
begin
    case = ContainerCases.container_case(family, operation; n = 512)
    state = case.prepare()
    answer = case.operation(state)
    correct = case.verify(state, answer)
    @assert correct
    (container = family, operation = operation, input_size = 512, oracle_passed = correct)
end

# ╔═╡ d94ace53-1a4d-4c46-91c7-444570010006
md"""## Run this experiment on your machine
The cell above checks one answer; it is not a benchmark. In a terminal:
```sh
julia --project=. containers.jl check
julia --project=. containers.jl plan
julia --project=. containers.jl quick Deque_drain_benchmark
julia --project=. containers.jl history Deque_drain_benchmark
julia --project=. containers.jl chairmarks Deque_drain_chairmark
```
Replace the case name with your selection. Omit it to run all 70 cases. The
history records 30 warmed samples per case and release; it does not execute just once.
The seven-version matrix runs outside this notebook, so opening it does not start a campaign.
"""

# ╔═╡ d94ace53-1a4d-4c46-91c7-444570010007
begin
    public_root = normpath(joinpath(example_root, "../../website/src/public/examples/real-packages"))
    figure_root = joinpath(public_root, "containers")
    catalog = JSON.parsefile(joinpath(figure_root, "catalog.json"))
    matching = filter(row -> get(row, "workload", "") == family * "_" * operation && row["kind"] == "normalized_metrics", catalog["views"])
    overlay = saved_plot(joinpath(figure_root, only(matching)["json"]))
end

# ╔═╡ d94ace53-1a4d-4c46-91c7-444570010008
performance_figure(overlay)

# ╔═╡ d94ace53-1a4d-4c46-91c7-444570010009
terminal_plot(overlay)

# ╔═╡ d94ace53-1a4d-4c46-91c7-444570010010
md"""## Read the four curves
Wall time is elapsed operation time. Garbage-collection time is time attributed
to reclaiming Julia objects. Allocation count and allocated bytes describe
allocation activity, not resident memory. Each metric is divided by its own
minimum across versions; inspect raw data before interpreting a ratio.

Thirty samples expose short-term variation but do not establish a regression by
themselves. Repeat an adjacent pair on an otherwise idle machine. Profiles add
overhead and must not replace ordinary timing measurements.
"""

# ╔═╡ d94ace53-1a4d-4c46-91c7-444570010011
@bind detailed_view Select([row["id"] => string(row["title"], " · ", row["label"]) for row in catalog["views"]])

# ╔═╡ d94ace53-1a4d-4c46-91c7-444570010012
performance_figure(saved_plot(joinpath(figure_root, detailed_view * ".json")))

# ╔═╡ d94ace53-1a4d-4c46-91c7-444570010013
md"""## Explain a change, then check it again
```sh
julia --project=. measure.jl profiles
julia setup.jl analyzers
julia --project=.controller/analyzers scenarios.jl diagnose datastructures events-heap
julia setup.jl extras
julia --project=.controller/extras corpus.jl
julia --project=.controller/extras drwatson.jl run datastructures
```
JET examines inference; AllocCheck identifies possible allocation sites;
SnoopCompile examines compilation. GC, memory and lock diagnostics observe
different resources. A flame graph shows aggregated call paths, not a timeline.
The property-testing corpus adds correctness inputs; DrWatson caches an explicitly
identified experiment. Neither a cache hit nor a profiler run is a fresh timing result.

## Open the same evidence elsewhere
```sh
julia --project=. replay.jl results/YOUR-RUN
julia setup.jl web
julia --project=.controller/web web.jl results/YOUR-RUN
```
In VS Code, open the example folder and select the suite and individual perf items.
The full guide includes the commands for generating a controller notebook and
for exporting SVG, JSON, Unicode, Speedscope and pprof files.
"""

# ╔═╡ d94ace53-1a4d-4c46-91c7-444570010014
md"""## Inspect the saved profiles and diagnostics
These profiles describe the 32,768-element heap lifecycle, not the selected
512-element container operation. Allocation pies combine sites below 5% into
**Other allocation sites**. Flame graphs show aggregated call paths.
The following selector opens the same saved plot model as the website and Studio.
"""

# ╔═╡ d94ace53-1a4d-4c46-91c7-444570010015
profile_catalog = JSON.parsefile(joinpath(public_root, "datastructures-profiles", "catalog.json"))

# ╔═╡ d94ace53-1a4d-4c46-91c7-444570010016
@bind profile_view Select([row["json"] => row["title"] * " · " * row["label"] for row in profile_catalog["views"]])

# ╔═╡ d94ace53-1a4d-4c46-91c7-444570010017
performance_figure(saved_plot(joinpath(public_root, "datastructures-profiles", profile_view)))

# ╔═╡ d94ace53-1a4d-4c46-91c7-444570010018
@bind diagnostic_figure Select([
    "datastructures-diagnostics/latency.svg" => "Loading and first-call latency",
    "datastructures-diagnostics/gc.svg" => "Garbage collection",
    "datastructures-diagnostics/memory.svg" => "Reachable Julia memory",
    "datastructures-diagnostics/locks.svg" => "Observed lock conflicts",
    "datastructures-diagnostics/heap-types.svg" => "Whole-worker heap categories",
    "datastructures-native/massif-1.svg" => "Native heap, including process startup"])

# ╔═╡ d94ace53-1a4d-4c46-91c7-444570010019
PlutoUI.LocalResource(joinpath(public_root, diagnostic_figure))

# ╔═╡ d94ace53-1a4d-4c46-91c7-444570010020
(
    diagnostics=JSON.parsefile(joinpath(public_root, "datastructures-diagnostics", "diagnosis.json")),
    quality_and_heap=JSON.parsefile(joinpath(public_root, "datastructures-diagnostics", "additional.json")),
    native=JSON.parsefile(joinpath(public_root, "datastructures-native", "summary.json")),
)

# ╔═╡ Cell order:
# ╠═d94ace53-1a4d-4c46-91c7-444570010001
# ╟─d94ace53-1a4d-4c46-91c7-444570010002
# ╠═d94ace53-1a4d-4c46-91c7-444570010003
# ╠═d94ace53-1a4d-4c46-91c7-444570010004
# ╠═d94ace53-1a4d-4c46-91c7-444570010005
# ╟─d94ace53-1a4d-4c46-91c7-444570010006
# ╠═d94ace53-1a4d-4c46-91c7-444570010007
# ╠═d94ace53-1a4d-4c46-91c7-444570010008
# ╠═d94ace53-1a4d-4c46-91c7-444570010009
# ╟─d94ace53-1a4d-4c46-91c7-444570010010
# ╠═d94ace53-1a4d-4c46-91c7-444570010011
# ╠═d94ace53-1a4d-4c46-91c7-444570010012
# ╟─d94ace53-1a4d-4c46-91c7-444570010013
# ╟─d94ace53-1a4d-4c46-91c7-444570010014
# ╠═d94ace53-1a4d-4c46-91c7-444570010015
# ╠═d94ace53-1a4d-4c46-91c7-444570010016
# ╠═d94ace53-1a4d-4c46-91c7-444570010017
# ╠═d94ace53-1a4d-4c46-91c7-444570010018
# ╠═d94ace53-1a4d-4c46-91c7-444570010019
# ╠═d94ace53-1a4d-4c46-91c7-444570010020
