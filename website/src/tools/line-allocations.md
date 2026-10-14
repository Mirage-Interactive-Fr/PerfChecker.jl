# Line allocations

Attribute Julia allocation bytes to source lines with the legacy `:alloc` collector.

From `examples/kitchen-sink` in the source checkout, run `julia setup.jl core`. Then start Julia with `julia --project=.` for the code below.

```julia
using PerfChecker
include("suite.jl")
plan = plan_suite(build_suite(); profile=:historical,
    version_provider=_ -> KITCHEN_VERSIONS)
selected = filter_suite_plan(plan; features=[:heap_32768_alloc],
    from_version=v"0.19.6", to_version=v"0.19.6")
result = run_suite_repl(selected; reports="results/line-allocations")
```

The saved DataStructures 0.19.6 line-allocation heatmap shows the recorded source attribution:

```@raw html
<InteractiveRecordedPlot source="/examples/real-packages/datastructures-profiles/allocation-heatmap-cb164d1392b342ff.json" html="/examples/real-packages/datastructures-profiles/allocation-heatmap-cb164d1392b342ff.html" title="DataStructures line allocations" kind="allocation_heatmap" />
```

Totals reflect the collection scope and repetition. They are not interchangeable with sampled allocation-profile bytes or per-call benchmark allocations.

::: details Trace cleanup and cancellation

Julia creates `source.jl.<worker-pid>.mem` files beside executed sources. PerfChecker removes the current worker's new traces after success, errors and cancellation, and restores overwritten pre-existing traces. Other processes' files are preserved. For async suites, call `cancel_suite!(job)` then `wait_suite(job)`; a cancellation request does not mean cleanup finished. A cleanup error retains an inventory and journal at the reported paths. A killed controller or power loss can leave traces; inspect ownership before recovering them. A synthetic `include_string` filename outside the known source roots is not covered.

:::
