# SnoopCompile

Inspect inference work on a first execution separately from the timing campaign.

From `examples/kitchen-sink` in the source checkout, run `julia setup.jl analyzers`. Then start Julia with `julia --project=.controller/analyzers` for the code below.

```julia
using PerfChecker
catalog = load_scenario_catalog("scenarios.toml")
heap = select_scenarios(catalog,
    [Dict("id"=>"events-heap", "implementation"=>"datastructures")])
result = diagnose(heap; project=dirname(Base.active_project()), threads=1,
    tools=[:snoopcompile], reports="results/heap-snoopcompile")
display(only(result["records"]))
```

```@raw html
<p>The <a href="../examples/real-packages/datastructures-diagnostics/diagnosis.json">saved diagnostic JSON</a>, recorded on Julia 1.13.0, contains: SnoopCompile 3.2.9 completed with <strong>1 inference record</strong>, <strong>0.000004708766937255859 s</strong>, and a passing oracle.</p>
```

The record covers the first complete lifecycle in the diagnostic worker, rather than warmed operation timing.
