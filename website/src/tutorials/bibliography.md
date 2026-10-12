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

Expected preparation artifacts (no measurement yet):

| Location | Result |
| --- | --- |
| `sources.toml`, `suite.jl` | Pinned targets and the suite definition |
| `.sources/` | Private source checkouts |
| `.controller/` | Separate prepared controller environments |
| `results/` | Destination for later runs |

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

Expected plan: **35 leaves**, seven workloads with five collectors each. The table below is the compact plan content, not a measurement transcript.

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

Expected selection (no worker started):

| Package / workload | Collector leaves |
| --- | --- |
| Bibliography / export_bibtex | benchmark, chairmark, profile_alloc, profile, wall_profile |

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

Choose a collector for **Bibliography → export_bibtex** in the same prepared suite. Timing uses one worker thread, 50 samples, `evals = 1` and 0.5 seconds. Profiles have their own sampling windows. Inspect the selected plan before launching. The outputs below are recorded evidence; none defines a regression budget.

```@raw html
<a id="Open-the-web-studio"></a>
<a id="Use-VS-Code"></a>
```

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

The REPL, VS Code, Pluto and Web controllers select this same suite leaf.
Their launch, cancellation and saved-report controls are covered in the
[interface guides](../interfaces/packages.md).

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

Recorded native-item result, from the VS Code TestItems handler (Julia item scope, not the export-only benchmark):

| Item | Execution | Measured duration |
| --- | --- | --- |
| Bibliography export workload | Passed | 1,993.05 ms |
| Bibliography format API | Unrun | Not measured |

The [saved native receipt](../examples/bibliography/vscode/capture.json) records the real activation, discovery and profile-handler execution. The editor elapsed time includes orchestration; the item timer includes imports, setup and assertions.

- The listing runs nothing.
- `performance` measures only the named item; without a name it measures both declarations.
- `functional` runs the shared functional item only.

In VS Code, set **PerfChecker: Runner Project** to `.controller/items`, then discover items. Each sample still runs in a fresh Julia process.

## Open Pluto

```sh
julia --startup-file=no setup.jl pluto
julia --startup-file=no --project=.controller/pluto pluto.jl
```

Expected result: a Pluto session opens the supplied notebook with package, workload and collector selectors. No measurement starts until **Launch selected checks**. After execution, **Save completed reports** writes the result directory. This is an interface recipe; its controls and recorded result are shown in the [Pluto guide](../interfaces/repl-pluto.md).

## Compare the package history

```sh
julia --project=.controller/core history.jl plan
julia --project=.controller/core history.jl run
```

Nine tagged versions: **0.1.0, 0.2.0, 0.2.5, 0.2.10, 0.2.15, 0.2.20, 0.3.0, 0.3.1, 0.4.0**. 36 leaves: 28 measurable, eight unavailable because `read_and_filter` only exists in 0.4.0.

For Bibliography 0.2.10 the example pins BibParser 0.1.10; its DataStructures constraint is compatible, BibParser 0.1.9 is not.

Dependencies evolve with the package stack, so this history describes the stacks together.

```@raw html
<InteractiveRecordedPlot source="/examples/bibliography/history/export-time.json" html="/examples/bibliography/history/export-time.html" title="Recorded Bibliography export medians across nine tagged versions" kind="version_series" />
```

Inspect a point for its tag and median in nanoseconds. This recorded Windows campaign used Julia 1.13.0, one worker thread and 100 samples per tag.


## Extend to historical comparisons

To isolate one source change, hold dependencies fixed. The [two-revision comparison](comparisons.md) follows the streaming-export change with BibInternal and BibParser pinned.

- `plan_suite(suite; profile = :ci)` selects representative releases and source checkouts.
- `:historical` includes all declared releases.
- An unavailable workload is not a regression.

To locate the calls responsible for a cost, continue with [Investigating a change](../guide/investigate.md).

## Recorded examples

The [recorded run summary](../examples/bibliography/suite-runs.json) preserves the collector, state policy, outcome and source report digest. It records seven completed leaves per collector; `pass` here means the collector executed, not that a correctness oracle or regression budget passed.

```@raw html
<InteractiveRecordedPlot source="/examples/bibliography/history/export-memory.json" html="/examples/bibliography/history/export-memory.html" title="Allocated Julia bytes per export across the same nine Bibliography releases" kind="version_series" />
```

Read this history alongside the timing curve above: Julia allocation bytes range from 4,480 to 8,352. They measure allocation activity, not resident process memory.
