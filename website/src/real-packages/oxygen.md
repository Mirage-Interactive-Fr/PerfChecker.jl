```@raw html
<a id="Oxygen:-from-individual-routes-to-real-network-traffic"></a>
```

# Oxygen: HTTP features and network traffic

An HTTP request involves several operations: matching a route, parsing parameters, running a handler and writing a response. This example measures those in-process, then adds a client and server to measure real socket traffic.

It compares **seven HTTP features across 14 Oxygen releases (1.0.0–1.11.0)**, three application routes that process JSON events, and network measurements from 1.7.0 to 1.11.0.

## See what changed

```@raw html
<NormalizedMeasurements source="/examples/real-packages/oxygen-features/normalized-metrics-24034c4be099f2e2.json" figure="/examples/real-packages/oxygen-features/normalized-metrics-24034c4be099f2e2.svg" html="/examples/real-packages/oxygen-features/normalized-metrics-24034c4be099f2e2.html" package-name="Oxygen · plain HTTP request" />
```

Start with **Wall time** and **Allocated bytes**. In this saved campaign, the
minimum request time changes from **7.2 µs at 1.10.2 to 3.8 µs at 1.11.0**;
allocated bytes change from **4,352 to 2,512**. Inspect those points to see the
raw values. These are minima of 30 warmed samples, not medians or a CI verdict.
The resolved dependency stacks also change, so the chart does not isolate the
cause. The steps below reproduce the workload and explain the other views.

```@raw html
<a id="1.-Start-with-a-request-whose-answer-is-known"></a>
```

## 1. Check one request

Run from `examples/kitchen-sink`:

```sh
julia setup.jl oxygen
julia --project=.controller/oxygen oxygen/test.jl
```

```julia
include("oxygen/service.jl")
case = EventService.feature_case("path")
request = case.prepare()
response = case.operation(request)
@assert case.verify(request, response)
```

This calls `/features/add/19/23`. Oxygen parses the two typed path parameters, calls the handler and serializes `42`. `verify` is the correctness oracle. Each sample gets a fresh request; preparation and verification are outside the timed operation.

- `plain` — short text response; body equals `ready`.
- `path` — typed path parameters; parsed sum equals 42.
- `query` — `Oxygen.queryparams`; parsed sum equals 42.
- `json` — automatic dictionary serialization; decoded value matches.
- `html` — `Oxygen.html` helper; exact HTML body.
- `binary` — `Oxygen.binary`, 4 KiB echo; bytes equal the submission.
- `not_found` — missing-route dispatch; HTTP 404.

```@raw html
<a id="2.-Follow-recent-patches-and-locate-a-candidate-regression"></a>
```

## 2. Follow releases

```sh
julia --project=.controller/oxygen oxygen/features.jl plan
julia --project=.controller/oxygen oxygen/features.jl quick
julia --project=.controller/oxygen oxygen/features.jl history
```

98 checks: seven features on 14 releases. Each takes **30 samples after warmup, `evals=1`**. Narrow to a suspect range:

```sh
julia --project=.controller/oxygen oxygen/features.jl history 1.10.0 1.10.2
```

```julia
using PerfChecker, BenchmarkTools
include("oxygen/features-suite.jl")
plan = plan_suite(build_http_feature_suite(); profile = :historical,
    version_provider = _ -> OXYGEN_VERSIONS)
selected = filter_suite_plan(plan; features = [:binary_benchmark],
    from_version = v"1.10.1", to_version = v"1.10.2")
result = run_suite_repl(selected; reports = "results/binary-pair")
```

Only Oxygen's version is fixed explicitly. Pkg resolves HTTP, DataStructures and the rest from that release's compatibility bounds, so the resolved dependency set can change too. Check the saved manifests when investigating.

!!! note
    HTTP.jl versions 0.9, 1 and 2 are **package** versions. The HTTP/1.1 and HTTP/2 **wire protocols** are a separate matter. The loopback experiment below uses plain HTTP without TLS.

```@raw html
<a id="Separate-figures-for-every-feature"></a>
```

```@raw html
<p>Each feature has tabs for the complete history and the 1.10 patches. Every plot is an interactive PerfChecker export. Inspect the four overlaid normalized metrics, their original minima and reference values. Open the same export on its own for more space, or download its measured data.</p>
<WorkloadAtlas directory="/examples/real-packages/oxygen-features" />
```


Wall time is the entire in-process request pipeline. Allocated bytes and allocation count include parsing and response creation; they are not network bytes or resident memory. Each metric is divided by its own minimum across the history.

### The same features as TestItems

```sh
julia --project=.controller/oxygen items.jl list
julia --project=.controller/oxygen items.jl run http_plain
```

Tagged `:perf_only`, `:oxygen` and a feature tag. A whole-item measurement includes setup and assertions; the suite's operation timing excludes them.

```@raw html
<a id="3.-Add-application-work-without-mixing-package-comparisons"></a>
```

## 3. Add application work

```sh
julia --project=.controller/oxygen oxygen/measure.jl history
```

Three `/events/` routes decode the same 2,048 events, process them and encode the result: a heap sorts them, an accumulator counts categories, and a circular buffer keeps the most recent 64. Their oracles use independent reference calculations.

Compare the heap route with the plain-text case. If only the heap route changes, look at JSON handling and event processing; if both change, inspect routing and shared dependencies.

These interactive figures use PerfChecker's public HTML renderer. Each plot
has the same controls here and when opened separately; the gallery's workload
navigation belongs to this documentation.
The [serialized-view recipe](../interfaces/visualization.md#Render-a-published-serialized-view-again)
renders the published plot JSON again without changing its values or making new
measurements. That plot JSON is not a complete run bundle.

```@raw html
<WorkloadAtlas directory="/examples/real-packages/oxygen" profiles-directory="/examples/real-packages/oxygen-profiles" profile-workload="heap_request" profile-feature-prefix="heap_" profile-note="These latest-release profiles use the same 2,048-event heap request as its history. They describe Oxygen 1.11.0 only: CPU and wall-time samples, allocation stacks, a six-sector allocation pie and 31 recorded allocation sites." />
```


```@raw html
<a id="Follow-the-recent-server-releases,-patch-by-patch"></a>
<a id="Compare-socket-measurements-across-releases"></a>
```

## 4. Measure real network traffic

In-process round trip first:

```sh
julia --project=.controller/oxygen oxygen/loopback.jl
```

It starts a loopback service, warms the connection, checks responses and records 30 round trips before stopping the server in `finally`. Body sizes are application bytes; packet and wire-byte fields are unavailable here.

For real packet counters, run **inside Linux or WSL**:

```sh
julia setup-linux.jl
julia --project=.controller/linux oxygen/network.jl
julia --project=.controller/linux oxygen/network-history.jl
```

The packet experiment selects `lo`, echoes four sizes (64 B, 4 KiB, 64 KiB, 1 MiB) and verifies all 30 responses byte-for-byte at each. Three idle windows establish whether unrelated loopback traffic was visible.

```@raw html
<a id="Latency,-throughput,-bytes-and-packets-are-different-measurements"></a>
```

### Keep the measurements apart

- Round-trip latency includes client, server and scheduling in one process.
- Application throughput divides body size by elapsed time.
- Interface bytes include protocol overhead.
- On loopback a transfer appears in both transmit and receive counters — do not sum them.

```@raw html
<PluginTabs>
<PluginTabsTab label="History">
<PluginTabs>
<PluginTabsTab label="64 bytes"><InteractiveRecordedPlot source="/examples/real-packages/oxygen-network/history-64.plot.json" html="/examples/real-packages/oxygen-network/history-64.html" title="Oxygen patch history for a 64-byte network echo" kind="observation_series" /></PluginTabsTab>
<PluginTabsTab label="4 KiB"><InteractiveRecordedPlot source="/examples/real-packages/oxygen-network/history-4096.plot.json" html="/examples/real-packages/oxygen-network/history-4096.html" title="Oxygen patch history for a 4 KiB network echo" kind="observation_series" /></PluginTabsTab>
<PluginTabsTab label="64 KiB"><InteractiveRecordedPlot source="/examples/real-packages/oxygen-network/history-65536.plot.json" html="/examples/real-packages/oxygen-network/history-65536.html" title="Oxygen patch history for a 64 KiB network echo" kind="observation_series" /></PluginTabsTab>
<PluginTabsTab label="1 MiB"><InteractiveRecordedPlot source="/examples/real-packages/oxygen-network/history-1048576.plot.json" html="/examples/real-packages/oxygen-network/history-1048576.html" title="Oxygen patch history for a 1 MiB network echo" kind="observation_series" /></PluginTabsTab>
</PluginTabs>
</PluginTabsTab>
<PluginTabsTab label="Latest version">
<InteractiveRecordedPlot source="/examples/real-packages/oxygen-network/network.plot.json" html="/examples/real-packages/oxygen-network/network.html" title="Actual loopback latency, throughput, transmitted bytes and packets for four Oxygen payload sizes" kind="observation_series" />
<p><a href="../examples/real-packages/oxygen-network/latest.json" download>Download the network observations</a></p>
</PluginTabsTab>
</PluginTabs>
```


### Attribute traffic to the process tree

```sh
julia --startup-file=no --project=.controller/linux oxygen/network-isolated.jl
```

The capability probe checks namespace and nftables support first. The recorded isolated run passed 120 request oracles with Oxygen 1.10.2 and HTTP.jl 1.11.0, capturing 2,057 outgoing packets and about 69.5 MB across the whole worker lifecycle (including warmup). Those totals are not per-request latencies.

```@raw html
<p><a href="../examples/real-packages/oxygen-network/isolation.json" download>Download the isolated process-tree capture</a></p>
```


The older releases were measured only in the in-process experiment. These Linux socket measurements are a separate experiment from the Windows in-process timings.

```@raw html
<a id="5.-Find-the-expensive-call-paths"></a>
```

## 5. Find expensive call paths

These recorded profiles describe **Oxygen 1.11.0 only**. They attribute work within
that release; use the multi-version timings above for release comparisons.

```sh
julia --project=. oxygen/measure.jl profiles
julia setup.jl extras
julia --project=.controller/extras profiles.jl results/YOUR-PROFILE-RUN exports/oxygen-profiles
```

```@raw html
<p>The heap request's <strong>Latest version</strong> tab beside its History contains these recorded CPU, wall-time, allocation-stack, allocation-share and by-line diagnostics. No profile capture is available for the other two application routes or the seven small HTTP feature operations.</p>
```


Profiling adds overhead. Re-measure a proposed change with BenchmarkTools or Chairmarks. If a short request yields too few CPU samples, profile a larger input or repeat longer.

```@raw html
<a id="First-request-versus-warm-request"></a>
<a id="Allocation-activity-and-garbage-collection"></a>
<a id="Reachable-objects,-RSS-and-locks"></a>
```

## 6. Diagnose inference, startup, allocation and retention

```sh
julia setup.jl analyzers
julia --project=.controller/analyzers scenarios.jl diagnose oxygen oxygen-heap
julia --project=.controller/analyzers additional-diagnostics.jl oxygen
```

The seven reports use 2,048 events, matching the timing history. The scenario script defaults to 64 events because full allocation stacks on the larger input are much bigger.

```@raw html
<PluginTabs>
<PluginTabsTab label="JET · inference"><DiagnosticReports source="/examples/real-packages/oxygen-diagnostics/diagnosis.json" tools="jet" /></PluginTabsTab>
<PluginTabsTab label="AllocCheck · allocations"><DiagnosticReports source="/examples/real-packages/oxygen-diagnostics/diagnosis.json" tools="alloccheck" /></PluginTabsTab>
<PluginTabsTab label="SnoopCompile · compilation"><DiagnosticReports source="/examples/real-packages/oxygen-diagnostics/diagnosis.json" tools="snoopcompile" /></PluginTabsTab>
</PluginTabs>
```

The recorded **JET 0.12.1** report contains 54 findings; one is
`Base.axes1(A::AbstractVector)::Any` at `abstractarray.jl:396`. This points to a
runtime-dispatch path, not a measured slowdown. **AllocCheck 0.2.6** reports
65 potential allocation sites, including `Vector{Any}` creation reached from
`internalrequest`; expand a finding to read its recorded call path.
**SnoopCompile 3.2.9** records **1.055 s of inference** for the first complete
scenario lifecycle. All three report completion and a passing correctness
oracle on Julia 1.13.0 with one thread.

These older records omit the exact Oxygen revision and dependency manifest.
Use them to read the diagnostics; rerun with your own saved source identity
before attributing a result to a release. No corrected Oxygen implementation
or before/after diagnostic is claimed here. For a small, reproducible JET
finding and correction, see [the JET walkthrough](../native-profiling.md).

### First request, allocation activity and retained memory

```@raw html
<PluginTabs>
<PluginTabsTab label="Loading and first request">
<InteractiveRecordedPlot source="/examples/real-packages/oxygen-diagnostics/latency.plot.json" html="/examples/real-packages/oxygen-diagnostics/latency.html" title="Oxygen source loading, first-request and warm-request latency" kind="observation_series" />
</PluginTabsTab>
<PluginTabsTab label="Allocation activity and GC">
<InteractiveRecordedPlot source="/examples/real-packages/oxygen-diagnostics/gc.plot.json" html="/examples/real-packages/oxygen-diagnostics/gc.html" title="Oxygen allocation activity and garbage-collection time" kind="observation_series" />
</PluginTabsTab>
<PluginTabsTab label="Memory"><InteractiveRecordedPlot source="/examples/real-packages/oxygen-diagnostics/memory.plot.json" html="/examples/real-packages/oxygen-diagnostics/memory.html" title="Reachable HTTP objects and resident process memory" kind="observation_series" /></PluginTabsTab>
<PluginTabsTab label="Locks"><InteractiveRecordedPlot source="/examples/real-packages/oxygen-diagnostics/locks.plot.json" html="/examples/real-packages/oxygen-diagnostics/locks.html" title="Observed lock conflicts during Oxygen diagnostic requests" kind="observation_series" /></PluginTabsTab>
</PluginTabs>
```


- Source loading and first compilation can dominate a first request even when steady-state dispatch is fast.
- Bytes can be allocated without triggering a collection in a short window.
- RSS is resident memory for the whole process, including native libraries. A larger result or intentional cache is not automatically a leak.

Select a panel or series, then inspect a point for its value and unit. The
latency record separates **7.385 s loading**, **1.039 s first lifecycle** and
**4.13 ms warm lifecycle**. The five GC observations allocate about **1.60 MB
each** with **zero recorded GC time**; this does not make those allocations
free. The lock observations report zero conflicts, rather than a waiting-time
measurement.

To inspect separate, later diagnostics for Oxygen 1.10.2 and 1.11.0 in VS Code,
download the [original latency and reachable-memory reports](../interfaces/vscode-workflows.md#Try-the-recorded-Oxygen-reports).
The guide shows the actual imported files, three latency phases and all five
memory samples. Those reports retain `performance = not_compared`; they are
not the seven-report campaign above or a paired timing benchmark.

```@raw html
<DiagnosticReports source="/examples/real-packages/oxygen-diagnostics/additional.json" tools="aqua" />
```

**Aqua 0.8.16 completed with a failed quality check**. Its actual output is:

```text
1 ambiguities found.
recursive_merge(x::AbstractDict...) @ Oxygen.Core.Util
recursive_merge(x::AbstractVector...) @ Oxygen.Core.Util
Possible fix, define recursive_merge()
```

This is a package-quality finding. The displayed suggestion is Aqua's output,
not an applied change or a benchmark result.

```@raw html
<InteractiveRecordedPlot source="/examples/real-packages/oxygen-diagnostics/heap-types.plot.json" html="/examples/real-packages/oxygen-diagnostics/heap-types.html" title="Shallow GC-object sizes in the Oxygen diagnostic worker" kind="observation_series" />
```

Inspect an object category for its **shallow bytes**. These totals describe the
GC-managed objects present in the diagnostic worker; they do not predict how
much memory would be reclaimed by deleting a reference.


```@raw html
<a id="Native-libraries-and-memory-tools"></a>
```

### Native libraries

On Linux/WSL:

```sh
julia --startup-file=no --project=.controller/linux setup-native.jl
julia --startup-file=no --project=.controller/linux native-run.jl oxygen
```

```@raw html
<DiagnosticReports source="/examples/real-packages/oxygen-native/summary.json" />
<InteractiveRecordedPlot source="/examples/real-packages/oxygen-native/massif-1.plot.json" html="/examples/real-packages/oxygen-native/massif-1.html" title="Oxygen native heap, allocator overhead and tracked stacks recorded by Massif" kind="observation_series" />
```


The recorded run completed Callgrind, Massif and heaptrack with a passing oracle. Memcheck and Cachegrind hit their time limit during Julia compilation; their reports are incomplete. Massif's axis counts instrumented instructions, not seconds. No GPU, remote-host or hardware-counter measurements were run.

```@raw html
<a id="7.-Preserve-experiments-and-reuse-the-same-evidence"></a>
```

## 7. Reuse the same evidence

```sh
julia --project=.controller/oxygen scenarios.jl run oxygen
julia --project=.controller/extras drwatson.jl run oxygen
julia --project=. replay.jl results/YOUR-OXYGEN-RUN
julia setup.jl plots
julia --project=.controller/plots export.jl results/YOUR-OXYGEN-RUN exports/oxygen
julia setup.jl web
julia --project=.controller/web web.jl oxygen-features
```

The web interface runs on port 8873 by default; the loopback experiment uses a separate port and router. Choose the **historical** profile for all 14 releases, then set **Samples = 30**, **Evals = 1**, **Seconds = 0.25**, **Threads = 1**. DrWatson caches under the stored parameters; set `PERFCHECKER_FORCE=true` to measure again.


```@raw html
<a id="Oxygen-Web-Studio-and-VS-Code"></a>
```

VS Code settings for `examples/kitchen-sink`:

```json
{
  "perfchecker.suite": "oxygen/features-suite.jl",
  "perfchecker.factory": "build_http_feature_suite",
  "perfchecker.runnerProject": ".controller/oxygen"
}
```

```@raw html
<a id="REPL-and-Unicode-plots"></a>
<a id="Makie-and-standalone-HTML"></a>
<a id="A-dedicated-Pluto-notebook"></a>
<a id="Web-interface-(Oxygen)-and-VS-Code"></a>
<a id="Or-reopen-a-completed-report:"></a>
```

### Open the complete Pluto notebook

Download the notebook below, then choose **Open a notebook** in Pluto's browser UI. Its embedded workloads, oracles and saved JSON need no checkout. First opening requires Julia **1.12+**, Git and internet; the preparation cell installs Core **1.1.0** and Makie/Pluto **1.0.1** in a separate runtime. Inspect the saved histories, select the experiment, collector, workload and targets, then choose **Launch selected checks** to start workers. See the [Pluto guide](../interfaces/pluto.md) for **Refresh status**, **Cancel active job** and **Save completed reports**.

To share an improvement, include the before/after results and the change that produced them. See [Contributing](../contributing/index.md).

```@raw html
<p><a href="../examples/real-packages/oxygen-notebook.jl" download>Download the Oxygen notebook (.jl)</a></p>
```
