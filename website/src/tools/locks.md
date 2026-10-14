# Locks

Inspect lock conflicts separately from the timing campaign.

From `examples/kitchen-sink` in the source checkout, run `julia setup.jl core`. Then start Julia with `julia --project=.` for the code below.

```julia
using PerfChecker
catalog = load_scenario_catalog("scenarios.toml")
heap = select_scenarios(catalog,
    [Dict("id"=>"events-heap", "implementation"=>"datastructures")])
result = diagnose(heap; project=dirname(Base.active_project()), threads=1,
    tools=[:locks], reports="results/heap-locks")
display(only(result["records"]))
```

```@raw html
<p>The <a href="../examples/real-packages/datastructures-diagnostics/diagnosis.json">saved diagnostic JSON</a>, recorded on Julia 1.13.0, contains: <strong>0 lock conflicts</strong>, <strong>0.0002074 s operation time</strong>. Execution completed and the oracle passed.</p>
```

This single-threaded workload does not exercise contention; zero conflicts cannot qualify a threaded path.

```@raw html
<InteractiveRecordedPlot source="/examples/real-packages/datastructures-diagnostics/locks.plot.json" html="/examples/real-packages/datastructures-diagnostics/locks.html" title="DataStructures locks observations" />
```
