# Memory

Compare reachable Julia objects with whole-worker resident memory.

From `examples/kitchen-sink` in the source checkout, run `julia setup.jl core`. Then start Julia with `julia --project=.` for the code below.

```julia
using PerfChecker
catalog = load_scenario_catalog("scenarios.toml")
heap = select_scenarios(catalog,
    [Dict("id"=>"events-heap", "implementation"=>"datastructures")])
result = diagnose(heap; project=dirname(Base.active_project()), threads=1,
    tools=[:memory], reports="results/heap-memory")
display(only(result["records"]))
```

```@raw html
<p>The <a href="../examples/real-packages/datastructures-diagnostics/diagnosis.json">recorded DataStructures diagnostic</a> completed with a passing oracle: state before/after <strong>49,192 B</strong>, state and result <strong>98,400 B</strong>, RSS before <strong>262,897,664 B</strong> and after <strong>262,213,632 B</strong> (<code>windows-psapi</code>).</p>
```

```@raw html
<InteractiveRecordedPlot source="/examples/real-packages/datastructures-diagnostics/memory.plot.json" html="/examples/real-packages/datastructures-diagnostics/memory.html" title="DataStructures reachable memory" />
```

Allocated bytes count activity, reachable bytes describe retained objects, and RSS describes physical pages of the process. Neither a lower RSS sample nor live-object growth alone proves a leak or improvement. GPU/device memory has no implemented collector here.

::: details Process resources and external memory

## Process envelope

Enable `:process_resources` on a feature to snapshot the isolated worker immediately before and after its backend collection.

```julia
FeatureSpec(:export_bibtex;
    entrypoint = "perf/features/export_bibtex.jl",
    options = Dict(:samples => 20, :process_resources => true))
```

- **Windows** — `WorkingSetSize`, lifetime `PeakWorkingSetSize`, `PrivateUsage`.
- **Linux** — `VmRSS`, `VmHWM`, `smaps_rollup` private mappings.
- **Other platforms** — all three `unavailable`.

- An unsupported or inaccessible counter stays absent. A platform failure produces `resource.process.unavailable`, never a zero.
- The envelope surrounds the whole collection, not each sample.
- Backend warmup or compilation can still occur inside the envelope; the bundle marks this boundary.
- A process peak is never reset: `new_lifetime_peak` records only how much the high-water mark advanced.

`process_memory_snapshot()` exposes the same adapter for diagnostics; `process_memory_capabilities()` lists the available counters.

```@raw html
<a id="External-memory-contract"></a>
```

## External memory

A package with native handles, pools, mapped arenas or device staging memory can name a callback in the feature options:

```julia
FeatureSpec(:step_native;
    entrypoint = "perf/features/step_native.jl",
    options = Dict(
        :process_resources => true,
        :external_memory_probe => :perf_external_memory,
        :external_memory_required => true,
        :resource_upper_limits => Dict(:external_live_delta_bytes => 0),
        :require_external_balance => true,
    ))
```

The zero-argument callback implements `perfchecker-external-memory/1`:

```julia
function perf_external_memory()
    return (
        schema_version = "perfchecker-external-memory/1",
        status = "observed",
        live_bytes = ledger.live_bytes,
        reserved_bytes = ledger.reserved_bytes,
        allocated_bytes_total = ledger.allocated_bytes_total,
        freed_bytes_total = ledger.freed_bytes_total,
        provider = "my-native-ledger",
    )
end
```

- All byte values are non-negative integers.
- `live_bytes` and `reserved_bytes` are gauges; their signed deltas may be negative.
- `allocated_bytes_total` and `freed_bytes_total` are monotonic; a decreasing value invalidates the envelope.
- Fields may be omitted only when the owner genuinely cannot observe them; at least one is required for `observed`.
- With `:external_memory_required => false` (default), a missing callback becomes informational. With `true`, it fails the feature.

`resource_upper_limits` turns selected envelope metrics into absolute per-run gates. `require_external_balance` also requires monotonic allocated/freed deltas to match and forbids growth in live external bytes. A violation marks the feature `invalid` while keeping the envelope for diagnosis.

The callback above is an integration contract to implement in your package.
No native-ledger recording is published in this example; the process RSS and
reachable-state observations above do not supply that missing measurement.

## Bundle metrics

- `process.rss.before/v1`, `after/v1`, `delta/v1` — resident memory around the collection.
- `process.rss.peak_lifetime_after/v1`, `new_lifetime_peak/v1` — lifetime high-water mark.
- `process.private.delta/v1` — private memory change.
- `external.live.after/v1`, `external.live.delta/v1` — native live bytes.
- `external.reserved.delta/v1` — native reserved change.
- `external.allocated.delta/v1`, `external.freed.delta/v1` — native monotonic deltas.

This turns a vague claim such as "memory is fine" into three independent assertions: zero Julia allocations, zero external live-byte growth, stable RSS.

For a recorded four-metric export example, see the [Bibliography history](../tutorials/bibliography.md#Compare-the-package-history). Allocation activity and resident memory remain different quantities.

:::
