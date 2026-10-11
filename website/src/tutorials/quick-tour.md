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

The operation stays the same; only what is recorded changes.

```sh
julia --startup-file=no --project=.controller/core run.jl profile_alloc Bibliography export_bibtex
```

Other collectors: `benchmark`, `chairmark`, `profile`, `wall_profile` (Julia 1.12+).

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
<iframe class="doc-interactive" src="../examples/bibliography/history/export-time.html" title="Bibliography export medians across nine tagged versions" loading="lazy" sandbox="allow-scripts allow-same-origin allow-downloads"></iframe>
<figcaption>Native interactive export of medians from 100 samples per tag. Windows · Julia 1.13.0 · one worker thread. Inputs match; dependency revisions follow each tag. Values are in nanoseconds (1,000 ns = 1 µs).</figcaption>
</figure>
<p><a href="../examples/bibliography/history/export-time.html">Open the interactive export</a> · <a href="../examples/bibliography/history/export-time.json" download>Download the serialized plot and source revisions</a></p>
```

```@raw html
<figure class="doc-screenshot">
<iframe class="doc-interactive" src="../examples/bibliography/history/export-samples.html" title="Distribution of 900 recorded Bibliography export timings across nine tagged versions" loading="lazy" sandbox="allow-scripts allow-same-origin allow-downloads"></iframe>
<figcaption>Native interactive distribution of 900 recorded timings: 100 samples per tag. Boxplots summarize each group; recorded points and slow observations remain available. Points can overlap. This shows variation, not execution order.</figcaption>
</figure>
<p><a href="../examples/bibliography/history/export-samples.html">Open the interactive export</a> · <a href="../examples/bibliography/history/export-samples.json" download>Download the serialized plot and source revisions</a></p>
```

```@raw html
<a id="Choose-your-next-step"></a>
```

## Next

- [Compare two versions](comparisons.md) while holding dependencies fixed.
- [Investigate a change](../guide/investigate.md) with a profile.
