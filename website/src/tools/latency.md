# Latency

Inspect loading and first-use costs separately from the timing campaign.

From `examples/kitchen-sink` in the source checkout, run `julia setup.jl core`. Then start Julia with `julia --project=.` for the code below.

```julia
using PerfChecker
catalog = load_scenario_catalog("scenarios.toml")
heap = select_scenarios(catalog,
    [Dict("id"=>"events-heap", "implementation"=>"datastructures")])
result = diagnose(heap; project=dirname(Base.active_project()), threads=1,
    tools=[:latency], reports="results/heap-latency")
display(only(result["records"]))
```

```@raw html
<p>The <a href="../examples/real-packages/datastructures-diagnostics/diagnosis.json">saved diagnostic JSON</a>, recorded on Julia 1.13.0, contains: Load <strong>0.6490315 s</strong>; first lifecycle <strong>0.1709083 s</strong>; warm lifecycle <strong>0.0002009 s</strong>. Execution completed and the oracle passed.</p>
```

Loading, first execution and warm execution have different boundaries; keep them separate.

```@raw html
<InteractiveRecordedPlot source="/examples/real-packages/datastructures-diagnostics/latency.plot.json" html="/examples/real-packages/datastructures-diagnostics/latency.html" title="DataStructures latency observations" />
```
