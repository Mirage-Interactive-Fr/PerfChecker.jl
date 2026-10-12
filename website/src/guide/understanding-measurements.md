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

::: tabs

== VS Code

Open the workspace containing the original suite. Configure its actual suite
file, factory and profile, and set `perfchecker.reports` to the saved report directory.
Refresh the suite plan, then open **Output** for the matching workload or run.
The plan identifies the workload; the reports supply its recorded values.
Do not launch the plan again merely to reopen the result. An arbitrary plot
JSON or an exported `plan.json` is not an importable replacement for this pair.

Select the recorded versions and a compatible metric before comparing their
distributions. Read the units and the full-distribution summary alongside the
visible samples. The [VS Code walkthrough](../interfaces/vscode-workflows.md)
explains the available controls and their version requirements. The native
Makie export below reads the fourteen-release Oxygen history: Windows, Julia
1.13.0, one worker thread, 30 samples per release. It illustrates the evidence
type; it is not a capture of the VS Code viewer.

```@raw html
<InteractiveRecordedPlot source="/examples/real-packages/oxygen-features/distribution-17e1925ed491af0f.json" html="/examples/real-packages/oxygen-features/distribution-17e1925ed491af0f.html" title="Explore the saved Oxygen plain HTTP timing distributions" kind="distribution" />
```

== Pluto

In the prepared [Pluto environment](../interfaces/repl-pluto.md#Pluto), generate
a notebook that reads the saved report:

```julia
using PerfChecker, PerfCheckerPluto
reportdir = abspath("results/<run>")
notebook = prepare_pluto_dashboard("saved-results.jl";
    project = dirname(Base.active_project()),
    result_path = joinpath(reportdir, "suite-result.json"))
launch_pluto_dashboard(notebook)
```

Without `suite_path`, this notebook reads reports only. Notebook generation and
launch are separate calls; opening it evaluates its Julia cells but does not
schedule a benchmark. Keep the report files in place when reopening the notebook.
Choose a new notebook filename if `saved-results.jl` already exists.

```@raw html
<DocMedia src="/examples/bibliography/pluto/completed.png" alt="Recorded Bibliography Pluto notebook with one completed export_bibtex benchmark, the Save completed reports action and the result table" caption="Earlier Bibliography notebook example: the selected benchmark completed and its report was saved explicitly. This controller notebook includes launch controls; the report-only notebook above omits them when no suite_path is supplied." />
```

== Web (Oxygen)

In the prepared [Web environment](../interfaces/web-studio.md):

```julia
using PerfChecker, PerfCheckerWeb, PerfCheckerMakie, WGLMakie
serve_suite("results/<run>"; host = "127.0.0.1", port = 8080)
```

While this local server runs, open `http://127.0.0.1:8080/perfchecker/v1/` on
the same machine. Select the saved run and its available plots. This directory
overload is a report viewer; a measurement controller requires a suite.
See [server configuration](../interfaces/web-studio.md#Safety) for remote access.

```@raw html
<InteractiveRecordedPlot source="/examples/bibliography/history/export-time.json" html="/examples/bibliography/history/export-time.html" title="Bibliography export medians from the saved nine-release campaign" kind="version_series" />
<details><summary>See the same history in Web Studio</summary>
<DocMedia src="/examples/bibliography/history-web/history-time.png" alt="Oxygen Results page showing the Bibliography historical campaign, export_bibtex version-series filters and measured timing across nine tags" caption="Earlier Bibliography historical campaign: the result selector, feature, metric and view identify the evidence displayed. These nine-tag timings are separate from the Oxygen package comparison in the VS Code tab." />
</details>
```

== REPL / CLI

In a controller with PerfChecker and UnicodePlots installed:

```julia
using PerfChecker, UnicodePlots
bundle = read_run_bundle("results/<run>/bundles/<bundle>")
catalog = plot_catalog(bundle)
[(entry["id"], entry["title"]) for entry in catalog]
isempty(catalog) && error("This bundle has no supported plots")
display(terminal_plot(bundle; plot_id = first(catalog)["id"]))
```

Use the actual bundle directory and choose a plot ID from its catalogue.
Terminal plots show saved values; they do not provide the browser's pointer
controls. A native-item `testitems.json` is a different report format and is
not accepted by `read_run_bundle`. See the [REPL guide](../interfaces/repl-pluto.md#REPL)
for selection and report saving, or [Plots](../interfaces/visualization.md)
for a Makie figure and standalone interactive HTML.

The published Oxygen history also includes a genuine
[UnicodePlots terminal export](../examples/real-packages/oxygen-features/normalized-metrics-24034c4be099f2e2.txt).
The interactive view below reads the same native model. Hover a release and
metric to inspect both the ratio and its original value and unit.

```@raw html
<NormalizedMeasurements source="/examples/real-packages/oxygen-features/normalized-metrics-24034c4be099f2e2.json" html="/examples/real-packages/oxygen-features/normalized-metrics-24034c4be099f2e2.html" package-name="Oxygen plain HTTP metrics relative to each metric's minimum" />
```

This model uses the minimum observation for each release and a separate
minimum reference for each metric. A ratio of one for time and one for bytes
therefore describe different quantities. Equal zero values use one by
convention; nonzero values against a zero reference are unavailable.
These are the same fourteen-release history and runtime as the distribution
in the VS Code tab, not a recollection of the older two-release example.

:::


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
