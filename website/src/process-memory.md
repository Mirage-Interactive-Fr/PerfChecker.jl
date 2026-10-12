# Process and external memory

Allocated bytes, live bytes and resident memory describe different stages of an object's life. Keep them apart.

- **Allocated bytes** — memory obtained during the operation.
- **Live bytes** — memory still retained afterwards.
- **Resident memory (RSS)** — the part of the process currently in physical RAM.
- **Private memory** — memory private to the process, by the OS definition below.
- A **peak** counter can cover the whole process lifetime, not just the last workload.

For Bibliography, reducing temporary export buffers can lower Julia allocation counts without lowering resident memory: the allocator may keep capacity for reuse. Conversely, a native dependency can grow process memory without appearing in Julia allocation counters.

PerfChecker keeps three questions separate:

1. How many Julia allocations does the operation perform?
2. How does the worker's resident/private memory change?
3. How many bytes does a package own outside Julia's heap?

No counter is a proxy for another.

## Inspect a recorded memory diagnostic

```@raw html
<InteractiveRecordedPlot source="/examples/real-packages/oxygen-diagnostics/memory.plot.json" html="/examples/real-packages/oxygen-diagnostics/memory.html" title="Oxygen reachable-object sizes and resident process memory" kind="observation_series" />
```

Select a panel to keep its scale and unit visible. The first observation in
the [saved memory diagnostic](examples/real-packages/oxygen-diagnostics/diagnosis.json)
contains these actual byte counts:

| Quantity | Before | After |
| --- | --- | --- |
| Reachable scenario state | 27,856 B | 28,264 B |
| Process RSS (`windows-psapi`) | 536,616,960 B | 532,635,648 B |
| Process private memory | 612,425,728 B | 606,199,808 B |
| Lifetime peak RSS | 550,666,240 B | 550,666,240 B |

Reachable state grows by **408 B** while RSS decreases. Neither change is an
allocation count or proof of a leak. State plus its result occupies **55,852 B**;
that reachable-object size does not include all resident process memory.

This completed diagnostic passed its oracle on Windows, Julia 1.13.0 and one
thread. Its older record omits the exact Oxygen revision and dependency
manifest, so it cannot identify a release regression. Its snapshots surround
individual diagnostic operations. The feature envelope below instead
surrounds a complete backend collection; these are different boundaries.

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

## Recorded examples

```@raw html
<figure class="doc-screenshot">
<InteractiveRecordedPlot source="/examples/bibliography/history/export-memory.json" html="/examples/bibliography/history/export-memory.html" title="Julia allocated bytes per Bibliography export across nine tagged versions" kind="version_series" />
<figcaption>Native interactive export of Julia allocated bytes per export across nine tags, from 4,480 to 8,352 bytes. These values measure allocation activity, not retained heap size or resident process memory.</figcaption>
</figure>
```
