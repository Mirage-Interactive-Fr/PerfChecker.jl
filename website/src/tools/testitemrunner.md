# TestItemRunner

Measure a tagged whole test item, including its setup and assertions. Run this
selection from `examples/bibliography`. Prepare its item environment, then
start Julia in that environment before evaluating the code:

```sh
julia setup.jl items
julia --project=.controller/items
```

```julia
using PerfChecker, TestItemRunner
listing = discover_testitems(pwd())
selected = filter(item -> item["name"] == "Bibliography export workload",
    listing["items"])
@assert length(selected) == 1
result = run_testitems(pwd(); ids=[only(selected)["id"]], samples=1,
    threads=1, timeout=180, reports="results/export-item")
@assert result["passed"]
```

```@raw html
<p>The <a href="../examples/bibliography/vscode/capture.json">recorded native execution receipt</a>
records real extension activation, shared/performance item discovery, the actual
Bibliography export-item profile handler and <strong>1993.05 ms</strong> delivered to the
native Testing API. That is a whole-item observation, including setup and
assertions; it is not the export-operation timing curve. The
<a href="../tutorials/bibliography.html">Bibliography tutorial</a> explains the item selection.</p>
```

For a DataStructures item, run from `examples/kitchen-sink`:

```sh
julia setup.jl core
julia --project=. items.jl list
julia --project=. items.jl run queue
```

This second recipe is runnable but has no separately published queue-item
receipt; the container operation charts cannot establish its whole-item cost.
