```@raw html
<a id="DataStructures:-a-complete-container-investigation"></a>
```

# DataStructures: 35 containers

Construction and use of a container can cost very differently. A deque may be cheap to drain and expensive to build.

This example measures **35 containers** across **DataStructures 0.19.0–0.19.6**, then follows five workloads back to 0.11.0.

```@raw html
<a id="1.-Open-the-example-and-check-one-answer"></a>
```

## Open the example

Run from `examples/kitchen-sink`:

```sh
julia setup.jl core
julia --project=. containers.jl check
julia --project=. test/runtests.jl
```

`check` covers empty, singleton, 32-element and 512-element inputs for every operation, comparing against ordinary arrays, dictionaries or explicit answers.

For the deque, the case has three parts:

- `prepare` builds a fresh deque;
- `operation` removes entries in FIFO order;
- `verify` compares the answer with the original permutation.

The runner times only `operation`. For the separate `build` case, construction is the measured operation — a faster constructor cannot hide a slower removal path.

```@raw html
<a id="2.-Select-a-structure,-operation-and-release-range"></a>
```

## Select a structure, operation and range

```sh
julia --project=. containers.jl plan
julia --project=. containers.jl quick Deque_drain_benchmark
julia --project=. containers.jl history Deque_drain_benchmark
julia --project=. containers.jl history
```

- `plan` lists the 70 latest-release checks.
- `quick` measures one operation on 0.19.6.
- `history` follows all seven 0.19 releases; without a case name it runs 490 checks.
- Every timing check uses **30 samples after warmup, `evals=1`**, with fresh state per sample.

Narrow to neighbors around a change:

```julia
using PerfChecker, BenchmarkTools
include("containers-suite.jl")
plan = plan_suite(build_container_suite(); profile = :historical,
    version_provider = _ -> CONTAINER_VERSIONS)
selected = filter_suite_plan(plan;
    features = [:Deque_drain_benchmark], from_version = v"0.19.2", to_version = v"0.19.3")
result = run_suite_repl(selected; reports = "results/deque-pair")
```

The same cases exist as TestItems tagged `:perf_only`, `:containers` and the structure name.

- A TestItem measurement includes setup and assertions.
- The suite case excludes them.

Choose the item for whole-test cost, the suite for the container operation alone.

```@raw html
<p>Choose an operation in each container's tabs. Guided views with a public HTML export provide point inspection and metric checkboxes; the other operations retain their matching static SVG and downloadable measurements.</p>
<WorkloadAtlas directory="/examples/real-packages/containers" containers />
```


```@raw html
<a id="3.-Inspect-every-container-separately"></a>
<a id="Four-measurements-on-one-plot"></a>
<a id="Explore-the-separate-curves-and-distributions"></a>
```

Each container has a tab for construction and a tab for use. The overlay divides each release's minimum sample by that metric's minimum across releases; `1` is the lowest observed value. A zero GC minimum means a short sample had no collection, not that collection is free.

The selected SortedSet lookup examples include interactive normalized curves,
version curves, distributions, deltas and tradeoffs. Other catalogue entries
show their static SVG. Open a full-size figure or download its JSON to inspect
the recorded observations.

```@raw html
<PackageGallery package-name="DataStructures container catalogue" directory="/examples/real-packages/containers" />
```


Chairmarks measures the same operations separately:

```sh
julia --project=. containers.jl chairmarks Deque_drain_chairmark
```

Keep the two collectors' samples separate; they sample differently.

```@raw html
<RecordedFigures directory="/examples/real-packages/containers-collectors" />
```


```@raw html
<a id="4.-Follow-eight-years-of-releases"></a>
```

## Follow eight years of releases

```sh
julia --project=. measure.jl history
```

20 releases from 0.11.0 (2018) to 0.19.6 (2026): four BenchmarkTools workloads and one Chairmarks heap workload per version. 100 checks, each with an independent oracle.

Versions are equally spaced in the plot; the distance does not represent calendar time.

### Keep the operation stable across an API break

Before 0.15 the min-heap constructor was `binary_minheap(input)`. The example selects it or `BinaryMinHeap(input)` once at module load; both construct and drain a min-heap and check the output is sorted.

Compare 0.17.20 with 0.18.0 for the heap ordering transition, and 0.18.22 with 0.19.0 for the next series.

The figures below are PerfChecker exports of the recorded measurements. The
gallery embeds the public HTML export when one is published, with its own metric
controls, and otherwise shows the static SVG. Its workload navigation belongs to
this documentation. To open the same plot outside the site or render its saved
JSON again, follow [Render a published serialized view again](../interfaces/visualization.md#Render-a-published-serialized-view-again).
Rendering the JSON preserves its recorded values; it does not recreate a complete
run bundle or perform a new benchmark.

### Where the history stops

`compatibility.jl DataStructures` checks old releases in separate processes. **0.9.0 and 0.10.0 fail to load on Julia 1.13** because they define methods for the removed `Base.start` API, so the history starts at 0.11.0. Testing earlier versions needs an older Julia runtime.

```@raw html
<NormalizedMeasurements source="/examples/real-packages/datastructures/normalized.json" figure="/examples/real-packages/datastructures/normalized.svg" html="/examples/real-packages/datastructures/normalized.html" package-name="DataStructures" />
<WorkloadAtlas directory="/examples/real-packages/datastructures" />
<PackageGallery package-name="DataStructures" directory="/examples/real-packages/datastructures" />
```


The vector implementation mostly exercises Base Julia, so it acts as a control. Changes in its timings across tags are likely machine noise, not a DataStructures change.

```@raw html
<a id="5.-Explain-the-cost-with-profiles-and-diagnostics"></a>
<a id="CPU,-wall-time-and-allocation-stacks"></a>
```

## Explain the cost

These recorded profiles describe **DataStructures 0.19.6 only**. They attribute
work within that release, rather than comparing two releases. Use the measured
histories above to compare versions, then profile a workload to locate its cost.

```sh
julia --project=. measure.jl profiles
julia setup.jl analyzers
julia --project=.controller/analyzers scenarios.jl diagnose datastructures events-heap
```

```@raw html
<RecordedFigures directory="/examples/real-packages/datastructures-profiles" />
```


- **JET** examines inferred paths for possible errors.
- **AllocCheck** finds statically visible allocation sites.
- **SnoopCompile** measures inference work, which can explain a slow first call.
- The latency diagnostic separates source loading, first operation and warm operation.

```@raw html
<a id="Loading,-compilation-and-warm-execution"></a>
<a id="Allocation-pressure-and-garbage-collection"></a>
<a id="Reachable-objects,-resident-memory-and-locks"></a>
```

```@raw html
<DiagnosticReports source="/examples/real-packages/datastructures-diagnostics/diagnosis.json" />
<DocMedia src="/examples/real-packages/datastructures-diagnostics/latency.svg" alt="Loading, first-operation and warm-operation latency for the DataStructures heap" />
<DocMedia src="/examples/real-packages/datastructures-diagnostics/gc.svg" alt="Allocated bytes and garbage-collection time for five heap operations" />
<PluginTabs>
<PluginTabsTab label="Memory"><DocMedia src="/examples/real-packages/datastructures-diagnostics/memory.svg" alt="Reachable state and result sizes beside resident process memory" /></PluginTabsTab>
<PluginTabsTab label="Locks"><DocMedia src="/examples/real-packages/datastructures-diagnostics/locks.svg" alt="Observed lock-conflict counts for five heap operations" /></PluginTabsTab>
</PluginTabs>
<p><a href="../examples/real-packages/datastructures-diagnostics/diagnosis.json" download>Download the complete diagnostic records</a></p>
```


The lock diagnostic counts conflicts; this example runs on one thread. RSS is memory resident for the whole process, including Julia and native libraries. Growth can reflect intended output or a cache, not necessarily a leak.

```@raw html
<a id="Native-tools-and-non-Julia-dependencies"></a>
```

### Native tools

On Linux or WSL:

```sh
julia setup-linux.jl
julia --startup-file=no --project=.controller/linux setup-native.jl
julia --project=.controller/linux native-run.jl datastructures
```

Each tool gets a bounded 512-event, three-operation workload and a 180-second budget. The script records unavailable tools, failures and oracle results explicitly.

- Massif's horizontal axis is instrumented instructions, not seconds.
- Native heap includes Julia runtime allocations and differs from the GC object graph.
- Memcheck checks memory accesses and leaks.

```@raw html
<DiagnosticReports source="/examples/real-packages/datastructures-native/summary.json" />
<DocMedia src="/examples/real-packages/datastructures-native/massif-1.svg" alt="Massif native heap, allocator overhead and tracked stacks through one Julia process" />
<DiagnosticReports source="/examples/real-packages/datastructures-callgrind/summary.json" />
```


A second Callgrind capture excludes startup and counts three warmed lifecycles: 550,591 instrumented instructions for this fixture — instruction count, not CPU time, for one revision.

```@raw html
<a id="Package-quality-and-the-live-Julia-heap"></a>
```

### Package quality

```sh
julia --project=.controller/analyzers additional-diagnostics.jl datastructures
```

Aqua found three methods with unbound type parameters in the default-dictionary family — independent of the heap timings.

The heap snapshot groups GC-managed objects by **shallow size**; it does not compute what removing a reference would reclaim. The raw snapshot stays local; the exported summary is shareable.

```@raw html
<DiagnosticReports source="/examples/real-packages/datastructures-diagnostics/additional.json" />
<DocMedia src="/examples/real-packages/datastructures-diagnostics/heap-types.svg" alt="Shallow sizes of GC-managed object categories in the DataStructures diagnostic worker" />
```


```@raw html
<a id="6.-Keep-inputs-and-experiment-provenance"></a>
```

## Keep inputs reproducible

PropCheck and Supposition generate extra correctness cases; freezing their corpus gives every release the same inputs (40 seeded cases).

```sh
julia setup.jl extras
julia --project=.controller/extras corpus.jl
julia --project=.controller/extras drwatson.jl run datastructures
```

DrWatson keeps parameters with cached results. A second invocation can reuse a result; set `PERFCHECKER_FORCE=true` for a fresh execution. A reused result adds no samples.

For a shared scenario catalog:

```sh
julia --project=. scenarios.jl plan datastructures
julia --project=. scenarios.jl run datastructures
```

```@raw html
<a id="7.-Replay-the-same-experiment-in-each-interface"></a>
```

## Replay in each interface

```sh
julia --project=. replay.jl results/YOUR-CONTAINER-RUN
julia setup.jl plots
julia --project=.controller/plots export.jl results/YOUR-CONTAINER-RUN exports/containers
julia setup.jl web
julia --project=.controller/web web.jl containers
```

In Oxygen, choose the **historical** profile to expose all seven releases. To reproduce the published settings, set **Samples = 30**, **Evals = 1**, **Seconds = 0.25** and **Threads = 1**.

VS Code workspace settings:

```json
{
  "perfchecker.suite": "containers-suite.jl",
  "perfchecker.factory": "build_container_suite",
  "perfchecker.runnerProject": "."
}
```

```@raw html
<a id="REPL-and-Unicode-terminal-plots"></a>
<a id="Makie-and-exportable-figures"></a>
<a id="A-dedicated-Pluto-notebook"></a>
<a id="Web-Studio-and-VS-Code"></a>
<a id="Web-interface-(Oxygen)-and-VS-Code"></a>
<a id="To-reopen-a-completed-run-directly:"></a>
```

For terminal plots, Makie, Pluto and reopening a completed run, follow the
[interface recipes](interfaces.md). Download the notebook below for the same
DataStructures experiment.

```@raw html
<p><a href="../examples/real-packages/datastructures-notebook.jl" download>Download the DataStructures notebook (.jl)</a></p>
```

```@raw html
<a id="8.-Turn-a-candidate-regression-into-a-reproducible-report"></a>
```

## Turn a candidate into a report

1. Fix the workload, seed, Julia version and dependency environment.
2. Rerun the adjacent release pair and inspect all samples.
3. Verify the oracle still passes.
4. Choose the metric, aggregation and acceptable noise before setting a threshold.

Keep the report and environment fingerprints with an issue or proposed optimization. See [Documentation guide](../contributing/documentation.md).
