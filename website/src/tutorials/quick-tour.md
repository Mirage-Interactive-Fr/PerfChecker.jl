```@raw html
<a id="Bibliography-in-three-small-steps"></a>
```

# Measure an operation

Time one operation with its input prepared **before** timing starts.

```@raw html
<a id="2.-Run-just-the-export-check"></a>
```

From the root of the [versioned example checkout](../real-packages/index.md#Get-the-code), run:

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

The operation stays the same; only what is recorded changes. Choose a backend; each tab shows its command and its own saved result.

::: tabs

== BenchmarkTools

```sh
julia --startup-file=no --project=.controller/core run.jl benchmark Bibliography export_bibtex
```

```@raw html
<InteractiveRecordedPlot source="/examples/bibliography/timing-evidence.json" html="/examples/bibliography/export-timing.html" title="Recorded BibTeX export timing — fifty samples" kind="distribution" />
```
Recorded result: fifty samples at source `575ec81`, Julia 1.13.0, one worker thread. Select a point for its nanoseconds. Correctness is `not_checked`; performance is `not_compared`.

== Chairmarks

```sh
julia --startup-file=no --project=.controller/core run.jl chairmark Bibliography export_bibtex
```

Recorded collector output from [suite-runs.json](../examples/bibliography/suite-runs.json):

| Field | Saved result |
| --- | --- |
| Workload | export_bibtex |
| Leaf | export_bibtex_chairmark |
| Target | dev@0.4.0 |
| Collector execution | executed (pass) |
| State policy | fresh |

The published receipt proves execution; it does not retain Chairmarks' numerical samples. In a local report, read elapsed time in **seconds**, bytes and allocation count; GC is a **fraction**, not BenchmarkTools' GC nanoseconds. No missing value is replaced with zero.

== CPU profile

```sh
julia --startup-file=no --project=.controller/core run.jl profile Bibliography export_bibtex
```

```@raw html
<InteractiveRecordedPlot source="/examples/bibliography/profiles/cpu.json" html="/examples/bibliography/profiles/cpu.html" title="Recorded CPU samples during BibTeX export" kind="cpu_flamegraph" />
```
Recorded result: sampled call stacks from this workload. Inspect a frame for its sample weight and path. Width attributes sampled work; it is not a per-call duration.

== Allocation profile

```sh
julia --startup-file=no --project=.controller/core run.jl profile_alloc Bibliography export_bibtex
```

```@raw html
<InteractiveRecordedPlot source="/examples/bibliography/profiles/allocations.json" html="/examples/bibliography/profiles/allocations.html" title="Recorded allocation samples during BibTeX export" kind="allocation_flamegraph" />
```
Recorded result: allocation-weighted stacks. Inspect a frame to identify an allocation site; the recorded weight does not measure resident memory.

== Wall-time profile

```sh
julia --startup-file=no --project=.controller/core run.jl wall_profile Bibliography export_bibtex
```

```@raw html
<InteractiveRecordedPlot source="/examples/bibliography/profiles/wall.json" html="/examples/bibliography/profiles/wall.html" title="Recorded wall-time task samples during BibTeX export" kind="wall_flamegraph" />
```
Recorded result: sampled task stacks, including waiting. Requires Julia 1.12 or later. Read the task-sample weight separately from CPU samples.

:::

```@raw html
<a id="3.-Compare-versions-and-inspect-the-variation"></a>
```

## Compare versions

```sh
julia --startup-file=no --project=.controller/core history.jl plan
julia --startup-file=no --project=.controller/core history.jl run
```

This runs nine Bibliography versions and four workloads. Earlier versions do not define every workload, so those combinations are `unavailable` — not slow, failed or zero.

```@raw html
<InteractiveRecordedPlot source="/examples/bibliography/history/export-time.json" html="/examples/bibliography/history/export-time.html" title="Recorded export medians across nine Bibliography tags" kind="version_series" />
```

This saved Windows campaign used Julia 1.13.0, one worker thread and 100 samples per tag. Inspect a point for its version and median in nanoseconds. Dependency revisions follow each tag, so the curve describes each released stack together.

```@raw html
<a id="1.-Read-a-measured-result"></a>
```

## Read a result

- Benchmarks record time, allocated bytes, allocation count and GC time.
- Compare the **distribution**, not just the median. Overlapping samples are weak evidence.
- Allocated bytes count Julia allocation activity, not resident memory.

[Understand the result](../guide/understanding-measurements.md) explains these in detail.


## Recorded examples

```@raw html
<figure class="doc-screenshot">
<InteractiveRecordedPlot source="/examples/bibliography/history/export-samples.json" html="/examples/bibliography/history/export-samples.html" title="Distribution of 900 recorded Bibliography export timings across nine tagged versions" kind="distribution" />
<figcaption>Native interactive distribution of 900 recorded timings: 100 samples per tag. Boxplots summarize each group; recorded points and slow observations remain available. Points can overlap. This shows variation, not execution order.</figcaption>
</figure>
```

```@raw html
<a id="Choose-your-next-step"></a>
```

## Next

- [Compare two versions](comparisons.md) while holding dependencies fixed.
- [Investigate a change](../guide/investigate.md) with a profile.
