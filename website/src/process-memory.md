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
<DocMedia src="/examples/bibliography/figures/history-memory.svg" alt="Allocated bytes per Bibliography export across nine tags, from 4480 bytes at 0.1.0 to 8352 at 0.4.0" caption="Julia allocation activity per operation. These values are neither retained heap size nor resident process memory. All nine points come from recorded measurements." />
```


```@raw html
<a id="External-memory-contract"></a>
```
