```@raw html
<a id="Understand-performance-measurements"></a>
```

# Understand the result

What each number means, and when two numbers may be compared.

```@raw html
<a id="Wall-time:-how-long-the-operation-takes"></a>
```

## Wall time

Elapsed clock time across the measured operation, including any waiting inside it.

- The workload definition decides the boundary. Read it before interpreting a timing.
- Units: 1 s = 1,000 ms = 1,000,000 µs = 1,000,000,000 ns.
- **CPU time** counts processor execution. Threads consume it in parallel, and waiting uses none.

```@raw html
<a id="Samples,-repetitions-and-distributions"></a>
```

## Samples and distributions

- A **sample** is one measured execution (or a batch normalized per evaluation).
- `samples` is how many to collect; `evals` is evaluations per sample.
- **median** — middle value; the usual summary.
- **minimum** — fastest observed.
- **mean** — sensitive to slow samples.
- **p95 / p99** — thresholds covering about 95% / 99% of observations.

A small microbenchmark does not establish a production p99. That needs production-like input, concurrency and load.

```@raw html
<a id="Allocated-bytes,-allocation-count-and-live-memory"></a>
```

## Allocations and memory

- **Allocated bytes** — memory obtained during the operation.
- **Allocation count** — how many allocation events occurred.
- **Live memory** — memory still retained afterwards.

Allocated bytes, allocation count and live memory are three separate quantities. One large buffer can allocate more bytes than many small objects; many small objects cost more management work. Neither equals resident process memory. See [Process memory](../process-memory.md).

```@raw html
<a id="Garbage-collection:-reclaiming-unused-objects"></a>
```

## Garbage collection

- The GC reclaims managed memory the program no longer needs; collecting it is work.
- **GC time** — measured collection time, in the same unit as the timing (BenchmarkTools).
- **GC fraction** — that time divided by elapsed time (Chairmarks).

Never merge the two.

- Zero recorded GC time in a short sample does not mean zero allocations — the collector may simply not have run.
- Do not add GC time to elapsed time; the elapsed interval already contains it.

```@raw html
<a id="Warm-code,-first-calls-and-state"></a>
```

## Warm and cold code

- Julia compiles methods on first call.
- A **warm** benchmark measures repeated execution after preparation.
- A **cold** or first-call experiment must include the startup, loading or compilation boundary explicitly.

Warm latency says nothing about `using YourPackage`.

```@raw html
<a id="Flame-graphs:-where-sampled-work-accumulates"></a>
```

## Flame graphs

- A **call stack** is the chain of calls leading to the current function.
- A **flame graph** aggregates many stacks into nested rectangles.
- Width — the selected weight (CPU samples, task samples or allocation bytes).
- Depth — the calling relationship. Horizontal position is not a timeline.
- A wide parent includes its descendants. Do not add parent and child percentages.

CPU, wall-time and allocation flame graphs look similar but weight different things. Read the metric, unit and legend first.

```@raw html
<a id="Inspect-three-recorded-Bibliography-profiles"></a>
```

Inspect the [three recorded Bibliography profiles](investigate.md#Recorded-examples)
to compare CPU, wall-time and allocation weights on the same workload.

```@raw html
<a id="Read-a-result-across-several-tools"></a>
```

## Comparability

Compare two numbers only when their measurement definitions and comparison keys agree. A run records the conditions so a consumer can check.

- Different OS, architecture, Julia threads or hardware make a comparison **incomparable**.
- A changed runtime or environment is a **warning**.
- A missing measurement stays missing. It never becomes an improvement.

## Reopen a saved measurement

Keep the report directory printed by the run, including its `suite-result.json`
and `bundles/` directory. Replace the paths below with that real directory.
These routes read saved evidence; they do not collect new samples.
The examples use saved Oxygen and Bibliography campaigns. Interactive native
exports let you inspect their values; the interface captures show where to
find the corresponding controls. Each example identifies its own evidence.

In a prepared plotting environment, read a bundle and export one of its saved distributions:

```julia
using PerfChecker, PerfCheckerMakie, WGLMakie
bundle = read_run_bundle("results/<run>/bundles/<bundle>")
views = filter(v -> v["kind"] == "distribution", plot_catalog(bundle))
isempty(views) && error("This bundle has no distribution view")
model = performance_plot(bundle, first(views)["id"])
write("saved-distribution.html", performance_plot_html(model))
```

Expected artifact: `saved-distribution.html`, containing the selected bundle's values. The command reads evidence; it does not rerun the workload. Use a real bundle directory, not a standalone plot JSON or `testitems.json`.

Here is a real native distribution from the fourteen-release Oxygen plain-HTTP campaign: Windows, Julia 1.13.0, one worker thread, 30 samples per release. It is saved evidence, independent of the path you supply above.

```@raw html
<InteractiveRecordedPlot source="/examples/real-packages/oxygen-features/distribution-17e1925ed491af0f.json" html="/examples/real-packages/oxygen-features/distribution-17e1925ed491af0f.html" title="Recorded Oxygen plain HTTP timing distributions" kind="distribution" />
```

Select a version and a sample to read its time and unit. The summary describes the full distribution; visible points can overlap. A completed collection alone does not establish a regression.


```@raw html
<a id="Try-it-with-Bibliography"></a>
```

## Recorded examples

```@raw html
<figure class="doc-screenshot">
<InteractiveRecordedPlot source="/examples/bibliography/history/export-time.json" html="/examples/bibliography/history/export-time.html" title="Bibliography export medians across nine tagged versions" kind="version_series" />
<figcaption>Native interactive export of medians from 100 samples per tag. Windows · Julia 1.13.0 · one worker thread. Inputs match; dependency revisions follow each tag. Values are in nanoseconds (1,000 ns = 1 µs).</figcaption>
</figure>
```

```@raw html
<figure class="doc-screenshot">
<InteractiveRecordedPlot source="/examples/bibliography/history/export-samples.json" html="/examples/bibliography/history/export-samples.html" title="Distribution of 900 recorded Bibliography export timings across nine tagged versions" kind="distribution" />
<figcaption>Native interactive distribution of 900 recorded timings: 100 samples per tag. Boxplots summarize each group; recorded points and slow observations remain available. Points can overlap. This shows variation, not execution order.</figcaption>
</figure>
```

```@raw html
<figure class="doc-screenshot">
<InteractiveRecordedPlot source="/examples/bibliography/history/export-memory.json" html="/examples/bibliography/history/export-memory.html" title="Julia allocated bytes per Bibliography export across nine tagged versions" kind="version_series" />
<figcaption>Native interactive export of Julia allocated bytes per export across nine tags, from 4,480 to 8,352 bytes. These values measure allocation activity, not retained heap size or resident process memory.</figcaption>
</figure>
```

## Next

- [Collectors](../reference/checks.md) — what each tool records.
- [Investigate a change](investigate.md) — locate the cost with a profile.
