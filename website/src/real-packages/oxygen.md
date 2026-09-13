# Oxygen: from individual routes to real network traffic

An HTTP request involves several operations: matching a route, parsing its
parameters, running a handler and writing a response. We can measure these
operations inside Oxygen first, then add a client and server to measure the
cost of sending the request over a socket.

The examples below compare seven HTTP features across **14 Oxygen releases,
from 1.0.0 to 1.11.0**. They also cover three routes that process JSON events,
network measurements from **1.7.0 to 1.11.0**, and profiles of the event handler.
The scripts and the downloadable notebook use the data shown in the figures.

## 1. Start with a request whose answer is known

Get the checkout described in [the example setup](index.md). All commands below
run from `examples/kitchen-sink`:

```sh
julia setup.jl oxygen
julia --project=.controller/oxygen oxygen/test.jl
```

Each worker loads the selected Oxygen version in a separate process. Its router
and dependencies are therefore independent of the Web Studio used to launch it.

```julia
include("oxygen/service.jl")
case = EventService.feature_case("path")
request = case.prepare()
response = case.operation(request)
@assert case.verify(request, response)
```

This request calls `/features/add/19/23`. Oxygen parses the two typed path
parameters, calls the handler and serializes the answer. `verify` checks for
HTTP 200 and the value 42. This check is the experiment's *correctness oracle*.
Each timing sample gets a fresh request;
preparation and verification are outside the timed operation.

| Case | Measured feature | Independent oracle |
| --- | --- | --- |
| `plain` | Short text response | Body equals `ready` |
| `path` | Typed path parameters | Parsed sum equals 42 |
| `query` | `Oxygen.queryparams` | Parsed sum equals 42 |
| `json` | Automatic dictionary serialization | Decoded boolean and 64 integers match |
| `html` | `Oxygen.html` response helper | Exact HTML body |
| `binary` | `Oxygen.binary`, 4 KiB echo | Response equals the submitted bytes |
| `not_found` | Missing-route dispatch | HTTP 404 |

The binary case echoes a fixed body. To investigate file uploads, streaming or
WebSockets, add a case that performs that operation and checks the response.

## 2. Follow recent patches and locate a candidate regression

```sh
julia --project=.controller/oxygen oxygen/features.jl plan
julia --project=.controller/oxygen oxygen/features.jl quick
julia --project=.controller/oxygen oxygen/features.jl history
```

The feature matrix contains 98 checks: seven features on 14 releases.
It selects 1.0.0 through 1.9.0, then 1.10.0, 1.10.1, 1.10.2 and 1.11.0.
Every check takes **30 samples after warmup, with `evals=1`**. The historical
adapter uses public macros on old releases and isolated routers where supported.

If the plot shows a jump between two releases, rerun that smaller range:

```sh
julia --project=.controller/oxygen oxygen/features.jl history 1.10.0 1.10.2
```

For one specific feature:

```julia
using PerfChecker, BenchmarkTools
include("oxygen/features-suite.jl")
plan = plan_suite(build_http_feature_suite(); profile=:historical,
    version_provider=_ -> OXYGEN_VERSIONS)
selected = filter_suite_plan(plan; features=[:binary_benchmark],
    from_version=v"1.10.1", to_version=v"1.10.2")
result = run_suite_repl(selected; reports="results/binary-pair")
```

Only Oxygen's version is selected explicitly. Pkg resolves HTTP, DataStructures
and the other dependencies using that release's compatibility bounds. Check the
saved manifests when investigating a change: a new Oxygen release may also use
a different dependency version.

The resolved dependencies include HTTP.jl 0.9, 1 and 2. These are package
versions; the HTTP/2 network protocol is a separate matter. The loopback
experiment below uses plain HTTP without testing TLS or protocol negotiation.

### Separate figures for every feature

Wall time measures the entire in-process request pipeline. GC time is the part
attributed to Julia's garbage collector. Allocated bytes and allocation count
measure allocation activity, including parsing and response creation. They do
not measure network bytes, packets or resident memory.

Each metric is divided by its own minimum across the complete release history.
The smaller patch-window figures retain that same reference and show every
neighboring patch clearly. Each overview point corresponds to a selected release.
An all-zero GC metric appears at one by convention; other ratios against zero
remain unavailable. Inspect raw values before interpreting a normalized curve.

```@raw html
<p>Each feature has tabs for the complete history and the 1.10 patches. Hover or focus a point for its value; use the metric buttons to show or hide curves.</p>
<WorkloadAtlas directory="/examples/real-packages/oxygen-features" />
```

Each caption points to the largest increase in minimum time between adjacent
releases. Use it to select a pair to rerun, then inspect the sample distributions
below to see how much the timings vary.

The separate units, distributions and version deltas remain available:

```@raw html
<PackageGallery package-name="Oxygen feature catalogue" directory="/examples/real-packages/oxygen-features" />
```

### The same features as TestItems

```sh
julia --project=.controller/oxygen items.jl list
julia --project=.controller/oxygen items.jl run http_plain
```

`test/http-items.jl` exposes each feature with `:perf_only`, `:oxygen` and a
feature-specific tag. Select these items individually in VS Code or through
PerfChecker. Ordinary tests filter out `:perf_only`. A whole-item measurement
includes setup and assertions; the suite's narrower operation timing excludes them.

## 3. Add application work without mixing package comparisons

The three `/events/` routes decode the same 2,048 events, process them and encode
the result. A heap sorts events, an accumulator counts categories, and a circular
buffer retains the most recent 64 events. Their oracles use independent reference
calculations, not a second call to the measured implementation.

```sh
julia --project=.controller/oxygen oxygen/measure.jl history
```

This matrix follows the same 14 Oxygen releases with the three BenchmarkTools cases
and a separate Chairmarks heap case. As in the feature comparison, Pkg resolves
DataStructures from Oxygen's compatibility bounds. The gallery lists the
dependencies for each release.

```@raw html
<NormalizedMeasurements source="/examples/real-packages/oxygen/normalized.json" figure="/examples/real-packages/oxygen/normalized.svg" package-name="Oxygen event service" />
<PackageGallery package-name="Oxygen application history" directory="/examples/real-packages/oxygen" />
<WorkloadAtlas directory="/examples/real-packages/oxygen" />
```

Compare the heap route with the plain-text case above. If only the heap route
changes, JSON handling and event processing are useful places to look next.
If both change, inspect the routing path and shared dependencies as well.

## 4. Measure real network traffic

First, the portable HTTP round-trip example:

```sh
julia --project=.controller/oxygen oxygen/loopback.jl
```

It starts a loopback service, warms the connection, checks responses and records
30 round trips before stopping the server in `finally`. Its body sizes are
application bytes. Packet and wire-byte fields are unavailable in this example;
collecting them requires the operating-system counters used below.

For actual packet counters, run the following **inside Linux or WSL**, from the
same example directory. A separate environment avoids reusing a Windows manifest:

```sh
julia setup-linux.jl
julia --project=.controller/linux oxygen/network.jl
julia --project=.controller/linux oxygen/network-history.jl
```

The packet experiment selects the `lo` interface explicitly. It echoes four
request sizes—64 bytes, 4 KiB, 64 KiB and 1 MiB—and verifies all 30 responses at
each size byte-for-byte. `PerfChecker.measure_network_interface` captures the
actual interface deltas around each request. Three idle windows establish
whether unrelated loopback traffic was observed before the measurements.

### Latency, throughput, bytes and packets are different measurements

Round-trip latency includes the client, server and scheduling in one Julia
process. Application throughput divides the two body sizes by that elapsed time.
Interface bytes include protocol overhead. Packet counts describe transfers
observed by the operating system; they are not inferred from payload size.

On loopback, a transfer appears in both transmit and receive counters. Summing
those counters would double-count traffic. The figures therefore plot transmit
bytes and transmit packets separately from application throughput. Dots show all
30 observations; the line follows their median.

```@raw html
<DocMedia src="/examples/real-packages/oxygen-network/network.svg" alt="Actual loopback latency, throughput, transmitted bytes and packets for four Oxygen payload sizes" />
```

The download includes the idle measurements, response checks and tool versions.
Other processes can send traffic over the host's loopback interface during a
sample. The namespace example below isolates that traffic. To study a remote
server or concurrent clients, change the workload to reproduce those conditions.

```@raw html
<p><a href="../examples/real-packages/oxygen-network/latest.json" download>Download the network observations</a></p>
```

### Follow the recent server releases, patch by patch

To attribute traffic to the experiment's process tree, use a dedicated network
namespace instead of the host's shared loopback interface:

```sh
julia --startup-file=no --project=.controller/linux oxygen/network-isolated.jl
```

The capability probe checks namespace and nftables support before launching.
The recorded isolated run passed **120 request oracles** with Oxygen 1.10.2 and
HTTP.jl 1.11.0. It captured 2,057 outgoing packets and about 69.5 MB sent across
the complete worker lifecycle, including warmup. These totals are not per-request
latencies; the request-level observations remain in `requests.json`.

```@raw html
<p><a href="../examples/real-packages/oxygen-network/isolation.json" download>Download the isolated process-tree capture</a></p>
```

### Compare socket measurements across releases

The server history covers every release from 1.7.0 through 1.11.0, including
1.7.1–1.7.5 and 1.10.1–1.10.2. Each tab shows one payload size across these
releases. The older releases were measured only in the in-process experiment.

```@raw html
<PluginTabs>
<PluginTabsTab label="64 bytes"><DocMedia src="/examples/real-packages/oxygen-network/history-64.svg" alt="Oxygen patch history for a 64-byte network echo" /></PluginTabsTab>
<PluginTabsTab label="4 KiB"><DocMedia src="/examples/real-packages/oxygen-network/history-4096.svg" alt="Oxygen patch history for a 4 KiB network echo" /></PluginTabsTab>
<PluginTabsTab label="64 KiB"><DocMedia src="/examples/real-packages/oxygen-network/history-65536.svg" alt="Oxygen patch history for a 64 KiB network echo" /></PluginTabsTab>
<PluginTabsTab label="1 MiB"><DocMedia src="/examples/real-packages/oxygen-network/history-1048576.svg" alt="Oxygen patch history for a 1 MiB network echo" /></PluginTabsTab>
</PluginTabs>
```

Replay or regenerate the figures from the saved data:

```sh
julia setup.jl plots
julia --project=.controller/plots network-export.jl results/YOUR-NETWORK-HISTORY exports/network
```

The exporter reads the saved counters. These Linux socket measurements belong
to a separate experiment from the Windows in-process timings above.

## 5. Find the expensive call paths

```sh
julia --project=. oxygen/measure.jl profiles
julia setup.jl extras
julia --project=.controller/extras profiles.jl results/YOUR-PROFILE-RUN exports/oxygen-profiles
```

CPU profiles sample execution; wall-time profiles can also expose waiting.
Allocation profiles attribute sampled objects or bytes to call paths. Flame-graph
width represents the selected weight and height represents nesting; the picture
is not a timeline. Exported folded stacks, Speedscope and pprof retain the recorded
scope and can be opened without rerunning the request.

```@raw html
<RecordedFigures directory="/examples/real-packages/oxygen-profiles" />
```

Profiling adds overhead, so measure a proposed change again with BenchmarkTools
or Chairmarks. If a short request produces too few CPU samples, profile a larger
input or repeat the operation for longer.

## 6. Diagnose inference, startup, allocation and retention

```sh
julia setup.jl analyzers
julia --project=.controller/analyzers scenarios.jl diagnose oxygen oxygen-heap
julia --project=.controller/analyzers additional-diagnostics.jl oxygen
```

The seven reports below use 2,048 events, matching the application timing
history. The scenario script defaults to 64 events because collecting full
allocation stacks for the larger input produces a much larger report. The
additional Aqua and heap-snapshot results also use 64 events.

JET analyzes the types inferred for the handler and reports possible errors or
runtime dispatch. AllocCheck identifies allocation sites in compiled code.
SnoopCompile records inference work, which can help explain a slow first request.
Expand a report to inspect the affected methods and source locations.

```@raw html
<DiagnosticReports source="/examples/real-packages/oxygen-diagnostics/diagnosis.json" />
```

### First request versus warm request

Source loading and initial compilation can dominate a first request even when
steady-state dispatch is fast. The latency figure separates loading, the first
operation and a warm operation on a logarithmic scale.

```@raw html
<DocMedia src="/examples/real-packages/oxygen-diagnostics/latency.svg" alt="Oxygen source loading, first-request and warm-request latency" />
```

### Allocation activity and garbage collection

The GC diagnostic observes five operations with process-wide counters. Bytes
can be allocated without triggering a collection in that short window. These
five diagnostic observations are distinct from the 30 timing samples per release.

```@raw html
<DocMedia src="/examples/real-packages/oxygen-diagnostics/gc.svg" alt="Oxygen allocation activity and garbage-collection time" />
```

### Reachable objects, RSS and locks

Reachable-object size measures the retained request and response graph. RSS
measures resident memory for the entire Julia process, including native libraries.
A larger result or an intentional cache is not automatically a leak. A redacted
heap snapshot can help inspect retention; the large snapshot stays outside Git.

```@raw html
<PluginTabs>
<PluginTabsTab label="Memory"><DocMedia src="/examples/real-packages/oxygen-diagnostics/memory.svg" alt="Reachable HTTP objects and resident process memory" /></PluginTabsTab>
<PluginTabsTab label="Locks"><DocMedia src="/examples/real-packages/oxygen-diagnostics/locks.svg" alt="Observed lock conflicts during Oxygen diagnostic requests" /></PluginTabsTab>
</PluginTabs>
```

The Locks tab reports conflict counts. To measure contention, extend this
sequential example with concurrent requests and record waiting time too.

Aqua checks package quality. Here it reported that a zero-argument call to
`recursive_merge` is ambiguous between the dictionary and vector overloads.
The routes above do not make that call.

The heap figure groups GC-managed objects by their shallow size: the size of
each object itself, excluding the objects it refers to. Native allocations are
outside this snapshot. The download contains the category totals; the full
snapshot is kept with the local results because of its size.

```@raw html
<DiagnosticReports source="/examples/real-packages/oxygen-diagnostics/additional.json" />
<DocMedia src="/examples/real-packages/oxygen-diagnostics/heap-types.svg" alt="Shallow GC-object sizes in the Oxygen diagnostic worker" />
```

### Native libraries and memory tools

On Linux/WSL:

```sh
julia --startup-file=no --project=.controller/linux setup-native.jl
julia --project=.controller/linux native-run.jl oxygen
```

The script prepares generic-target Julia caches outside instrumentation and uses
the runtime suppressions recommended in the [Julia Valgrind guide](https://docs.julialang.org/en/v1.10/devdocs/valgrind/).
Callgrind counts instrumented instructions/calls, Cachegrind models cache activity,
and Massif samples native heap usage. Memcheck examines memory accesses/leaks;
heaptrack follows native allocations. The Callgrind helper starts collection after
warmup and includes three complete lifecycles, including preparation and the oracle.
Other profiles include startup and JIT work. Their costs are not native wall-time benchmarks.

The reports list the tool version, exit status and response-check result.
GPU, remote-host and hardware-counter measurements were not run for this example.

```@raw html
<DiagnosticReports source="/examples/real-packages/oxygen-native/summary.json" />
<DocMedia src="/examples/real-packages/oxygen-native/massif-1.svg" alt="Oxygen native heap, allocator overhead and tracked stacks recorded by Massif" />
```

The recorded native run completed Callgrind, Massif and heaptrack with a passing
oracle. Memcheck and Cachegrind reached their time limit during Julia compilation;
their reports are incomplete and cannot be used to assess memory errors.
The Massif axis counts instrumented instructions rather than wall-clock seconds.

## 7. Preserve experiments and reuse the same evidence

```sh
julia --project=.controller/oxygen scenarios.jl run oxygen
julia --project=.controller/extras drwatson.jl run oxygen
```

The scenario catalog stores the input parameters and response checks. DrWatson
caches a result under those parameters, so repeating the command can return the
previous run. Set `PERFCHECKER_FORCE=true` to collect new measurements.

Use `corpus.jl` to save inputs generated by the property tests. Replaying that
corpus gives each package version the same cases to process and verify.

### REPL and Unicode plots

```sh
julia --project=. replay.jl results/YOUR-OXYGEN-RUN
```

```julia
using PerfChecker, UnicodePlots
include("replay.jl")
terminal_plot(saved_plot("downloaded-plot.json"))
```

Every primary figure on this page links to its Unicode rendering or numerical
projection. Network figures can be regenerated from their recorded counters.

### Makie and standalone HTML

```sh
julia setup.jl plots
julia --project=.controller/plots export.jl results/YOUR-OXYGEN-RUN exports/oxygen
```

With WGLMakie loaded, `performance_plot_html(model)` provides the corresponding
interactive view. SVG, JSON and terminal exports all consume the same observations.
They do not start another service or measurement.

### A dedicated Pluto notebook

```@raw html
<p><a href="../examples/real-packages/oxygen-notebook.jl" download>Download the Oxygen notebook (.jl)</a></p>
```

```sh
julia +1.12 setup.jl pluto
julia +1.12 --project=.controller/pluto -e 'using Pluto; Pluto.run(notebook="oxygen-notebook.jl", threads=1)'
```

Select a feature, check a request, inspect its release history, compare the Makie
and Unicode views, and read the network counters. The notebook uses the published
data included in the checkout. It does not start a historical campaign when opened.
Its renderer environment can use a different Oxygen version from the recorded workers.

### Oxygen Web Studio and VS Code

```sh
julia setup.jl web
julia --project=.controller/web web.jl oxygen-features
# Or reopen a completed report:
julia --project=.controller/web web.jl results/YOUR-OXYGEN-RUN
```

The Web Studio runs on port 8873 by default; the loopback experiment uses a
separate port and router. Select the feature and version range before launching.
Choose the **historical** profile to expose the 14 releases, then set **Samples =
30**, **Evals = 1**, **Seconds = 0.25** and **Threads = 1** to reproduce the
published timing settings.
In VS Code, select individual HTTP TestItems or `oxygen/features-suite.jl` with
its `build_http_feature_suite` factory. The interfaces read the same result bundle.

With VS Code opened at `examples/kitchen-sink`, use the prepared Oxygen controller:

```json
{
  "perfchecker.suite": "oxygen/features-suite.jl",
  "perfchecker.factory": "build_http_feature_suite",
  "perfchecker.runnerProject": ".controller/oxygen"
}
```

Then open **PerfChecker: Discover existing test items** or the visual suite editor.

```sh
julia +1.12 --project=.controller/pluto controller-notebook.jl oxygen-features
```

This generates a controller notebook with explicit launch controls. For CI,
keep JSON/JUnit reports with the input, runtime and environment fingerprints.
Documenter and DocumenterVitepress render saved evidence without requiring a
fresh network test during a documentation build.

To share an improvement found with this example, include the before/after
results and the change that produced them. See [contributing an experiment](contributing.md).
