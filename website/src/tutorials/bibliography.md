# Bibliography: run the complete suite

This walkthrough uses real Bibliography code and the performance suites owned
by its three packages. Prepare the sources, inspect the available checks, run a
selection, then open the results through the different interfaces. The runnable
files are in `examples/bibliography/` in the PerfChecker checkout.

New to profiling? Read [Understand performance measurements](../guide/understanding-measurements.md)
alongside this walkthrough. It explains wall time, GC, allocations, samples and
flame graphs using the operations below. Each collector also has a short
[reading guide](../reference/checks.md), including quantities that differ between
tools even when their labels look similar.

## Choose a task

You do not need to execute this whole page in one session. Each route has its
own commands and result; start with one item or one export benchmark.

| Task | Start here | What you obtain |
| --- | --- | --- |
| Adapt a self-contained test to my own package | [Downloadable test item](../guide/first-check.md) | One shared functional/performance test, no source checkout |
| Reuse the pinned upstream tests | [Native items](#Reuse-the-upstream-tests-as-native-items) | A selected item and `testitems.json` |
| Time only the export operation | Prepare below, then [select one workload](#Select-a-package,-workload-and-collector) | A suite report with timings and a run bundle |
| Use a graphical interface | [VS Code](../interfaces/vscode.md), [Oxygen](#Open-the-web-studio), [Pluto](#Open-Pluto) | The same suite or item selection through controls |
| Compare released package stacks | [Nine-version history](#Compare-the-package-history) | Timing distributions, allocation curves and availability |
| Evaluate one source change | [Fixed-dependency comparison](#Extend-to-historical-comparisons) | Before/after observations with dependency revisions held fixed |

The rest of this page uses files shipped with the PerfChecker source checkout
to reproduce the recorded suite. That example preparation is not part of
installing PerfChecker. The downloadable TestItem above is the shorter path
when you just want to write and run a test in your own project.

## Prepare the example once

Use Julia 1.12 or later to include the task wall-time profiler. Git and network
access are needed for the first preparation. From your PerfChecker checkout:

```sh
cd examples/bibliography
julia --startup-file=no setup.jl
```

Preparation creates these directories:

```text
examples/bibliography/
├─ sources.toml             # exact source revisions
├─ suite.jl                 # loads the three upstream suites
├─ run.jl                   # plan and scripted execution
├─ repl.jl, web.jl, pluto.jl # interface launchers
├─ .sources/                # independent, pinned package checkouts
├─ .controller/             # controller environments
└─ results/                 # created when a run starts
```

The sources are public commits, rather than whatever happens to be on `main`:

| Package | Declared version | Source revision |
| --- | --- | --- |
| BibInternal | 0.4.0 | [792d8c7](https://github.com/JuliaBibliographies/BibInternal.jl/commit/792d8c709169505f998f7d70bfa092551dd4089f) |
| BibParser | 0.3.0 | [cf1eb44](https://github.com/JuliaBibliographies/BibParser.jl/commit/cf1eb4446b986a23ed444963dcdb4c6ecc2da90f) |
| Bibliography | 0.4.0 | [575ec81](https://github.com/JuliaBibliographies/Bibliography.jl/commit/575ec810042cc791fd47a2c025a80246ccf039b5) |

Preparation does not modify your existing development checkouts. A subsequent
preparation checks the recorded revisions and refuses to replace local edits.
The measured packages are installed in workers, separately from the controller.
All commands below run from `examples/bibliography/`.

## Inspect the full suite

```sh
julia --project=.controller/core run.jl plan
```

The quick plan has **35 leaves: seven workloads, each with five collectors**.
It uses the pinned source checkouts, labelled `dev@0.4.0` or `dev@0.3.0` in the
plan. Here `dev` means a source checkout rather than a registry release; the
commit is still fixed by `sources.toml`.

| Package | Workload | Operation |
| --- | --- | --- |
| BibInternal | `construct_entry` | Construct a normalized article entry |
| BibInternal | `validate_entry` | Validate an entry against the canonical rules |
| BibParser | `parse_bibtex_file` | Parse a BibTeX file |
| Bibliography | `import_bibtex` | Import BibTeX into the public model |
| Bibliography | `export_bibtex` | Export the model as BibTeX |
| Bibliography | `web_render` | Convert a bibliography into its web representation |
| Bibliography | `read_and_filter` | Read a document and filter its entries |

The small inputs make this a practical walkthrough. They are not a substitute
for checking your own document sizes and entry distributions. For example,
`export_bibtex` prepares a one-entry bibliography outside the measured call,
then measures `Bibliography.export_bibtex(bibliography)`.

| Collector argument | What it records |
| --- | --- |
| `benchmark` | BenchmarkTools timing and allocation measurements |
| `chairmark` | Chairmarks measurements of the same workload |
| `profile_alloc` | Allocation samples, source files and call stacks |
| `profile` | CPU samples and call stacks |
| `wall_profile` | Task wall-time stacks, requiring Julia 1.12 or later |

The plan command starts no worker. Check the final `status` column before
running it. An unsupported Julia version leaves its unavailable collector
visible, with the reason available in the plan data.

## Run the seven timing checks

```sh
julia --project=.controller/core run.jl benchmark
```

This executes the seven workloads sequentially, in isolated workers. It requests
50 samples, one evaluation per sample, a 0.5-second benchmark budget and one
worker thread. Dependency resolution and compilation can make the first run
much longer than the measurement budget.

The terminal shows progress and finishes by printing a new report directory:

```text
Reports: .../results/benchmark-<unique suffix>
```

The local Windows run on 12 September 2026 completed all seven checks with
Julia 1.13.0 and one worker thread. Its suite verdict is `executed`, correctness
is `not_checked`, and performance is `not_compared`.

The same local session then completed all seven Chairmarks, allocation, CPU and
wall-time checks: 35 successful collector/workload combinations across the five
recorded runs. The sampling profiles use the explicit reuse policy explained
below. These results establish collector execution on this Windows/Julia setup;
they are not a cross-platform qualification or a regression verdict.

```@raw html
<p>The <a href="../examples/bibliography/suite-runs.json">recorded run summary</a> lists each workload, collector, state policy, outcome and source report digest.</p>
```

Every invocation gets a new directory so repeating the tutorial preserves the
earlier measurements. To execute all 35 leaves, use `run.jl all` instead.

## Select a package, workload and collector

Run only Bibliography's export timing check:

```sh
julia --project=.controller/core run.jl benchmark Bibliography export_bibtex
```

Keep the workload and change what you measure:

```sh
julia --project=.controller/core run.jl profile_alloc Bibliography export_bibtex
julia --project=.controller/core run.jl profile Bibliography export_bibtex
```

Omit the workload argument to select all workloads in that package. Use
comma-separated names to select several packages or workloads. These selections
use the public `filter_suite_plan` function:

```julia
using PerfChecker
suite = load_software_suite("suite.jl")
plan = plan_suite(suite; profile = :quick)
selected = filter_suite_plan(plan;
    packages = "Bibliography", features = :export_bibtex,
    backends = [:benchmark, :profile_alloc])
print_suite_plan(selected)
```

`features = :export_bibtex` matches the logical workload across collectors.
You do not need to know the technical allocation leaf name
`export_bibtex_allocations` to select it.

### Why the sampling profiles reuse their inputs

The CPU and wall-time profiles in this example repeatedly call the original
workload with one prepared input during a continuous sampling window. These
seven workloads read their inputs; `verify-reuse.jl`, run in `.controller/items`,
checks that two successive calls leave both the state and input-file bytes
unchanged. Timing and allocation collectors keep fresh state per evaluation.

This is an explicit `state_policy = :reuse` setting for the sampling collectors.
The initial fresh-state CPU attempt captured no target stack for the very short
export operation and failed that check. Restarting the sampling timer around
each microsecond operation can miss it entirely. An empty profile is missing
evidence, not proof that the operation costs nothing. Do not copy this reuse
policy to a workload that mutates its input; profile a representative longer
operation or prepare an explicitly reusable scenario instead.

## Read the report before interpreting the graph

Open `suite-report.md` in the report directory first. The same run is available
as `suite-result.json` for scripts and `suite-junit.xml` for CI. The `bundles/`
directory holds the portable evidence consumed by plots and interfaces.

The Markdown report's `Seconds` column is the elapsed time of the complete
leaf, including its orchestration. It is **not** the workload's sample latency.
Use `julia.wall.time` observations and their declared unit for workload timing.

A completed collector establishes that the measurement ran. The upstream
workloads used here do **not** declare correctness oracles: their correctness
status is `not_checked`. Run the packages' functional TestItems as well before
accepting a change. Likewise, a quick run with a single target cannot establish
a performance improvement: it has no measured baseline.

Inspect duration and allocation measurements together, then use the allocation
or CPU profile to locate the work responsible. Preserve unavailable collectors
and worker failures in your report instead of filtering them into an apparent
pass. The [measurement model](../measurement-model.md) explains the verdicts.

The JSON files also contain format identifiers for the tools that read them.
You do not need to configure these to run the example. See
[run bundles](../reference/run-bundles.md) if you want to process the files yourself.

## Open the same suite in the REPL

```sh
julia --project=.controller/core repl.jl
```

For one export timing check, enter `Bibliography` at the package prompt,
`export_bibtex` at the feature prompt, and `benchmark` at the backend prompt.
Leave the version bounds and search blank. Keep the default sort, choose your
sample count and duration, and use one worker thread. Review the printed plan
before keeping the selection.

The launcher uses `configure_suite_repl`, which returns `(plan, overrides)`, then
passes both to `run_suite_repl`. See [REPL and Pluto](../interfaces/repl-pluto.md).

The recorded terminal run selected one `Bibliography / export_bibtex / benchmark`
check with 50 samples, a 0.5-second budget and one thread. It reached `1/1 complete`
and saved its report. The configurator rejects an empty selection and nonpositive
numeric settings before execution; answering `no` cancels the selection.

## Open the web studio

```sh
julia setup.jl web
julia --project=.controller/web web.jl
```

Open [the local Bibliography studio](http://127.0.0.1:8871/perfchecker/v1/).
Use the package and feature filters to select `Bibliography / export_bibtex`,
choose the check types, and keep the worker thread count at one. The studio
loads the same suite and saves below the same `results/` directory. The web
controller has its own environment containing PerfCheckerWeb and
PerfCheckerMakie; those packages are not added to the measured worker.

See [Web Studio](../interfaces/web-studio.md) for execution and result inspection.

### Explore all nine versions in Oxygen

After completing `history.jl run`, open **Results**, filter **Profile** to
**historical**, and select the complete campaign. Choose **Feature**
`export_bibtex`, **Metric** `julia.wall.time`, and **View** `version_series`.
The point selector inspects all nine versions. Switch to `julia.alloc.bytes`
for allocated bytes, then back to time with `distribution` for all 900 recorded
timings, or `version_delta` for eight comparisons against 0.1.0.

The saved run is marked `partially_executed` because eight planned workloads
were not defined for earlier versions. Its 28 available operations completed.
The separate `inconclusive` comparison label means no acceptance threshold was
configured. Neither label means that an unavailable workload measured zero.

```@raw html
<DocMedia video recording="bibliography-history" src="/examples/bibliography/history-web/bibliography-history.webm" poster="/examples/bibliography/history-web/history-time.png" subtitles="/examples/bibliography/history-web/walkthrough.vtt" alt="Oxygen walkthrough comparing nine Bibliography tags through time, allocation, distribution and delta views" caption="Actual exploration of the recorded historical campaign. The first wait is plot rendering; this video launches no measurement job. Captions explain the selected measures. No audio." />
<DocMedia src="/examples/bibliography/history-web/history-memory.png" alt="Oxygen allocated-byte curve showing all nine Bibliography tags, from 4480 to 8352 bytes" caption="The same saved campaign viewed as Julia allocation bytes. The metric changes while the selected workload and source revisions remain the same." />
```

### Watch one export check

This uncut local recording follows the commands above, with 50 samples and one
worker thread. The ring follows the recorded mouse movements. The pauses are
the actual worker execution and first plot compilation; no timings were
substituted. Captions describe each step, and the sequence is written below.

```@raw html
<DocMedia video recording="bibliography-web" src="/examples/bibliography/web/bibliography-web.webm" poster="/examples/bibliography/web/selection.png" subtitles="/examples/bibliography/web/walkthrough.vtt" alt="Recorded Bibliography export check in the Oxygen studio" caption="Windows, Julia 1.13.0, 12 September 2026. One export_bibtex check, from selection to its saved sample distribution. No audio." />
```

1. Clear the selection. Choose package **Bibliography** and workload
   **export_bibtex**. Five available cards show its different collectors.
2. Choose **benchmark**, then **Add visible**. The plan now contains one of the
   35 available checks. Keep one thread, 50 samples and 0.5 seconds.
3. Launch the job and wait for **complete**. This establishes that the collector
   ran; it does not add a correctness oracle or a reference measurement.
4. Open **Results**, then the latest run. Choose metric **julia.wall.time** and
   view **distribution**. Wait for the plot to finish loading.
5. Move **Inspect measured point**, or focus it and press End. The last sample
   in this recording is 6,200 ns; the highlighted point moves on the chart.

```@raw html
<DocMedia src="/examples/bibliography/web/collectors.png" alt="Five collectors available for the Bibliography export_bibtex workload" caption="The workload filter groups the five collectors under the same export_bibtex name." />
<DocMedia src="/examples/bibliography/web/results.png" alt="Saved export timing distribution with sample 50 highlighted at 6200 nanoseconds" caption="A saved result reopened after the run. The executed verdict and inconclusive comparison remain visible above the distribution." />
```

The [standalone interactive gallery](../interfaces/visualization.md) compares
nine tagged versions in a separate campaign. Its sources and samples differ from
this video; both preserve their original measurements.

## Open Pluto

```@raw html
<p><a href="../examples/bibliography/pluto/notebook.jl" download="notebook.jl"><strong>Download the Bibliography Pluto notebook (.jl)</strong></a></p>
```

The notebook is the editable example: it contains the selectors, explicit run
controls, progress and result table. Save it as `notebook.jl` in
`examples/bibliography/` in your PerfChecker checkout. That file is also included
in the checkout, so downloading is optional if you already have the example.
It uses paths relative to its location and contains no machine-specific paths.

```sh
julia --startup-file=no setup.jl pluto
julia --startup-file=no --project=.controller/pluto pluto.jl
```

Run these commands from `examples/bibliography/`. Preparation installs the
controller dependencies; opening the notebook loads the prepared project.
Its controller environment is separate from Oxygen's. Opening the file, editing
a selector or checking **Compare nine tagged versions** starts no measurement.

The historical option selects 0.1.0 through 0.4.0 with their pinned dependencies.
Leave it unchecked to explore all seven workloads at the pinned development
revisions. You can edit and save this notebook like any other Pluto document.

Select **Bibliography**, **export_bibtex** and **benchmark**. Check the one-row
plan, then press **Launch selected checks**. Use **Refresh status** until the
status reads `complete`, and **Save completed reports** to retain the bundle in
a new `results/pluto-*` directory. Editing a selector or reloading the browser
does not launch another job.

```@raw html
<DocMedia src="/examples/bibliography/pluto/completed.png" alt="Pluto notebook showing one completed Bibliography export check and its saved reports" caption="The same export workload run through Pluto. Status, report saving and the result row are visible; no measurement starts when the notebook opens." />
```

This walkthrough was exercised with Pluto 1.0.3 on Julia 1.13.0 under Windows.
That Pluto release still emits an upstream Julia 1.13 support warning. The
recorded checks cover this notebook's selection, execution, saving and reload
behavior; they do not establish complete compatibility of Pluto itself. See
[Pluto's Julia 1.13 tracking issue](https://github.com/JuliaPluto/Pluto.jl/issues/3389).

## Use VS Code

Open `examples/bibliography/` as the workspace. Set **PerfChecker: Runner
Project** to the absolute path of `.controller/core`. Open the visual suite
editor and select `suite.jl`. The suite tree groups packages, workloads, check
types and targets; choose the export leaf for the same bounded run.

### Reuse the upstream tests as native items

The pinned Bibliography revision uses `@testset` files and contains no
`@testitem` declarations. The example supplies two thin declarations in
`testitems/items.jl`: **Bibliography format API** includes the upstream
`test/api.jl`, and **Bibliography export workload** includes the same export
workload used by the suite. Their implementations are not copied into this
example. `JuliaTestItems.toml` restricts discovery to those declarations.

```sh
julia --startup-file=no setup.jl items
julia --startup-file=no --project=.controller/items items.jl list
julia --startup-file=no --project=.controller/items items.jl performance "Bibliography export workload"
```

The listing starts no item. The last command measures only the named export
item and prints a new report directory containing `testitems.json`. Run
`items.jl performance` without a name to measure both declarations, or
`items.jl functional` for the shared functional item only.

Keep `examples/bibliography/` as the VS Code workspace and change **PerfChecker:
Runner Project** to the absolute path of `.controller/items`. Run **PerfChecker:
Discover existing test items**, then use the Testing view to select a single
item. This test environment includes the pinned packages needed by the items;
each measured sample still runs in a fresh Julia process.

```@raw html
<DocMedia src="/examples/bibliography/vscode/native-items.png" alt="VS Code Testing view: the Bibliography export workload passed and the format API item remains unrun" caption="Actual VS Code 1.137.0 execution of one selected Bibliography item. The other discovered item remains unrun. The 26.4 seconds in the Testing summary include orchestration; this run's item measurement was 1.99 seconds, including its imports, setup and assertions." />
```

The format API item is shared with functional CI. The export item has the
`perf_only` tag. To run just the shared functional tests from Julia:

```julia
using PerfChecker, TestItemRunner
TestItemRunner.run_tests(pwd(); filter = testitem_filter(:test))
```

To measure those items, including the performance-only item:

```julia
using PerfChecker, TestItemRunner
items = discover_testitems(pwd())
result = run_testitems(pwd(); samples = 1, threads = 1)
```

An item measurement includes imports, setup and assertions. Its duration is
therefore different from the isolated `perf_workload` samples shown earlier.
See [VS Code](../interfaces/vscode.md) and [existing test items](../test-items.md)
for filtering, cancellation and result interpretation.

## Compare the package history

The historical plan selects nine tagged versions: **0.1.0, 0.2.0, 0.2.5, 0.2.10,
0.2.15, 0.2.20, 0.3.0, 0.3.1 and 0.4.0**. It measures the same input with
`import_bibtex`, `export_bibtex` and `web_render` throughout. `read_and_filter`
only exists in the 0.4.0 feature contract; earlier versions remain explicitly
unavailable for that workload.

```sh
julia --project=.controller/core history.jl plan
julia --project=.controller/core history.jl run
```

The plan has 36 leaves: 28 measurable operations and eight unavailable ones.
It requests 100 samples per operation, one evaluation per sample and one worker
thread, in sequence. The result directory contains the complete run bundle,
suite result and `sources.toml` with the full Git revisions used for every
tagged package and its pinned dependencies. The current small workload has no
correctness oracle or CI acceptance threshold, so successful collection is not
a claim that these versions passed a release gate.

For Bibliography 0.2.10, the example pins BibParser 0.1.10. Its DataStructures
constraint is compatible with that Bibliography release; BibParser 0.1.9 is not.
The package sources and compatibility declarations are unchanged. See
`history.jl` and the saved `sources.toml` for the exact dependency pairings.

Open the [interactive historical gallery](../interfaces/visualization.md) to
switch among elapsed time, allocated bytes, all export samples and change from
0.1.0. Read the units and the short explanation above each graph. The measured
value table provides the numbers without requiring mouse interaction, and the
availability matrix explains gaps. Dependencies evolve with the package stack,
so use the [fixed-dependency experiment](#Extend-to-historical-comparisons) below
when you want to isolate one particular export change.

To open this plan in Oxygen, prepare its controller as described in the web
section below, then run:

```sh
julia --project=.controller/web web.jl history
```

This loads the historical selection; starting a run remains an explicit action.
To export a completed run into standalone interactive HTML and downloadable
measurements:

```sh
julia --project=.controller/web export-history.jl results/<history-run> generated/history
```


```@raw html
<DocMedia src="/examples/bibliography/figures/history-time.svg" alt="Bibliography export medians across nine tagged versions on a linear microsecond axis" caption="One hundred samples per tag, Windows, Julia 1.13.0, one worker thread. Inputs match; the dependency stack evolves with the tags. Lower means less elapsed time." />
```

## Extend to historical comparisons

The upstream suite retains release pins and version-specific workloads. For
example, Bibliography 0.4.0 is paired with BibInternal 0.4.0 and BibParser 0.3.0.
The normalized `read_and_filter` workload is unavailable before Bibliography
0.4.0. An unavailable workload is not a regression.

In Julia, `plan_suite(suite; profile = :ci)` selects representative releases and
the source checkouts; `:historical` includes all declared releases. Inspect and
filter those plans before launching a large campaign. Inclusive version bounds
are available through `filter_suite_plan`.

For a focused code change, Bibliography's
[streaming export commit](https://github.com/JuliaBibliographies/Bibliography.jl/commit/575ec810042cc791fd47a2c025a80246ccf039b5)
replaces concatenated per-entry strings with writes to one buffer. Comparing
that revision with its parent is a useful experiment; the code change alone
does not establish a speedup. Hold the workload, dependency revisions, Julia
runtime and machine fixed, then inspect both allocation and timing differences.
See [revision comparisons](comparisons.md) for candidate and baseline selection.

The example includes that two-revision experiment. From `examples/bibliography/`:

```sh
julia --project=.controller/core compare-exports.jl plan
julia --project=.controller/core compare-exports.jl run
```

It selects only `export_bibtex` with BenchmarkTools, fixes the BibInternal and
BibParser revisions from `sources.toml`, and records 100 samples per revision,
with one evaluation per sample and one worker thread. It leaves your source
checkouts untouched. Reports go to a new `results/export-comparison-*` directory.

One Windows run on Julia 1.13.0, recorded on 12 September 2026, produced:

| Median measurement | Parent `6a4cc90` | Streaming export `575ec81` | Change |
| --- | ---: | ---: | ---: |
| Allocated bytes | 3,904 B | 2,976 B | −23.77% |
| Allocation count | 27 | 23 | −14.81% |
| Elapsed time | 7,600 ns | 6,800 ns | −10.53% |
| Garbage collection time | 0 ns | 0 ns | No relative change defined |


```@raw html
<DocMedia src="/examples/bibliography/figures/streaming-comparison.svg" alt="Before and after a Bibliography streaming export change: bytes 3904 to 2976, allocations 27 to 23, median time 7.6 to 6.8 microseconds" caption="Two development revisions with fixed dependency pins, 100 samples each, Windows and Julia 1.13.0. These medians do not describe the earlier 0.4.0 release tag; timing distributions overlap." />
```

```@raw html
<p><a href="../examples/bibliography/streaming-comparison.json">Download the comparison measurements</a>.</p>
```

These are measurements of the checked-in small fixture on one machine. The
timing samples overlap, and the experiment does not estimate a confidence
interval or establish a general speedup. The report's verdict is
`inconclusive`, with `diagnostic` records: the example selects the reference
revision but deliberately sets no acceptance thresholds. A zero GC baseline
also makes a relative GC percentage undefined. The workload has no correctness
oracle, so these numbers do not establish output equivalence.

To turn a comparison into a CI decision, choose metric limits and a minimum
sample count for your workload before measuring; see
[comparison policies](comparisons.md). Keep the original bundle with its
environment and source revisions alongside the report.
