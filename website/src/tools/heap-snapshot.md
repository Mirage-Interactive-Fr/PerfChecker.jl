# Heap snapshot

Capture GC-managed objects in the diagnostic worker after scenario verification.

From `examples/kitchen-sink` in the source checkout, run `julia setup.jl core`. Then start Julia with `julia --project=.` for the code below.

```julia
using PerfChecker
catalog = load_scenario_catalog("scenarios.toml")
heap = select_scenarios(catalog,
    [Dict("id"=>"events-heap", "implementation"=>"datastructures")])
snapshot = diagnose(heap; project=dirname(Base.active_project()), tools=[:heap],
    threads=1, timeout=180, reports="results/heap-snapshot")
display(only(snapshot["records"]))
```

```@raw html
<p>The <a href="../examples/real-packages/datastructures-diagnostics/additional.json">recorded receipt</a> records a completed capture, passing oracle and <strong>190,003,317-byte redacted snapshot</strong>.</p>
```

```@raw html
<InteractiveRecordedPlot source="/examples/real-packages/datastructures-diagnostics/heap-types.plot.json" html="/examples/real-packages/datastructures-diagnostics/heap-types.html" title="Recorded GC heap object categories" />
```

The snapshot covers the whole worker's GC heap. It excludes native/device memory and does not measure allocation activity during one call.
