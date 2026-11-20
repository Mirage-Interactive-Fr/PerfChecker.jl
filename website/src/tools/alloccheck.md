# AllocCheck

Inspect possible allocations in a specialization separately from the timing campaign.

From `examples/kitchen-sink` in the source checkout, run `julia setup.jl analyzers`. Then start Julia with `julia --project=.controller/analyzers` for the code below.

```julia
using PerfChecker
catalog = load_scenario_catalog("scenarios.toml")
heap = select_scenarios(catalog,
    [Dict("id"=>"events-heap", "implementation"=>"datastructures")])
result = diagnose(heap; project=dirname(Base.active_project()), threads=1,
    tools=[:alloccheck], reports="results/heap-alloccheck")
display(only(result["records"]))
```

```@raw html
<p>The <a href="../examples/real-packages/datastructures-diagnostics/diagnosis.json">saved diagnostic JSON</a>, recorded on Julia 1.13.0, contains: AllocCheck 0.2.6 completed with <strong>6 potential-allocation findings</strong> and a passing oracle.</p>
```

The findings include vector/memory allocations in `drain_heap` and `BinaryHeap`. Static findings are not measured byte totals.
