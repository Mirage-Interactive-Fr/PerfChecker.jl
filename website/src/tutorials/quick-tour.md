# Measure an operation

Time one operation with its input prepared **before** timing starts.

From a PerfChecker checkout:

```sh
cd examples/bibliography
julia --startup-file=no setup.jl
julia --startup-file=no --project=.controller/core run.jl benchmark Bibliography export_bibtex
```

The last command selects one package, one workload and one collector. It prints a report directory at the end:

```text
Reports: .../results/benchmark-<suffix>
```

Keep that directory: it holds the measurements and the source revisions they describe.

## Swap the collector, keep the workload

The operation stays the same; only what is recorded changes.

```sh
julia --startup-file=no --project=.controller/core run.jl profile_alloc Bibliography export_bibtex
```

Other collectors: `benchmark`, `chairmark`, `profile`, `wall_profile` (Julia 1.12+).

## Compare versions

```sh
julia --startup-file=no --project=.controller/core history.jl plan
julia --startup-file=no --project=.controller/core history.jl run
```

This runs nine Bibliography versions and four workloads. Earlier versions do not define every workload, so those combinations are `unavailable` — not slow, failed or zero.

## Read a result

- Benchmarks record time, allocated bytes, allocation count and GC time.
- Compare the **distribution**, not just the median. Overlapping samples are weak evidence.
- Allocated bytes count Julia allocation activity, not resident memory.

[Understand the result](../guide/understanding-measurements.md) explains these in detail.


## Recorded examples

```@raw html
<DocMedia src="/examples/bibliography/figures/history-time.svg" alt="Median Bibliography export time across nine tags: 13.15 microseconds at 0.1.0 and 15.45 at 0.4.0, with a 16.9 peak at 0.2.10" caption="Recorded on Windows with Julia 1.13.0 and one worker thread. The same input is used throughout; dependency versions follow each historical package stack. The axis is linear and starts at zero." />
```

```@raw html
<DocMedia src="/examples/bibliography/figures/history-samples.svg" alt="All 900 recorded Bibliography export timings grouped by nine tagged versions, with a median marker for each group" caption="One point per recorded export timing; the dark horizontal marks are medians. Slow observations remain visible. This shows sampling variation, not the order in which requests completed." />
```

## Next

- [Compare two versions](comparisons.md) while holding dependencies fixed.
- [Investigate a change](../guide/investigate.md) with a profile.

```@raw html
<a id="Bibliography-in-three-small-steps"></a>
<a id="1.-Read-a-measured-result"></a>
<a id="2.-Run-just-the-export-check"></a>
<a id="3.-Compare-versions-and-inspect-the-variation"></a>
<a id="Choose-your-next-step"></a>
```
