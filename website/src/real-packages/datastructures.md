# DataStructures: a complete container investigation

This guide starts with an independently checkable operation, follows its release
history, investigates its costs, and opens the saved results in each interface.
It covers **35 containers**, with construction and use measured separately.
The detailed matrix includes **every 0.19 release, from 0.19.0 through 0.19.6**.
A second experiment follows representative operations back to 0.11.0.

The examples are runnable Julia files, TestItems and a dedicated Pluto notebook.
The figures below contain recorded measurements. Opening this page or building
the documentation does not execute a benchmark.

## 1. Open the example and check one answer

Get the checkout described in [the example setup](index.md). Run the commands in
this guide from `examples/kitchen-sink`:

```sh
julia setup.jl core
julia --project=. containers.jl check
julia --project=. test/runtests.jl
```

`setup.jl core` prepares this example's environment. It is not a required suite
installation step for ordinary PerfChecker users. The correctness check covers
empty, singleton, 32-element and 512-element inputs for every container operation.
It compares results with ordinary Julia arrays, dictionaries or explicit answers.

Here is the complete lifecycle for one case:

```julia
include("src/containers.jl")
case = ContainerCases.container_case("Deque", "drain"; n=512, seed=42)
state = case.prepare()
answer = case.operation(state)
@assert case.verify(state, answer)
```

`prepare` builds a fresh deque. `operation` removes its entries in FIFO order.
`verify` compares the answer with the original permutation. The runner times only
`operation`; preparation and verification occur outside the measured interval.
For the separate `build` case, constructing the deque is the measured operation.
This distinction prevents a faster constructor from hiding a slower removal path.

## 2. Select a structure, operation and release range

```sh
julia --project=. containers.jl plan
julia --project=. containers.jl quick Deque_drain_benchmark
julia --project=. containers.jl history Deque_drain_benchmark
julia --project=. containers.jl history
```

`plan` lists the 70 latest-release checks. `quick` measures the selected operation
on 0.19.6. `history` follows all seven 0.19 releases; without a case name it runs
490 checks. Every timing check uses **30 samples after warmup, with `evals=1`**.
Each sample starts with freshly prepared state, which matters for destructive
queues and self-adjusting search trees.

To rerun just the neighboring versions around an observed change:

```julia
using PerfChecker, BenchmarkTools
include("containers-suite.jl")
plan = plan_suite(build_container_suite(); profile=:historical,
    version_provider=_ -> CONTAINER_VERSIONS)
selected = filter_suite_plan(plan;
    features=[:Deque_drain_benchmark], from_version=v"0.19.2", to_version=v"0.19.3")
print_suite_plan(selected)
result = run_suite_repl(selected; reports="results/deque-pair")
```

The same cases are individually discoverable TestItems:

```sh
julia --project=. items.jl list
julia --project=. items.jl run deque
```

`test/container-items.jl` contains a construction item and a use item for each
structure, tagged `:perf_only`, `:containers` and the structure's name. The
ordinary test runner excludes `:perf_only`. PerfChecker can select them by tag.
Timing a TestItem includes its setup and assertions; the narrower suite lifecycle
above excludes them. These are two useful measurement boundaries, not identical results.

## 3. Inspect every container separately

Each container has two visible figures. Wall time is elapsed operation time.
GC time is the portion attributed to Julia's garbage collector. Allocated bytes
and allocation count measure allocation activity; neither measures the resident
memory of the process.

For each metric, the overlay divides the minimum observed sample at each release
by that metric's minimum across releases. One therefore means the lowest observed
value for that metric. A zero GC minimum means that a short sample contained no
collection, not that garbage collection is free. An all-zero metric is shown at
one by convention; a ratio against zero is otherwise unavailable.

The captions identify candidate release boundaries from the recorded time minima.
They are observations, not automatic regression verdicts. Inspect the distribution
and repeat the adjacent pair on an otherwise idle machine before attributing a
change to a commit. The cases below use 512 unique integer keys, except counters
and multidictionaries, which group them into 16 categories. Different sizes,
key distributions and operation mixes can change the result.

```@raw html
<WorkloadAtlas directory="/examples/real-packages/containers" containers />
```

The full catalogue keeps each metric on its own scale, sample distributions,
version deltas and time/allocation trade-offs. These additional views use the
same saved observations:

```@raw html
<PackageGallery package-name="DataStructures container catalogue" directory="/examples/real-packages/containers" />
```

To corroborate a selected case with Chairmarks:

```sh
julia --project=. containers.jl chairmarks Deque_drain_chairmark
```

Omit the case name to measure all 70 operations on 0.19.6 with Chairmarks. Keep
BenchmarkTools and Chairmarks results separate: their collector identities and
sampling machinery differ.

The following figures place the **70 operations on 0.19.6** side by side for
both collectors. Each container has four panels with absolute values: time,
GC share, allocated bytes and allocation count. Each panel separates construction
from use. The bars show minima from 30 samples, without merging the two collectors'
observations or treating one collector's overhead as a package improvement.
Zero GC bars mean no collection occurred in the selected minimum sample.
Time is converted to microseconds: BenchmarkTools records nanoseconds, while
Chairmarks records seconds. For GC, BenchmarkTools' paired time samples are
converted to per-sample GC fractions before taking the minimum; Chairmarks already
records a GC fraction. The panel shows both as percentages. This conversion does
not make their sampling machinery identical.

```@raw html
<RecordedFigures directory="/examples/real-packages/containers-collectors" />
```

Regenerate these panels from your own completed reports:

```sh
julia --project=.controller/plots collector-export.jl results/CONTAINER-HISTORY results/CHAIRMARKS-RUN exports/collectors
```

## 4. Follow eight years of releases

```sh
julia --project=. measure.jl history
```

This selects **20 releases, from 0.11.0 (August 2018) to 0.19.6 (July 2026)**:
four BenchmarkTools workloads and one Chairmarks heap workload per version.
The controller prepares separate target environments; the workload source and
seed remain fixed. There are **100 checks**, each with an independent correctness oracle.

| Release | Published | Why keep this point? |
| --- | --- | --- |
| 0.11.0 | 2018-08-07 | Earliest release that passed this example on Julia 1.13 |
| 0.12.0 | 2018-09-11 | New sorted-container iteration protocol and package project file |
| 0.13.0 | 2018-09-21 | OrderedCollections split into a dependency |
| 0.14.0 | 2018-09-24 | Last selected generation before the heap constructor rename |
| 0.15.0 | 2019-01-08 | Old heap constructors deprecated |
| 0.16.1 | 2019-07-05 | Intermediate container generation |
| 0.17.0 | 2019-07-05 | Deprecated APIs removed |
| 0.17.20 | 2020-08-04 | Last release before the 0.18 heap refactor |
| 0.18.0 | 2020-08-17 | Heaps adopt Base ordering; circular-container optimizations |
| 0.18.10 | 2021-08-09 | A point within the long-lived 0.18 series |
| 0.18.13 | 2022-05-24 | A later 0.18 point |
| 0.18.15 | 2023-08-03 | A later 0.18 point |
| 0.18.22 | 2025-03-18 | Last release before 0.19 |
| 0.19.0 | 2025-08-01 | Breaking container APIs and a higher minimum Julia version |
| 0.19.1 | 2025-08-26 | Follow every patch in the current series |
| 0.19.2 | 2025-11-04 | Follow every patch in the current series |
| 0.19.3 | 2025-11-04 | Follow every patch in the current series |
| 0.19.4 | 2026-03-27 | Follow every patch in the current series |
| 0.19.5 | 2026-06-01 | Follow every patch in the current series |
| 0.19.6 | 2026-07-17 | Latest selected release |

Dates are GitHub release publication dates, which can differ from the commit
date. Versions are equally spaced in the plots: the distance between points
does not represent elapsed calendar time. The downloaded values include the dates.

### Keep the operation stable across an API break

Before 0.15, the public min-heap constructor was `binary_minheap(input)`.
The example selects it or `BinaryMinHeap(input)` once when the module loads;
the measured operation still constructs and drains a min-heap in both cases.
The sorted-output oracle is unchanged. This bridges a spelling change without
substituting a modern implementation into an old package.

The [0.18 release](https://github.com/JuliaCollections/DataStructures.jl/releases/tag/v0.18.0)
changed heap ordering and optimized circular containers. The
[0.19 release](https://github.com/JuliaCollections/DataStructures.jl/releases/tag/v0.19.0)
also changed queue and disjoint-set APIs. The present workloads do not exercise
every changed API: a stable counter curve cannot establish that all containers
are unchanged. Compare 0.17.20 with 0.18.0 for the heap transition, and 0.18.22
with 0.19.0 for the next major package generation.

### Where the history stops

`compatibility.jl DataStructures` checks old releases in separate processes,
including empty and singleton cases. **0.9.0 and 0.10.0 fail to load on Julia
1.13** because they define methods for the removed `Base.start` iteration API.
They are omitted, rather than plotted as zero or patched inside the package.
0.11.0 passes. Going further back would require a separate historical-Julia
experiment; mixing that into this curve would change both the package and runtime.

All points here are measured *today* on the same Julia runtime and local machine.
They are not measurements of what a machine running Julia in 2018 achieved.

### Four measurements on one plot

Elapsed time measures how long the operation took. GC time measures the part
attributed to Julia's garbage collector, which reclaims unreachable objects.
Allocated bytes and allocation count measure allocation activity, not the size
of the live heap or total resident memory.

Each curve below uses the minimum sample for each version, divided by that
metric's minimum across versions. Thus each metric has a reference value of
one despite having a different unit. You can hide a curve and inspect its raw
values. A zero GC sample is common for a short operation; it does not prove
that the workload never triggers garbage collection.

```@raw html
<NormalizedMeasurements source="/examples/real-packages/datastructures/normalized.json" figure="/examples/real-packages/datastructures/normalized.svg" package-name="DataStructures" />
```

Compare 0.17.20 and 0.18.0 alongside the heap refactor, then examine each 0.19
patch for smaller changes. The interactive figure exposes the recorded values.
Repeat a candidate pair, inspect the distributions and compare the vector
control before attributing a speedup to a particular implementation change.

Here are all four event workloads, plus the independent Chairmarks heap capture:

```@raw html
<WorkloadAtlas directory="/examples/real-packages/datastructures" />
```

### Explore the separate curves and distributions

The gallery also retains each measure on its own scale. A distribution exposes
sample variation hidden by one summary value. The version trajectory uses its
documented aggregation; do not assume that its median equals the overlay's
minimum. BenchmarkTools and Chairmarks remain separate measurement definitions.

```@raw html
<PackageGallery package-name="DataStructures" directory="/examples/real-packages/datastructures" />
```

The vector implementation mostly exercises Base Julia, so it also acts as a
control. Changes in its timing across package tags can reflect machine noise
rather than a DataStructures change. Investigate and repeat a suspected
improvement before attributing it to a release.


## 5. Explain the cost with profiles and diagnostics

A timing history tells you where to investigate. A profiler helps explain which
call paths consume a resource. The following diagnostic example uses the heap
workload with 2,048 events; CPU/allocation profile runs use their recorded sizes.
It is separate from the 512-key container matrix above.

```sh
julia --project=. measure.jl profiles
julia setup.jl analyzers
julia --project=.controller/analyzers scenarios.jl diagnose datastructures events-heap
```

### CPU, wall time and allocation stacks

A CPU profile samples execution on the processor. A wall-time profile can also
expose waiting. An allocation profile attributes sampled allocated objects or
bytes to call paths. A flame graph aggregates those paths: width represents the
chosen weight, while vertical position represents nested calls. It is not a timeline.

```@raw html
<RecordedFigures directory="/examples/real-packages/datastructures-profiles" />
```

The profiler changes execution costs. After changing a suspicious allocation or
call path, return to the ordinary timing collector and rerun its correctness oracle.
Very short operations may produce sparse CPU profiles; a blank profile is not
proof that no work occurred.

```@raw html
<DiagnosticReports source="/examples/real-packages/datastructures-diagnostics/diagnosis.json" />
```

### Loading, compilation and warm execution

JET examines inferred execution paths for possible errors. AllocCheck identifies
statically visible allocation sites. SnoopCompile measures inference work in its
recorded scope. They answer different questions from a stopwatch.

The latency diagnostic separates source loading, the first operation, and a warm
operation. These three values explain why a fast repeated operation can still
feel slow in an interactive session. The chart uses a logarithmic vertical scale.

```@raw html
<DocMedia src="/examples/real-packages/datastructures-diagnostics/latency.svg" alt="Loading, first-operation and warm-operation latency for the DataStructures heap" />
```

### Allocation pressure and garbage collection

The GC diagnostic records five operations with process-wide counters. Allocated
bytes can be nonzero while GC time is zero: the allocator has not necessarily
needed a collection within these short observation windows. These diagnostic
observations are separate from the 30-sample timing campaigns.

```@raw html
<DocMedia src="/examples/real-packages/datastructures-diagnostics/gc.svg" alt="Allocated bytes and garbage-collection time for five heap operations" />
```

### Reachable objects, resident memory and locks

Reachable-object size estimates the objects retained by the input and result.
Resident set size (RSS) is the memory currently resident for the entire process,
including Julia and native libraries. A flat input size with a larger result is
not a memory leak. A leak investigation requires repeated retention evidence
and an understanding of intended caches and outputs.

```@raw html
<PluginTabs>
<PluginTabsTab label="Memory"><DocMedia src="/examples/real-packages/datastructures-diagnostics/memory.svg" alt="Reachable state and result sizes beside resident process memory" /></PluginTabsTab>
<PluginTabsTab label="Locks"><DocMedia src="/examples/real-packages/datastructures-diagnostics/locks.svg" alt="Observed lock-conflict counts for five heap operations" /></PluginTabsTab>
</PluginTabs>
```

The lock diagnostic counts observed conflicts; it does not measure waiting duration.
This single-threaded heap case is a baseline, not a contention stress test.
The downloadable records contain tool versions, findings, scopes and the numerical
observations behind these figures.

```@raw html
<p><a href="../examples/real-packages/datastructures-diagnostics/diagnosis.json" download>Download the complete diagnostic records</a></p>
```

### Native tools and non-Julia dependencies

Valgrind Callgrind counts instrumented instructions and calls; Cachegrind models
cache activity; Massif samples native heap usage. Those values include Julia
startup and JIT work in the whole-process captures. They must not be substituted for native
wall-time measurements. Memcheck checks memory accesses and leaks; heaptrack
tracks native allocation activity. A tool exit does not replace the workload oracle.

On Linux or WSL:

```sh
julia setup-linux.jl
julia --startup-file=no --project=.controller/linux setup-native.jl
julia --project=.controller/linux native-run.jl datastructures
```

Each tool gets a bounded 512-event, three-operation workload and a 180-second
budget. The script records unavailable tools, unsuccessful executions and oracle
results explicitly. Large raw profiles remain local; share them as release assets
when useful. The following capture completed Callgrind, Cachegrind, Massif and
heaptrack with a passing workload oracle. Memcheck completed the workload but
reported findings: these need investigation, not a blanket claim that
DataStructures has a memory error. Julia's runtime and JIT are also in scope.

```@raw html
<DiagnosticReports source="/examples/real-packages/datastructures-native/summary.json" />
<DocMedia src="/examples/real-packages/datastructures-native/massif-1.svg" alt="Massif native heap, allocator overhead and tracked stacks through one Julia process" />
```

Massif's horizontal axis is instrumented instructions, not elapsed seconds.
Its native heap includes Julia runtime allocations and is different from Julia's
GC object graph. Each process has its own timeline.

A second Callgrind capture excludes startup and counts three warmed lifecycles,
including their preparation and oracle. It recorded 550,591 instrumented
instructions for this fixed fixture. This is neither CPU time nor a release comparison.

```@raw html
<DiagnosticReports source="/examples/real-packages/datastructures-callgrind/summary.json" />
```

### Package quality and the live Julia heap

```sh
julia --project=.controller/analyzers additional-diagnostics.jl datastructures
```

Aqua found three methods with unbound type parameters in the default-dictionary
family. This is a package-quality finding, not evidence that the measured heap
operation became slower. The tool output below identifies the methods.

The heap snapshot records GC-managed objects in the whole worker. The chart
groups their **shallow sizes** by object category; it does not compute the memory
that would be reclaimed by removing a reference. The redacted raw snapshot stays
local because it is large. The smaller exported summary can be shared.

```@raw html
<DiagnosticReports source="/examples/real-packages/datastructures-diagnostics/additional.json" />
<DocMedia src="/examples/real-packages/datastructures-diagnostics/heap-types.svg" alt="Shallow sizes of GC-managed object categories in the DataStructures diagnostic worker" />
```

## 6. Keep inputs and experiment provenance

PropCheck and Supposition generate additional correctness cases. Freezing their
corpus lets every release receive the same inputs, rather than a different random
test. The provided corpus has 40 seeded cases. It supplements the explicit oracles;
it is not statistical evidence of a speedup.

```sh
julia setup.jl extras
julia --project=.controller/extras corpus.jl
julia --project=.controller/extras drwatson.jl run datastructures
```

DrWatson keeps experiment parameters with cached results. A second invocation
can reuse a result; set `PERFCHECKER_FORCE=true` to request a fresh execution.
Do not count a cache hit as another independent measurement.

For a shared scenario catalog and its portable bundles:

```sh
julia --project=. scenarios.jl plan datastructures
julia --project=. scenarios.jl run datastructures
```

The scenario file describes parameters, fixture paths, preparation, operation and
verification. Its JSON report identifies completed observations and failed oracles.
Use report provenance when comparing machines; similar CPU specifications alone
do not establish equivalent performance. Cross-machine prediction needs a calibration
matrix measured on several machines, which this one-machine example does not provide.

## 7. Replay the same experiment in each interface

### REPL and Unicode terminal plots

```sh
julia --project=. replay.jl results/YOUR-CONTAINER-RUN
```

For a downloaded plot, the helper avoids needing a complete local campaign:

```julia
using PerfChecker, UnicodePlots
include("replay.jl")
terminal_plot(saved_plot("downloaded-plot.json"))
```

### Makie and exportable figures

```sh
julia setup.jl plots
julia --project=.controller/plots export.jl results/YOUR-CONTAINER-RUN exports/containers
```

This writes SVG, JSON and Unicode text for every catalogue view. It is the same
export path used for the figures on this page. With WGLMakie loaded,
`performance_plot_html(model)` creates the corresponding standalone interactive view.

### A dedicated Pluto notebook

```@raw html
<p><a href="../examples/real-packages/datastructures-notebook.jl" download>Download the DataStructures notebook (.jl)</a></p>
```

```sh
julia +1.12 setup.jl pluto
julia +1.12 --project=.controller/pluto -e 'using Pluto; Pluto.run(notebook="datastructures-notebook.jl", threads=1)'
```

Choose a container and operation, check its answer, inspect its seven-release
history, then switch between Makie and Unicode plots. The notebook reads the
published data included in the checkout; opening it does not launch 490 checks.
It also contains the commands for measuring your own cases and investigating costs.
The profile selector and diagnostic figures let you inspect the recorded heap
experiment alongside the container histories, with their different scopes stated.

### Web Studio and VS Code

```sh
julia setup.jl web
julia --project=.controller/web web.jl containers
# To reopen a completed run directly:
julia --project=.controller/web web.jl results/YOUR-CONTAINER-RUN
```

Select the container operation, collector and version range before launching.
Choose the **historical** profile to expose all seven releases. To reproduce the
published timing settings, set **Samples = 30**, **Evals = 1**, **Seconds = 0.25**
and **Threads = 1** in the Studio before launching the selected cases.
In VS Code, open the example directory; the container TestItems can be run
individually. For suite-based execution, select `containers-suite.jl` and its
`build_container_suite` factory. Both interfaces consume saved reports, so a new
view does not require a new benchmark.

For a VS Code workspace opened at `examples/kitchen-sink`, set:

```json
{
  "perfchecker.suite": "containers-suite.jl",
  "perfchecker.factory": "build_container_suite",
  "perfchecker.runnerProject": "."
}
```

Use **PerfChecker: Discover existing test items** for the individual item runner,
or **PerfChecker: Open visual suite editor** for the historical matrix.

To generate a Pluto controller with explicit launch buttons:

```sh
julia +1.12 --project=.controller/pluto controller-notebook.jl containers
```

## 8. Turn a candidate regression into a reproducible report

Keep the workload, input seed, Julia version and dependency environment fixed.
Rerun the adjacent release pair, inspect all samples, and verify that the oracle
still passes. A performance threshold is meaningful only after choosing the
metric, aggregation and acceptable noise for your workload.

Suite reports include JSON, Markdown and JUnit for CI. Documenter and
DocumenterVitepress can render a saved bundle without rerunning it:

```sh
julia --project=.controller/extras documenter.jl results/YOUR-CONTAINER-RUN
julia --project=.controller/extras profiles.jl results/YOUR-PROFILE-RUN exports/profiles
```

The second command exports folded stacks, Speedscope and pprof when their
extensions are loaded. Keep the report and environment fingerprints with an
issue or proposed optimization. The [contribution guide](contributing.md)
explains how to contribute another real-package story with its evidence.
