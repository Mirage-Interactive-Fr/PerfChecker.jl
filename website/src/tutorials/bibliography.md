```@raw html
<a id="Bibliography:-run-the-complete-suite"></a>
```

# Bibliography: the complete suite

Bibliography imports, processes and exports bibliographic entries. Its parser and data model live in BibParser and BibInternal, so a slower export need not come from the parser.

The scripts in `examples/bibliography/` load all three packages' suites. Use them to select one operation, compare releases, and inspect timings and profiles in each interface.

New to profiling? Read [Understand the result](../guide/understanding-measurements.md) alongside this page.

## Choose a task

- `items.jl performance` — measure selected upstream tests as items.
- `run.jl benchmark Bibliography export_bibtex` — time export only.
- `history.jl run` — compare nine released stacks.
- `compare-exports.jl run` — compare one source change with dependencies fixed.
- VS Code, Oxygen, Pluto — the same selections through controls.

```@raw html
<a id="Prepare-the-example-once"></a>
```

## Prepare once

From a PerfChecker checkout:

```sh
cd examples/bibliography
julia --startup-file=no setup.jl
```

Preparation creates `sources.toml`, `suite.jl`, several launchers, `.sources/` (pinned checkouts), `.controller/` (controller environments) and `results/`.

`sources.toml` pins:

- BibInternal 0.4.0 — `792d8c7`
- BibParser 0.3.0 — `cf1eb44`
- Bibliography 0.4.0 — `575ec81`

Preparation does not modify your existing checkouts. A later run checks the recorded revisions and refuses to replace local edits.

```@raw html
<a id="Inspect-the-full-suite"></a>
```

## Inspect the suite

```sh
julia --project=.controller/core run.jl plan
```

35 leaves: seven workloads, five collectors each.

- BibInternal `construct_entry` — construct a normalized article entry.
- BibInternal `validate_entry` — validate against canonical rules.
- BibParser `parse_bibtex_file` — parse a BibTeX file.
- Bibliography `import_bibtex` — import BibTeX into the public model.
- Bibliography `export_bibtex` — export the model as BibTeX.
- Bibliography `web_render` — convert to the web representation.
- Bibliography `read_and_filter` — read a document and filter entries.

- `benchmark` — BenchmarkTools timing and allocations.
- `chairmark` — Chairmarks measurements.
- `profile_alloc` — allocation samples, files and stacks.
- `profile` — CPU samples and stacks.
- `wall_profile` — task wall-time stacks (Julia 1.12+).

Planning starts no worker. Check the status column before running.

```@raw html
<a id="Run-the-seven-timing-checks"></a>
```

## Select a package, workload and collector

Choose either route to inspect the same five-collector export plan. Neither starts a measurement.

::: code-group

```sh [CLI]
julia --startup-file=no --project=.controller/core run.jl plan Bibliography export_bibtex
```

```julia [Julia API]
using PerfChecker
suite = load_software_suite("suite.jl")
plan = plan_suite(suite; profile = :quick)
selected = filter_suite_plan(plan;
    packages = "Bibliography", features = :export_bibtex)
print_suite_plan(selected)
```

:::

Start Julia with `--project=.controller/core` for the API route. The working directory is `examples/bibliography/` for both routes. `features = :export_bibtex` matches the logical workload across collectors; you do not need the technical leaf name. Omit the workload to select all workloads in a package; the CLI also accepts comma-separated names.

```@raw html
<a id="Why-the-sampling-profiles-reuse-their-inputs"></a>
```

### Why the sampling profiles reuse their input

The CPU and wall-time profiles call the original workload repeatedly with one prepared input during a continuous sampling window. These workloads read their inputs, and `verify-reuse.jl` checks that two calls leave state and file bytes unchanged. Timing and allocation collectors keep fresh state.

An empty profile is missing evidence, not proof the operation is free. Never copy this reuse policy to a workload that mutates its input.

```@raw html
<a id="Read-the-report-before-interpreting-the-graph"></a>
```

## Read the report before the graph

Open `suite-report.md` first. The same run is available as `suite-result.json` and `suite-junit.xml`; `bundles/` holds the evidence plots consume.

- The Markdown `Seconds` column covers the whole leaf, including orchestration — not the sample latency. Use `julia.wall.time` for workload timing.
- A completed collector means the measurement ran. These upstream workloads have no oracle, so correctness is `not_checked`.
- A quick run against one target has no baseline. It cannot show an improvement.
- Preserve unavailable collectors and worker failures instead of filtering them into an apparent pass.

```@raw html
<a id="Open-the-same-suite-in-the-REPL"></a>
<a id="Open-the-web-interface"></a>
```

```@raw html
<a id="Open-the-interfaces"></a>
<a id="Watch-one-export-check"></a>
```

## Run one export through your interface

Each tab runs **Bibliography → export_bibtex → benchmark** from the same prepared suite. Keep one worker thread, 50 samples, `evals = 1` and 0.5 seconds. Inspect the one-row plan before launching and read its completed report before interpreting a figure. The recorded captures show this workload; they are examples, not a new run on your machine.

```@raw html
<a id="Open-the-web-studio"></a>
<a id="Use-VS-Code"></a>
```

::: tabs

== VS Code

1. Open `examples/bibliography/` as the workspace and set **PerfChecker: Runner Project** to `.controller/core`.
2. Open Studio, select `suite.jl`, package **Bibliography**, workload **export_bibtex** and collector **benchmark**.
3. Inspect the one-row plan and the controls above, then explicitly launch it.
4. Open the completed run and its saved report. A one-target execution has no comparison baseline.

See [suite selection and results](../interfaces/vscode-workflows.md) for the editor controls. The native TestItems below use their separate `.controller/items` environment; they measure a different scope.

== Pluto

Prepare the optional environment, then launch the supplied notebook:

```sh
julia --startup-file=no setup.jl pluto
julia --startup-file=no --project=.controller/pluto pluto.jl
```

1. Select **Bibliography**, **export_bibtex** and **benchmark**.
2. Inspect the one-row plan and controls, then press **Launch selected checks**.
3. Refresh the completed status and explicitly save the reports. Opening the notebook, changing a selector or reloading starts no measurement.

```@raw html
<p><a href="../examples/bibliography/pluto/notebook.jl" download="notebook.jl"><strong>Download the Bibliography notebook (.jl)</strong></a></p>
<DocMedia src="/examples/bibliography/pluto/selection.png" alt="Recorded Pluto selection of the Bibliography export benchmark" caption="Recorded selection for this export workload. Launch and report saving are explicit notebook actions." />
```

== REPL / CLI

From the same example directory, run just the benchmark collector:

```sh
julia --startup-file=no --project=.controller/core run.jl benchmark Bibliography export_bibtex
```

The command prints the selected plan, runs it with the controls above and prints its new report directory. Open `suite-report.md` there; `suite-result.json` preserves the same execution. For interactive selection, start `repl.jl` in the same controller and choose the same package, workload and collector.

== Web (Oxygen)

Prepare and start the optional Web controller:

```sh
julia --startup-file=no setup.jl web
julia --startup-file=no --project=.controller/web web.jl
```

Open `http://127.0.0.1:8871/perfchecker/v1/` on the same machine while that server is running.

1. Select package **Bibliography** and workload **export_bibtex**. Its five collector cards appear.
2. Choose **benchmark**, then **Add visible**. Inspect the one-row plan and controls above.
3. Launch explicitly and wait for **complete**.
4. Open **Results**, choose `julia.wall.time` and view `distribution`.

```@raw html
<DocMedia src="/examples/bibliography/web/selection.png" alt="Recorded Web Studio selection of Bibliography export_bibtex" caption="The recorded export selection in Oxygen Studio. Choose benchmark to time this operation." />
```

See [Web controller configuration](../interfaces/web-studio.md) for binding, authentication and remote access.

:::

### Explore all nine versions in Oxygen

After `history.jl run`, open **Results**, filter **Profile** to **historical**, and select the campaign. Choose feature `export_bibtex`, metric `julia.wall.time`, view `version_series`. Switch to `julia.alloc.bytes` for allocated bytes, `distribution` for all 900 timings, or `version_delta` for comparisons against 0.1.0.

The run is `partially_executed`: eight planned workloads do not exist in earlier versions, so their points are absent. `inconclusive` means no acceptance threshold was configured.

## Reuse the upstream tests as native items

The pinned Bibliography revision uses `@testset` files, not `@testitem`. The example supplies two thin declarations in `testitems/items.jl`.

```sh
julia --startup-file=no setup.jl items
julia --startup-file=no --project=.controller/items items.jl list
julia --startup-file=no --project=.controller/items items.jl performance "Bibliography export workload"
```

- The listing runs nothing.
- `performance` measures only the named item; without a name it measures both declarations.
- `functional` runs the shared functional item only.

In VS Code, set **PerfChecker: Runner Project** to `.controller/items`, then discover items. Each sample still runs in a fresh Julia process.

## Open Pluto

Use the **Pluto** tab above for the runnable notebook, optional environment and explicit launch/save steps. The [Pluto interface guide](../interfaces/repl-pluto.md) covers notebook configuration and shutdown.

## Compare the package history

```sh
julia --project=.controller/core history.jl plan
julia --project=.controller/core history.jl run
```

Nine tagged versions: **0.1.0, 0.2.0, 0.2.5, 0.2.10, 0.2.15, 0.2.20, 0.3.0, 0.3.1, 0.4.0**. 36 leaves: 28 measurable, eight unavailable because `read_and_filter` only exists in 0.4.0.

For Bibliography 0.2.10 the example pins BibParser 0.1.10; its DataStructures constraint is compatible, BibParser 0.1.9 is not.

Dependencies evolve with the package stack, so this history describes the stacks together.

## Extend to historical comparisons

To isolate one source change, hold dependencies fixed. The [two-revision comparison](comparisons.md) follows the streaming-export change with BibInternal and BibParser pinned.

- `plan_suite(suite; profile = :ci)` selects representative releases and source checkouts.
- `:historical` includes all declared releases.
- An unavailable workload is not a regression.

To locate the calls responsible for a cost, continue with [Investigating a change](../guide/investigate.md).

## Recorded examples

```@raw html
<p>The <a href="../examples/bibliography/suite-runs.json">recorded run summary</a> lists each workload, collector, state policy, outcome and source report digest.</p>
```

```@raw html
<DocMedia video recording="bibliography-history" src="/examples/bibliography/history-web/bibliography-history.webm" poster="/examples/bibliography/history-web/history-time.png" subtitles="/examples/bibliography/history-web/walkthrough.vtt" alt="Oxygen walkthrough comparing nine Bibliography tags through time, allocation, distribution and delta views" caption="Actual exploration of the recorded historical campaign. The first wait is plot rendering; this video launches no measurement job. Captions explain the selected measures. No audio." />
<DocMedia src="/examples/bibliography/history-web/history-memory.png" alt="Oxygen allocated-byte curve showing all nine Bibliography tags, from 4480 to 8352 bytes" caption="The same saved campaign viewed as Julia allocation bytes. The metric changes while the selected workload and source revisions remain the same." />
```

```@raw html
<DocMedia video recording="bibliography-web" src="/examples/bibliography/web/bibliography-web.webm" poster="/examples/bibliography/web/selection.png" subtitles="/examples/bibliography/web/walkthrough.vtt" alt="Recorded Bibliography export check in the Oxygen studio" caption="Windows, Julia 1.13.0, 12 September 2026. One export_bibtex check, from selection to its saved sample distribution. No audio." />
```

```@raw html
<DocMedia src="/examples/bibliography/web/collectors.png" alt="Five collectors available for the Bibliography export_bibtex workload" caption="The workload filter groups the five collectors under the same export_bibtex name." />
<DocMedia src="/examples/bibliography/web/results.png" alt="Saved export timing distribution with sample 50 highlighted at 6200 nanoseconds" caption="A saved result reopened after the run. The executed verdict and inconclusive comparison remain visible above the distribution." />
```

```@raw html
<p><a href="../examples/bibliography/pluto/notebook.jl" download="notebook.jl"><strong>Download the Bibliography Pluto notebook (.jl)</strong></a></p>
```

```@raw html
<DocMedia src="/examples/bibliography/pluto/completed.png" alt="Pluto notebook showing one completed Bibliography export check and its saved reports" caption="The same export workload run through Pluto. Status, report saving and the result row are visible; no measurement starts when the notebook opens." />
```

```@raw html
<DocMedia src="/examples/bibliography/vscode/native-items.png" alt="VS Code Testing view: the Bibliography export workload passed and the format API item remains unrun" caption="Actual VS Code 1.137.0 execution of one selected Bibliography item. The other discovered item remains unrun. The 26.4 seconds in the Testing summary include orchestration; this run's item measurement was 1.99 seconds, including its imports, setup and assertions." />
```

```@raw html
<figure class="doc-screenshot">
<iframe class="doc-interactive" src="../examples/bibliography/history/export-time.html" title="Bibliography export medians across nine tagged versions" loading="lazy" sandbox="allow-scripts allow-same-origin allow-downloads"></iframe>
<figcaption>Native interactive export of medians from 100 samples per tag. Windows · Julia 1.13.0 · one worker thread. Inputs match; dependency revisions follow each tag. Values are in nanoseconds (1,000 ns = 1 µs).</figcaption>
</figure>
<p><a href="../examples/bibliography/history/export-time.html">Open the interactive export</a> · <a href="../examples/bibliography/history/export-time.json" download>Download the serialized plot and source revisions</a></p>
```
