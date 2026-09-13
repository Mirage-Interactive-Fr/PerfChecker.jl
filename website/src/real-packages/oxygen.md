# Oxygen: from individual routes to real network traffic

This guide follows one HTTP experiment from a verified request through release
comparisons, network counters, profiling and replay in each interface. Seven
HTTP features are measured independently. An application example then adds JSON
event processing with a heap, a counter and a circular buffer.

The routing history covers **14 Oxygen releases from 1.0.0 to 1.11.0**:
one point per older minor series, then every patch in 1.10 and 1.11.
The socket experiment follows the recent server
API from **1.7.0 to 1.11.0**, including the intermediate patches. These are two
separate measurement boundaries: an in-process request cannot measure network traffic.

## 1. Start with a request whose answer is known

Get the checkout described in [the example setup](index.md). All commands below
run from `examples/kitchen-sink`:

```sh
julia setup.jl oxygen
julia --project=.controller/oxygen oxygen/test.jl
```

The service lives in its own Oxygen router. Target workers also run in separate
processes, so measuring an old Oxygen version cannot modify the Web Studio's
router or dependency environment.

```julia
include("oxygen/service.jl")
case = EventService.feature_case("path")
request = case.prepare()
response = case.operation(request)
@assert case.verify(request, response)
```

This request calls `/features/add/19/23`. Oxygen parses the two typed path
parameters, calls the handler and serializes the answer. The oracle independently
expects HTTP 200 and the value 42. Each timing sample gets a fresh request;
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

These are controlled feature baselines, not an exhaustive test of Oxygen's API.
For example, a binary echo does not test file uploads, streaming or WebSockets.
Add such a lifecycle when it matches your application, retaining an independent oracle.

## 2. Follow recent patches and locate a candidate regression

```sh
julia --project=.controller/oxygen oxygen/features.jl plan
julia --project=.controller/oxygen oxygen/features.jl quick
julia --project=.controller/oxygen oxygen/features.jl history
```

The feature matrix contains 98 checks: seven features on 14 releases.
It selects 1.0.0 through 1.9.0, then 1.10.0, 1.10.1, 1.10.2 and 1.11.0.
There is no registered 1.11.1 in this recorded selection.
Every check takes **30 samples after warmup, with `evals=1`**. The historical
adapter uses public macros on old releases and isolated routers where supported.
It does not rewrite Oxygen internals or alter old source code.

A broad history locates a boundary; a small repeatable comparison investigates it:

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

Only Oxygen is explicitly varied. Julia resolves HTTP, DataStructures and other
dependencies from Oxygen's declared compatibility bounds. The recorded manifests
identify the resulting application stack. A dependency transition can explain a
change, but a coincident version boundary does not prove which commit caused it.

The historical stack crosses HTTP 0.9, HTTP 1 and HTTP 2. Here, **HTTP 2 means
version 2 of HTTP.jl**, not proof that a request used the HTTP/2 wire protocol.
The loopback benchmark below does not claim protocol negotiation or TLS coverage.

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
<WorkloadAtlas directory="/examples/real-packages/oxygen-features" />
```

A caption identifies the largest adjacent increase in recorded time minima as
a candidate for investigation. Repeat that pair and inspect the distributions
before declaring a regression. A one-machine history is evidence to investigate,
not a general ranking of package releases.

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
and a separate Chairmarks heap case. It does **not** pair chosen DataStructures
versions with Oxygen. The gallery lists the dependencies actually resolved for
each target release.

```@raw html
<NormalizedMeasurements source="/examples/real-packages/oxygen/normalized.json" figure="/examples/real-packages/oxygen/normalized.svg" package-name="Oxygen event service" />
<PackageGallery package-name="Oxygen application history" directory="/examples/real-packages/oxygen" />
<WorkloadAtlas directory="/examples/real-packages/oxygen" />
```

Compare the three routes independently. A faster heap route with unchanged
plain-text routing may point toward JSON or application processing; it does not
by itself establish that Oxygen's router improved. Compare matching collector
identities and parameters before interpreting two records together.

## 4. Measure real network traffic

First, the portable HTTP round-trip example:

```sh
julia --project=.controller/oxygen oxygen/loopback.jl
```

It starts a loopback service, warms the connection, checks responses and records
30 round trips before stopping the server in `finally`. Its body sizes are
application bytes. It deliberately records packet and wire-byte fields as
unavailable because it does not read operating-system counters.

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

The saved network observations include the idle controls, response checks,
tool/runtime versions and counter scope.
The interface is shared by the host: a quiet idle control is useful evidence but
not a proof that later traffic belongs exclusively to the measured process.
A remote server, concurrent clients and a saturated link require separate experiments.

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
1.7.1–1.7.5 and 1.10.1–1.10.2. Earlier releases remain in the in-process history;
they are not silently presented as socket measurements. Each panel below uses
one fixed payload size across the server releases.

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

No HTTP request is made by the exporter. Keep Linux network results separate from
Windows in-process timing results: their runtime environment and measurement scope differ.

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

The profiler perturbs execution. Use it to choose a change, then return to the
ordinary timing collector and verify the response again. Very short requests may
produce sparse CPU samples; increasing the profiling workload is more informative
than interpreting an empty graph as zero cost.

## 6. Diagnose inference, startup, allocation and retention

```sh
julia setup.jl analyzers
julia --project=.controller/analyzers scenarios.jl diagnose oxygen oxygen-heap
julia --project=.controller/analyzers additional-diagnostics.jl oxygen
```

The seven diagnostic records below use 2,048 events, as does the application
timing history. The reusable scenario now defaults to 64 events to keep full
allocation stacks manageable. The additional Aqua/heap experiment uses that
smaller fixture. Always check the recorded parameters before comparing results.

JET checks inferred execution for possible errors. AllocCheck reports possible
allocation sites; SnoopCompile examines inference work. The records below show
what each instrument actually reported, including its version and scope.

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

Lock-conflict counts do not measure waiting duration. This sequential fixture
cannot qualify behavior under concurrent traffic. Aqua separately checks package
quality; a quality finding is not a measured performance regression.

Aqua reported an ambiguity between Oxygen's dictionary and vector overloads
of `recursive_merge` for a zero-argument call. That does not establish a failure
of the HTTP routes measured above. The heap snapshot reports shallow GC-object
sizes across the worker, not retained dominator sizes or native allocations.
The large raw snapshot stays local; this figure uses its exported category totals.

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

Every result records tool availability, timeout/failure status and whether the
workload oracle completed. A partial profile or failed startup is not a successful
package test. GPU, remote-host and hardware-counter qualification require the
corresponding hardware and permissions; no such result is fabricated here.

```@raw html
<DiagnosticReports source="/examples/real-packages/oxygen-native/summary.json" />
<DocMedia src="/examples/real-packages/oxygen-native/massif-1.svg" alt="Oxygen native heap, allocator overhead and tracked stacks recorded by Massif" />
```

The recorded native run completed Callgrind, Massif and heaptrack with a passing
oracle. Memcheck and Cachegrind reached their time limit during Julia compilation;
their partial captures do not establish package correctness or native memory safety.
The Massif axis counts instrumented instructions rather than wall-clock seconds.

## 7. Preserve experiments and reuse the same evidence

```sh
julia --project=.controller/oxygen scenarios.jl run oxygen
julia --project=.controller/extras drwatson.jl run oxygen
```

A shared scenario catalog records parameters and correctness boundaries. DrWatson
keeps parameters with a cached experiment; repeating its command can reuse a saved
result. Set `PERFCHECKER_FORCE=true` when you deliberately want fresh measurements.
Property-generated event inputs can be frozen with `corpus.jl` and replayed by the
application oracle. Reusing a corpus improves comparability; reusing a result is
not another independent observation.

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

When a patch appears slower, narrow the range, repeat the pair and verify the
response semantics before proposing a fix. The [contribution guide](contributing.md)
explains how to contribute the experiment, figures and interpretation together.
