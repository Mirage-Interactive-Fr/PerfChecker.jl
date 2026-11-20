# GC

Inspect allocation and garbage-collection activity separately from the timing campaign.

From `examples/kitchen-sink` in the source checkout, run `julia setup.jl core`. Then start Julia with `julia --project=.` for the code below.

```julia
using PerfChecker
catalog = load_scenario_catalog("scenarios.toml")
heap = select_scenarios(catalog,
    [Dict("id"=>"events-heap", "implementation"=>"datastructures")])
result = diagnose(heap; project=dirname(Base.active_project()), threads=1,
    tools=[:gc], reports="results/heap-gc")
display(only(result["records"]))
```

```@raw html
<p>The <a href="../examples/real-packages/datastructures-diagnostics/diagnosis.json">saved diagnostic JSON</a>, recorded on Julia 1.13.0, contains: <strong>98,494 allocated bytes</strong>, <strong>0 s GC</strong>, <strong>0.0001555 s operation time</strong>. Execution completed and the oracle passed.</p>
```

A zero GC sample does not show that the operation allocated nothing.

```@raw html
<InteractiveRecordedPlot source="/examples/real-packages/datastructures-diagnostics/gc.plot.json" html="/examples/real-packages/datastructures-diagnostics/gc.html" title="DataStructures gc observations" />
```
