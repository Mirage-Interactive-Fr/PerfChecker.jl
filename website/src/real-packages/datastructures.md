```@raw html
<a id="DataStructures:-a-complete-container-investigation"></a>
```

# DataStructures: 35 containers

Construction and use of a container can cost very differently. A deque may be cheap to drain and expensive to build.

This example measures **35 containers** across **DataStructures 0.19.0–0.19.6**, then follows five workloads back to 0.11.0.

## Read one measured change

```@raw html
<NormalizedMeasurements source="/examples/real-packages/containers/normalized-metrics-2c8d15cd8058155f.json" figure="/examples/real-packages/containers/normalized-metrics-2c8d15cd8058155f.svg" html="/examples/real-packages/containers/normalized-metrics-2c8d15cd8058155f.html" package-name="DataStructures · SortedSet lookup" />
```

Select **Wall time** and inspect **0.19.2** and **0.19.3**: their minimum
observations are **3.7 µs** and **7.4 µs** for the same lookup workload.
Then enable allocation metrics to see whether they move with time. Each curve
uses its own minimum as 1; the tooltip retains the original unit. These are
minima of 30 warmed samples, so inspect the recorded samples and remeasure
the pair before calling the difference a regression.

```@raw html
<a id="1.-Open-the-example-and-check-one-answer"></a>
```

## Open the example

Run from `examples/kitchen-sink`. Prepare the example's controller once, then check its answers:

```sh
julia setup.jl core
julia --project=. containers.jl check
```

`check` covers empty, singleton, 32-element and 512-element inputs for every operation, comparing against ordinary arrays, dictionaries or explicit answers.

`setup.jl core` installs the example dependencies and connects the controller to the local PerfChecker checkout. `check` verifies answers without timing.

The example's own test items are a separate optional check: `julia --project=. test/runtests.jl` exercises the small correctness tests and deliberately skips items tagged `:perf_only`. These are the kitchen-sink example's tests, not the upstream DataStructures package test suite. The timed container cases use their declared array/dictionary oracles rather than importing upstream tests or their test dependencies into every release worker.

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
<p>Choose an operation, then History or Latest version. History compares all seven recorded releases with four normalized curves. Latest version shows the separate BenchmarkTools and Chairmarks minima for 0.19.6; these single-release sessions do not establish an improvement.</p>
<WorkloadAtlas directory="/examples/real-packages/containers" containers latest-directory="/examples/real-packages/containers-collectors" />
```


```@raw html
<a id="3.-Inspect-every-container-separately"></a>
<a id="Four-measurements-on-one-plot"></a>
<a id="Explore-the-separate-curves-and-distributions"></a>
```

Each container has a tab for construction and a tab for use. The overlay divides each release's minimum sample by that metric's minimum across releases; `1` is the lowest observed value. A zero GC minimum means a short sample had no collection, not that collection is free.

Every operation's **History** tab uses one interactive four-metric normalized overlay, covering 0.19.0–0.19.6, including AVLTree construction and lookup.
Select a plotted observation to inspect its exact value and version. Open the same export on its
own for more space, or download its JSON to inspect the recorded observations.


Chairmarks measures the same operations separately:

```sh
julia --project=. containers.jl chairmarks Deque_drain_chairmark
```

Keep the two collectors' samples separate; they sample differently. Their latest-release observations appear beside each operation's history. No per-container CPU, wall-time or allocation-stack capture is present in this campaign.


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

The figures below are interactive PerfChecker exports of the recorded measurements.
The gallery embeds the public HTML export with its own controls. Its workload
navigation belongs to this documentation. To open the same plot outside the site or render its saved
JSON again, follow [Render a published serialized view again](../interfaces/visualization.md#Render-a-published-serialized-view-again).
Rendering the JSON preserves its recorded values; it does not recreate a complete
run bundle or perform a new benchmark.

### Where the history stops

`compatibility.jl DataStructures` checks old releases in separate processes. **0.9.0 and 0.10.0 fail to load on Julia 1.13** because they define methods for the removed `Base.start` API, so the history starts at 0.11.0. Testing earlier versions needs an older Julia runtime.

```@raw html
<WorkloadAtlas directory="/examples/real-packages/datastructures" profiles-directory="/examples/real-packages/datastructures-profiles" :profile-links='{"heap_2048":{"featurePrefix":"heap_32768_","note":"The saved CPU, wall-time and allocation profiles use 32,768 events, while this timing history uses 2,048. Both construct and drain a heap. The heap allocation profile attributes its weight to one source line."},"counter_2048":{"featurePrefix":"counter_32768_","note":"This separate Linux allocation capture uses 32,768 events, Julia 1.13.1 and DataStructures 0.19.6; the timing history uses 2,048 events. Its allocation stacks, pie and source lines describe the larger counter operation, not the timing differences between releases. No CPU or wall-time capture was added."}}' />
```


The vector implementation mostly exercises Base Julia, so it acts as a control. Changes in its timings across tags are likely machine noise, not a DataStructures change.

```@raw html
<a id="5.-Explain-the-cost-with-profiles-and-diagnostics"></a>
<a id="CPU,-wall-time-and-allocation-stacks"></a>
```

## Diagnose inference and startup

The **Latest version** tabs beside the heap and counter histories contain the saved diagnostics for **DataStructures 0.19.6**. Their profiles use the explicitly larger 32,768-event fixtures. The counter's native allocation capture retains 11 events and 2,208 sampled bytes; separately measured operation totals are 2,352 bytes and 11 allocations. Its pie uses the sampled weights without rescaling them to the independent total. No single-point version trajectory, version heatmap or version totals are presented as a comparison.

```sh
julia --project=. measure.jl profiles
julia setup.jl analyzers
julia --project=.controller/analyzers scenarios.jl diagnose datastructures events-heap
```

::: details Reproduce the separate Counter allocation profile

From `examples/kitchen-sink`, after `julia setup.jl core`, start Julia with
`julia --project=.` and select only the larger counter feature:

```julia
using PerfChecker
include("suite.jl")
plan = plan_suite(build_suite(); profile=:historical,
    version_provider=_ -> KITCHEN_VERSIONS)
selected = filter_suite_plan(plan; features=[:counter_32768_profile_alloc],
    from_version=v"0.19.6", to_version=v"0.19.6")
print_suite_plan(selected)
result = run_suite_repl(selected; reports="results/counter-allocation",
    overrides=Dict{Symbol,Any}(:threads=>1, :sample_rate=>1.0,
        :profile_repetitions=>1))
@assert suite_passed(result)
```

This collects one warmed allocation profile with fresh state and the counter
oracle, plus separate whole-operation byte and allocation totals. The saved
Linux recording used Julia 1.13.1 and a 120-second scenario-worker budget;
`run_suite_repl` does not expose that scenario-worker budget as a keyword.
The command above deliberately launches a new profile; opening the saved
Latest version figures does not. Its sampling settings match the capture,
but a new runtime or dependency resolution can produce different stacks.

:::

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
<PluginTabs>
<PluginTabsTab label="JET · inference"><DiagnosticReports source="/examples/real-packages/datastructures-diagnostics/diagnosis.json" tools="jet" /></PluginTabsTab>
<PluginTabsTab label="AllocCheck · allocations"><DiagnosticReports source="/examples/real-packages/datastructures-diagnostics/diagnosis.json" tools="alloccheck" /></PluginTabsTab>
<PluginTabsTab label="SnoopCompile · compilation"><DiagnosticReports source="/examples/real-packages/datastructures-diagnostics/diagnosis.json" tools="snoopcompile" /></PluginTabsTab>
</PluginTabs>
```

For this specialization, **JET 0.12.1 reports no findings**, while
**AllocCheck 0.2.6 reports six potential allocation sites**. Neither result
measures execution speed or proves that every possible input is allocation
free. **SnoopCompile 3.2.9 records 4.71 µs of inference** in this diagnostic
lifecycle. The reports completed with passing correctness oracles on Julia
1.13.0 with one thread; these older records do not retain the exact
DataStructures source revision or resolved manifest.

```@raw html
<PluginTabs>
<PluginTabsTab label="Loading and first operation">
<InteractiveRecordedPlot source="/examples/real-packages/datastructures-diagnostics/latency.plot.json" html="/examples/real-packages/datastructures-diagnostics/latency.html" title="Loading, first-operation and warm-operation latency for the DataStructures heap" kind="observation_series" />
</PluginTabsTab>
<PluginTabsTab label="Allocation activity and GC">
<InteractiveRecordedPlot source="/examples/real-packages/datastructures-diagnostics/gc.plot.json" html="/examples/real-packages/datastructures-diagnostics/gc.html" title="Allocated bytes and garbage-collection time for five heap operations" kind="observation_series" />
</PluginTabsTab>
<PluginTabsTab label="Memory"><InteractiveRecordedPlot source="/examples/real-packages/datastructures-diagnostics/memory.plot.json" html="/examples/real-packages/datastructures-diagnostics/memory.html" title="Reachable state and result sizes beside resident process memory" kind="observation_series" /></PluginTabsTab>
<PluginTabsTab label="Locks"><InteractiveRecordedPlot source="/examples/real-packages/datastructures-diagnostics/locks.plot.json" html="/examples/real-packages/datastructures-diagnostics/locks.html" title="Observed lock-conflict counts for five heap operations" kind="observation_series" /></PluginTabsTab>
</PluginTabs>
<p><a href="../examples/real-packages/datastructures-diagnostics/diagnosis.json" download>Download the complete diagnostic records</a></p>
```


Inspect a point to distinguish the recorded **649 ms loading**, **171 ms first
lifecycle** and **201 µs warm lifecycle**. The lock diagnostic counts conflicts;
this example runs on one thread. RSS is memory resident for the whole process,
including Julia and native libraries. Growth can reflect intended output or a
cache, not necessarily a leak.

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
<InteractiveRecordedPlot source="/examples/real-packages/datastructures-native/massif-1.plot.json" html="/examples/real-packages/datastructures-native/massif-1.html" title="Massif native heap, allocator overhead and tracked stacks through one Julia process" kind="observation_series" />
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
<DiagnosticReports source="/examples/real-packages/datastructures-diagnostics/additional.json" tools="aqua" />
<InteractiveRecordedPlot source="/examples/real-packages/datastructures-diagnostics/heap-types.plot.json" html="/examples/real-packages/datastructures-diagnostics/heap-types.html" title="Shallow sizes of GC-managed object categories in the DataStructures diagnostic worker" kind="observation_series" />
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

### Open the complete Pluto notebook

Download the notebook below, then choose **Open a notebook** in Pluto's browser UI. Its embedded workloads, oracles and saved JSON need no checkout. First opening requires Julia **1.12+**, Git and internet; the preparation cell installs Core **1.1.0** and Makie/Pluto **1.0.1** in a separate runtime. Inspect the saved histories, select the experiment, collector, workload and targets, then choose **Launch selected checks** to start workers. See the [Pluto guide](../interfaces/pluto.md) for **Refresh status**, **Cancel active job** and **Save completed reports**.

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

Keep the report and environment fingerprints with an issue or proposed optimization. See [Contributing](../contributing/index.md).
