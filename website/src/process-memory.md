# Process and external memory

Memory measurements describe different stages of an object's life. Allocated
bytes count memory obtained during an operation; live bytes concern what is
still retained. **Resident memory** is the portion of a process currently in
physical RAM. **Private memory** concerns memory private to that process, with
the exact operating-system definition recorded below. A peak counter can cover
the whole process lifetime, not just the last workload.

For Bibliography, reducing temporary export buffers can lower Julia allocation
counts without immediately reducing the worker's resident memory: the runtime
or allocator may keep capacity for later reuse. Conversely, a native dependency
can grow process memory without appearing in Julia allocation counters. Use
these readings together and keep their scopes distinct. The
[measurement tutorial](guide/understanding-measurements.md) introduces allocation
and garbage collection before the contracts below.

PerfChecker keeps three questions separate:

1. how many Julia allocations the measured operation performs;
2. how the isolated worker process' resident/private memory changes;
3. how many bytes a package explicitly owns outside Julia's heap.

No counter is used as a proxy for another one.


```@raw html
<DocMedia src="/examples/bibliography/figures/history-memory.svg" alt="Allocated bytes per Bibliography export across nine tags, from 4480 bytes at 0.1.0 to 8352 at 0.4.0" caption="Julia allocation activity per operation. These values are neither retained heap size nor resident process memory. All nine points come from recorded measurements." />
```

## Process envelope

To add process observation, enable `:process_resources` on a feature in your
existing software suite. This fragment uses the Bibliography export workload
from the prepared example; run from `examples/bibliography/` and attach the
feature to a package suite as explained in [software suites](software-suites.md):

```julia
using PerfChecker
feature = FeatureSpec(:export_bibtex;
    entrypoint = abspath(".sources/Bibliography/perf/features/export_bibtex.jl"),
    options = Dict(
        :samples => 20,
        :process_resources => true,
    ))
```

The controller takes snapshots of the isolated Malt worker immediately before
and after the backend collection. `process_memory_snapshot()` exposes the same
platform adapter for diagnostics. `process_memory_capabilities()` says which
counters the current platform can provide.

| Platform | Current resident memory | Peak | Private memory |
| --- | --- | --- | --- |
| Windows | PSAPI `WorkingSetSize` | process-lifetime `PeakWorkingSetSize` | committed private bytes (`PrivateUsage`) |
| Linux | `/proc/<pid>/status` `VmRSS` | process-lifetime `VmHWM` | private mappings from `smaps_rollup`, when readable |
| Other | `unavailable` | `unavailable` | `unavailable` |

An unsupported or inaccessible counter stays absent. A platform failure produces
an informational `resource.process.unavailable` diagnostic instead of a fabricated
zero.

The envelope surrounds the complete backend collection, not each BenchmarkTools
sample. Feature setup and correctness probes run before it. Backend-controlled
warmup or compilation can still occur inside the envelope, so the bundle marks
this boundary explicitly. A process peak is never reset: the `new_lifetime_peak`
metric records only how much the high-water mark advanced during the collection.

## External-memory contract

Packages with native handles, pools, mapped arenas or device staging memory can
provide an ownership ledger without depending on PerfChecker in the worker. Name
the callback in the feature options:

```julia
FeatureSpec(:step_native;
    entrypoint = "perf/features/step_native.jl",
    options = Dict(
        :process_resources => true,
        :external_memory_probe => :perf_external_memory,
        :external_memory_required => true,
        :resource_upper_limits => Dict(
            :external_live_delta_bytes => 0,
        ),
        :require_external_balance => true,
    ))
```

The following is an adapter contract example, not a Bibliography measurement.
`ledger` must be supplied by the native-memory owner; PerfChecker cannot infer
it from Julia allocation counters. The entrypoint defines a zero-argument callback. It may close over the state that
`perf_setup()` placed in the worker:

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

All byte values are non-negative integers. `live_bytes` and `reserved_bytes` are
gauges; their signed deltas may be negative. `allocated_bytes_total` and
`freed_bytes_total` are monotonic counters and decreasing values invalidate the
envelope. Fields may be omitted only when the owner genuinely cannot observe
them. At least one counter is required for an `observed` snapshot.

With `:external_memory_required => false` (the default), a missing or faulty
callback becomes an informational `resource.external.unavailable` diagnostic.
With `true`, it fails the feature. This lets exploratory suites remain portable
while making native-memory evidence mandatory in release gates.

`resource_upper_limits` turns selected envelope metrics into absolute per-run
gates. `require_external_balance` additionally requires the workload's monotonic
allocated and freed deltas to match and forbids growth in live external bytes.
The resulting `perfchecker-resource-policy-evaluation/1` evidence lives under
the run's performance qualification. A violation makes the feature `invalid`
while retaining its envelope for diagnosis. This gate remains independent from
the backend's Julia allocation columns: zero Julia allocations cannot hide a
native leak, and native balance cannot hide Julia heap churn.

## Bundle metrics

Run bundles store the resource envelope as ordinary versioned observations, with
`scope = isolated_worker_process` and `aggregation = collector_envelope`.
Important definitions include:

- `process.rss.before/v1`, `process.rss.after/v1`, and `process.rss.delta/v1`;
- `process.rss.peak_lifetime_after/v1` and
  `process.rss.new_lifetime_peak/v1`;
- `process.private.delta/v1`;
- `external.live.after/v1` and `external.live.delta/v1`;
- `external.reserved.delta/v1`;
- `external.allocated.delta/v1` and `external.freed.delta/v1`.

This makes a result such as "zero Julia allocations, zero external live-byte
growth, stable RSS" expressible as three independent assertions rather than one
ambiguous memory claim.
