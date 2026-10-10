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
The screenshots illustrate different recorded runs: Oxygen timing distributions
in VS Code and Bibliography checks in Pluto and the Web interface. They show the controls
to use, rather than claiming that each interface displays the same campaign.

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
explains the available controls and their version requirements.

```@raw html
<DocMedia src="/assets/screenshots/vscode/v101/oxygen-distributions-central-db8b51b.png" alt="Native VS Code displaying saved Oxygen 1.10.2 and 1.11.0 timing distributions on a common zoomed scale, with their different medians and visible sample counts" caption="Saved Oxygen comparison, Linux, Julia 1.13.1, extension source db8b51b. The viewport shows 26/30 and 28/30 samples; summaries still use all 30 per release. The VS Code distribution guide gives its provenance and full-range view." />
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
<DocMedia src="/examples/bibliography/history-web/history-time.png" alt="Oxygen Results page showing the Bibliography historical campaign, export_bibtex version-series filters and measured timing across nine tags" caption="Earlier Bibliography historical campaign: the result selector, feature, metric and view identify the evidence displayed. These nine-tag timings are separate from the Oxygen package comparison in the VS Code tab." />
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

:::


```@raw html
<a id="Try-it-with-Bibliography"></a>
```

## Recorded examples

```@raw html
<DocMedia src="/examples/bibliography/figures/history-time.svg" alt="Bibliography export medians across nine tagged versions on a linear microsecond axis" caption="One hundred samples per tag, Windows, Julia 1.13.0, one worker thread. Inputs match; the dependency stack evolves with the tags. Lower means less elapsed time." />
```

```@raw html
<DocMedia src="/examples/bibliography/figures/history-samples.svg" alt="Nine groups containing all 900 export timings, with median markers and visible slow samples" caption="Each dot is one sample; the dark marks are medians. Horizontal displacement only separates dots. Overlap and slow observations remain visible." />
```

```@raw html
<DocMedia src="/examples/bibliography/figures/history-memory.svg" alt="Allocated bytes per Bibliography export across nine tags, from 4480 bytes at 0.1.0 to 8352 at 0.4.0" caption="Julia allocation activity per operation. These values are neither retained heap size nor resident process memory. All nine points come from recorded measurements." />
```

## Next

- [Collectors](../reference/checks.md) — what each tool records.
- [Investigate a change](investigate.md) — locate the cost with a profile.
