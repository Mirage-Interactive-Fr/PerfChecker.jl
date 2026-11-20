# Chairmarks

Measure a repeatable operation across package releases.

From `examples/kitchen-sink` in the source checkout, run `julia setup.jl core`. Then start Julia with `julia --project=.` for the code below.

```julia
using PerfChecker, Chairmarks
include("suite.jl")
plan = plan_suite(build_suite(); profile=:historical,
    version_provider=_ -> KITCHEN_VERSIONS)
selected = filter_suite_plan(plan; features=[:heap_2048_chairmark],
    from_version=v"0.19.5", to_version=v"0.19.6")
result = run_suite_repl(selected; reports="results/heap-chairmark")
@assert suite_passed(result)
```

The saved DataStructures recording below covers **20 real releases**, with 30 warmed samples per target. Preparation and verification stay outside the timed operation. Four individually normalized metrics overlay wall time, allocated bytes, allocation count and **GC fraction**. The short reproduction selects two of those releases.

```@raw html
<NormalizedMeasurements source="/examples/real-packages/datastructures/normalized-metrics-2733e6d4863b6def.json" html="/examples/real-packages/datastructures/normalized-metrics-2733e6d4863b6def.html" package-name="DataStructures heap · Chairmarks" />
```

A zero reference has no finite ratio; raw zero observations are retained. Keep BenchmarkTools and Chairmarks distributions separate: their GC units differ.

::: details Sampling and comparability

Fresh state requires `evals=1`; collector sampling uses explicit `samples`, `evals` and other backend options. Neither backend uses the generic `repeat` warmup preference. Compare only matching measurement definitions and comparison keys; changing inputs, warmup or operation boundaries requires a new key. [Saved results](results.md) explains comparisons and integrity.

:::
