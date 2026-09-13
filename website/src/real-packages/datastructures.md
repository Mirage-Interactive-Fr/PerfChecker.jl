# DataStructures: a complete container investigation

Constructing a container and using it can have quite different costs. For
example, a deque may be cheap to drain but expensive to build. Measuring the
two operations separately lets us see which one changes between releases.

This example measures **35 containers** across **DataStructures 0.19.0–0.19.6**,
then follows a smaller set of workloads back to 0.11.0. It includes scripts,
TestItems and a Pluto notebook. The figures use saved results, which you can
explore before running the benchmarks yourself.

## 1. Open the example and check one answer

Get the checkout described in [the example setup](index.md). Run the commands in
this guide from `examples/kitchen-sink`:

```sh
julia setup.jl core
julia --project=. containers.jl check
julia --project=. test/runtests.jl
```

`setup.jl core` installs the dependencies used by this example. The correctness check covers
empty, singleton, 32-element and 512-element inputs for every container operation.
It compares results with ordinary Julia arrays, dictionaries or explicit answers.

For example, the deque test has three parts:

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
above excludes them. Choose the TestItem when you want the cost of the whole
test, or the suite case when you want the cost of the container operation alone.

## 3. Inspect every container separately

Each container has a tab for construction and a tab for use. Wall time is elapsed operation time.
GC time is the portion attributed to Julia's garbage collector. Allocated bytes
and allocation count measure allocation activity; neither measures the resident
memory of the process.

For each metric, the overlay divides the minimum observed sample at each release
by that metric's minimum across releases. One therefore means the lowest observed
value for that metric. A zero GC minimum means that a short sample contained no
collection, not that garbage collection is free. An all-zero metric is shown at
one by convention; a ratio against zero is otherwise unavailable.

Each caption identifies the largest increase in minimum time between adjacent
releases. Rerun that pair on an otherwise idle machine and compare the sample
distributions before investigating the source change.

The cases use 512 unique integer keys. Counters and multidictionaries group
those keys into 16 categories. To adapt the example, try the sizes and key
distributions used by your application; they affect the relative costs of
construction, lookup and mutation.

```@raw html
<p>Choose an operation in each container's tabs. Hover or focus a point for its value; use the metric buttons to show or hide curves.</p>
<WorkloadAtlas directory="/examples/real-packages/containers" containers />
```

The full catalogue keeps each metric on its own scale, sample distributions,
version deltas and time/allocation trade-offs. These additional views use the
same saved observations:

```@raw html
<PackageGallery package-name="DataStructures container catalogue" directory="/examples/real-packages/containers" />
```

To measure the same operation with Chairmarks:

```sh
julia --project=. containers.jl chairmarks Deque_drain_chairmark
```

Omit the case name to measure all 70 operations on 0.19.6 with Chairmarks.
Keep the two collectors' samples separate: they use different sampling
procedures, even when their output units have been converted to match.

The figures below compare both collectors on **all 70 operations at 0.19.6**.
Each group of bars shows construction and use, with one color per collector.
Select time, GC share, allocated bytes or allocation count above each figure.
Each bar is the minimum of 30 samples collected by that tool.

The exporters convert time to microseconds because BenchmarkTools records
nanoseconds and Chairmarks records seconds. For the GC view, they divide each
BenchmarkTools GC time by its matching elapsed time, then take the minimum;
Chairmarks already supplies that fraction. Both are displayed as percentages.
A zero bar means at least one sample completed without a collection. Differences
between the bars can also reflect how the two tools collect samples.

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
Both cases check that the output is sorted. This lets the same workload use
each release's public API.

The [0.18 release](https://github.com/JuliaCollections/DataStructures.jl/releases/tag/v0.18.0)
changed heap ordering and optimized circular containers. The
[0.19 release](https://github.com/JuliaCollections/DataStructures.jl/releases/tag/v0.19.0)
also changed queue and disjoint-set APIs. Compare 0.17.20 with 0.18.0 to examine
the heap transition, and 0.18.22 with 0.19.0 for the next series. The five
historical workloads cover only some of those API changes; the 70-operation
matrix above provides more detail within 0.19.

### Where the history stops

`compatibility.jl DataStructures` checks old releases in separate processes,
including empty and singleton cases. **0.9.0 and 0.10.0 fail to load on Julia
1.13** because they define methods for the removed `Base.start` iteration API.
The history therefore starts at 0.11.0. Testing earlier versions requires an
older Julia runtime; see [Julia runtime comparisons](../tutorials/julia-runtimes.md).
All points here use Julia 1.13 on the same machine, including the older package
releases.

### Four measurements on one plot

The overlay uses the same normalization as the container plots: divide each
version's minimum by the lowest minimum across releases, separately for each
metric. A value of two means twice that metric's lowest observed value. Toggle
a curve to hide it, or select a point to inspect the raw value and unit.

```@raw html
<NormalizedMeasurements source="/examples/real-packages/datastructures/normalized.json" figure="/examples/real-packages/datastructures/normalized.svg" package-name="DataStructures" />
```

The following figures show all four event workloads and the separate Chairmarks
heap measurements:

```@raw html
<WorkloadAtlas directory="/examples/real-packages/datastructures" />
```

### Explore the separate curves and distributions

Use the gallery to inspect individual metrics and sample distributions.
The trajectory views use the statistic named in their labels; a median
trajectory will generally differ from the minimum used in the overlay.

```@raw html
<PackageGallery package-name="DataStructures" directory="/examples/real-packages/datastructures" />
```

The vector implementation mostly exercises Base Julia, so it also acts as a
control. Changes in its timing across package tags can reflect machine noise
rather than a DataStructures change. Investigate and repeat a suspected
improvement before attributing it to a release.


## 5. Explain the cost with profiles and diagnostics

A profile helps locate the calls responsible for a workload's time or
allocations. The diagnostics below use the heap workload with 2,048 events.
The CPU and allocation profile sizes are recorded with each figure; they
are separate runs from the 512-key container benchmarks.

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

If an operation is too short to collect useful CPU samples, increase the input
size or profile repeated calls. Use the resulting call paths to choose a change,
then measure it again with BenchmarkTools or Chairmarks to avoid profiling overhead.

```@raw html
<DiagnosticReports source="/examples/real-packages/datastructures-diagnostics/diagnosis.json" />
```

### Loading, compilation and warm execution

JET examines inferred execution paths for possible errors. AllocCheck identifies
statically visible allocation sites. SnoopCompile measures inference work, which
can explain why the first call takes longer than subsequent calls.

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
including Julia and native libraries. When investigating memory growth, repeat
the operation and check which objects remain reachable after discarding its
result. Account for caches that are expected to retain data between calls.

```@raw html
<PluginTabs>
<PluginTabsTab label="Memory"><DocMedia src="/examples/real-packages/datastructures-diagnostics/memory.svg" alt="Reachable state and result sizes beside resident process memory" /></PluginTabsTab>
<PluginTabsTab label="Locks"><DocMedia src="/examples/real-packages/datastructures-diagnostics/locks.svg" alt="Observed lock-conflict counts for five heap operations" /></PluginTabsTab>
</PluginTabs>
```

The lock diagnostic counts conflicts. This example runs on one thread; testing
contention requires a workload with concurrent access. The download contains
the numerical observations, tool versions and full diagnostic messages.

```@raw html
<p><a href="../examples/real-packages/datastructures-diagnostics/diagnosis.json" download>Download the complete diagnostic records</a></p>
```

### Native tools and non-Julia dependencies

Valgrind Callgrind counts instrumented instructions and calls; Cachegrind models
cache activity; Massif samples native heap usage. The whole-process captures
include Julia startup and JIT work. Memcheck checks memory accesses and leaks,
while heaptrack tracks native allocations. These tools can inspect runtime and
library costs that Julia's allocation profiler does not record.

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
reported findings. Inspect their call stacks to locate the affected code;
the capture includes Julia's runtime and JIT as well as DataStructures.

```@raw html
<DiagnosticReports source="/examples/real-packages/datastructures-native/summary.json" />
<DocMedia src="/examples/real-packages/datastructures-native/massif-1.svg" alt="Massif native heap, allocator overhead and tracked stacks through one Julia process" />
```

Massif's horizontal axis is instrumented instructions, not elapsed seconds.
Its native heap includes Julia runtime allocations and is different from Julia's
GC object graph. Each process has its own timeline.

A second Callgrind capture excludes startup and counts three warmed lifecycles,
including their preparation and oracle. It recorded 550,591 instrumented
instructions for this fixed fixture.
The count is instrumented instructions, not CPU time, and this capture measures
one revision rather than a change between releases.

```@raw html
<DiagnosticReports source="/examples/real-packages/datastructures-callgrind/summary.json" />
```

### Package quality and the live Julia heap

```sh
julia --project=.controller/analyzers additional-diagnostics.jl datastructures
```

Aqua checks package quality. It found three methods with unbound type parameters
in the default-dictionary family. Expand the report to see the methods; this
check is independent of the heap timings above.

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
corpus gives every release the same inputs. The provided corpus has 40 seeded
cases, each checked against the reference answer.

```sh
julia setup.jl extras
julia --project=.controller/extras corpus.jl
julia --project=.controller/extras drwatson.jl run datastructures
```

DrWatson keeps experiment parameters with cached results. A second invocation
can reuse a result; set `PERFCHECKER_FORCE=true` to request a fresh execution.
A reused result contributes no new samples to the experiment.

For a shared scenario catalog and its portable bundles:

```sh
julia --project=. scenarios.jl plan datastructures
julia --project=. scenarios.jl run datastructures
```

The scenario file describes the parameters, fixture paths, preparation,
operation and verification. Its JSON report stores the measurements and check
results. For comparisons between machines, see [machine calibration](../machine-transfer.md);
that workflow needs additional measurements from each participating machine.

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
