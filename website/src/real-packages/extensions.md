# Profiles, extensions and experiments

The DataStructures and Oxygen examples use the tools listed below. Follow
either package's tutorial for the commands and results, or use this index to
find a particular collector. Profiling and diagnostic tools run separately
from the timing benchmarks because their instrumentation changes execution costs.

| Capability | Recorded use in these examples | Where to continue |
| --- | --- | --- |
| BenchmarkTools and Chairmarks | Separate timing collectors, fresh state, 30 warmed samples | Both package histories; all container operations also have a Chairmarks run |
| TestItemRunner | Tagged construction/use and HTTP items, measured in isolated workers | Each package's TestItems instructions |
| UnicodePlots | Terminal rendering of every exported catalogue view | The Unicode download beside each figure |
| Makie and WGLMakie | Static SVG figures and interactive replay of saved plot models | Each package's notebook and interface instructions |
| PProf and FlameGraphs | Exported recorded CPU/allocation stacks | `profiles.jl` and the profile figures on both pages |
| JET, AllocCheck, SnoopCompile | Executed operation diagnostics with findings and scope | Diagnostic records on both pages |
| Latency, GC, memory and locks | Executed diagnostics, separately plotted | Both package pages |
| Aqua and heap snapshots | Quality findings and redacted whole-worker GC snapshots | Quality reports and heap-category figures |
| DrWatson | A measured, cached heap experiment for each package | `drwatson.jl run PACKAGE` |
| PropCheck and Supposition | Frozen seeded input corpora and correctness replay | `corpus.jl` |
| Documenter and DocumenterVitepress | Rendering a saved bundle; no campaign during the doc build | `documenter.jl` |
| Network counters and isolation | Real loopback requests plus an executed namespace capture | Oxygen's network section |
| Valgrind and heaptrack | Executed native captures with individual completion/timeout statuses | Native reports on both pages |
| Linux perf and VTune | Not installed on the recording host; runnable plans are provided | `native.jl` / `native-run.jl` |
| HTTPAdvisor | Optional provider transport; no model request in this experiment | [Advice setup](../advisor-ui.md) |
| GPU and multi-machine transfer | No suitable GPU or multi-host calibration dataset in this example | Add the corresponding hardware-backed experiment before making a claim |

## Timing: BenchmarkTools and Chairmarks

Both historical campaigns exercise both collectors. Each has its own definition
of a sample and its own measurement identity. Use them to corroborate a result,
not to concatenate two different distributions as though they came from one
instrument. The default history includes all event operations with BenchmarkTools
and the heap operation with Chairmarks; `all` expands that selection.

## Allocation, CPU and wall-time profiles

```sh
julia --project=. measure.jl profiles
julia --project=. oxygen/measure.jl profiles
julia --project=. profiles.jl results/ACTUAL-PROFILE-RUN exports/profiles
julia --project=. replay.jl results/ACTUAL-PROFILE-RUN
```

An allocation profile attributes sampled allocation activity to call paths.
Use it to locate avoidable temporary objects; it is not a resident-memory plot.
A CPU profile samples where execution spends processor time. A wall-time
profile can also reveal waiting. The profiler perturbs execution, so compare
performance with the ordinary timing collector after making a change.

A flame graph aggregates call stacks. Its width is the selected weight—samples
or bytes—and its vertical direction follows nested calls. It is not a timeline.
Very short operations may produce too few samples to draw a useful flame graph;
increase the workload size or profiling window to collect more samples.

These are the recorded profiles of the DataStructures heap and Oxygen heap
request. Open the catalogue to switch between allocation and sampling views.

```@raw html
<PackageGallery package-name="DataStructures profiles" directory="/examples/real-packages/datastructures-profiles" />
<PackageGallery package-name="Oxygen profiles" directory="/examples/real-packages/oxygen-profiles" />
```

`profiles.jl` exports saved stacks as folded text and Speedscope JSON. After
`setup.jl extras`, run it with `--project=.controller/extras` to also activate
PProf and FlameGraphs and write pprof artifacts. Missing stack observations are
reported explicitly. The output can be inspected without rerunning a workload.

DataStructures also has the legacy `:alloc` line-tracking collector in its
matrix. It has different perturbation and attribution from `:profile_alloc`;
do not treat their byte totals as interchangeable timing measurements.

## Shared scenarios and diagnostics

The DataStructures `scenarios.toml` names the same four lifecycle factories as
the suite. Run it without translating the workload:

```sh
julia --project=. scenarios.jl plan
julia --project=. scenarios.jl run
julia setup.jl analyzers
julia --project=.controller/analyzers scenarios.jl diagnose
```

JET investigates inference and possible runtime errors. AllocCheck searches
for statically visible allocations. SnoopCompile examines compilation work;
latency diagnostics distinguish loading and first execution from warm timing.
GC, reachable-memory and lock diagnostics answer additional questions about
allocation pressure, retained objects and contention. An unsupported provider
or runtime returns an availability result rather than installing dependencies
during a check.

The equivalent Oxygen lifecycle is `EventService.request_case`. Run its catalogue with:

```sh
julia --project=.controller/oxygen scenarios.jl run oxygen
julia --project=.controller/analyzers scenarios.jl diagnose oxygen
```

Its measured
operation includes decoding and encoding, so an inference or allocation result
there has a broader scope than the data-structure operation alone.
The shared Oxygen catalogue uses **64 events**, while its historical timing
suite uses 2,048. Full allocation-stack capture is much more expensive than
counting allocated bytes; the smaller diagnostic fixture keeps those artifacts
manageable. Compare results only when their parameters and scope agree.

To investigate one case instead of the whole catalogue, append its ID:
`scenarios.jl diagnose oxygen oxygen-heap`, or
`scenarios.jl diagnose datastructures events-heap`.

## DrWatson: keep experiment parameters with the result

```sh
julia setup.jl extras
julia --project=.controller/extras drwatson.jl
```

This executable introduction derives parameter dictionaries and a filename from
the suite plan, then uses `drwatson_produce_or_load` to save or reload an experiment
configuration. Reusing that file is deliberately labelled as configuration reuse,
not a new performance observation.

To execute and cache one heap benchmark on the latest selected release:

```sh
julia --project=.controller/extras drwatson.jl run datastructures
julia --project=.controller/extras drwatson.jl run oxygen
```

Repeating the command reuses its saved result. Set `PERFCHECKER_FORCE=true`
when you deliberately want a fresh measurement instead.

To cache a real, deliberately small suite, use:

```julia
using PerfChecker, DrWatson
include("suite.jl")
suite = build_suite()
result, filename = drwatson_run_suite(suite; profile=:quick,
    directory="results/cached-suite", tag=false,
    version_provider=_ -> KITCHEN_VERSIONS)
```

Inspect the plan first: `:quick` selects versions according to the suite's
profile rules and does not necessarily mean one workload. Use a smaller
`SoftwareSuite` when you want fewer features. Revisions and frozen inputs belong
in the experiment identity; pass `force=true` when you intend to remeasure.

## Property-generated inputs

PropCheck and Supposition can discover inputs that your handwritten examples
miss. Freeze those generated cases with `freeze_propcheck_corpus` or
`freeze_supposition_corpus`, then replay the saved corpus with an oracle. Input
generation belongs outside the timed operation. A saved corpus is what makes
the performance comparison repeatable after a stochastic search.

The event workload already separates input generation from execution. A useful
extension is to generate event counts and seeds, freeze them, and measure the
same cases on every target version. See [the corpus example script](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/blob/release/v1.0.0-rc1/examples/kitchen-sink/corpus.jl).

```sh
julia --project=.controller/extras corpus.jl freeze
julia --project=.controller/extras corpus.jl replay
```

The first command refuses to overwrite an existing corpus. The second replays
40 saved input cases through the heap oracle without generating new inputs.

## Native tools and external memory

```sh
julia --project=. native.jl
```

This prepares commands for Valgrind Memcheck, Callgrind, Massif and Cachegrind,
plus heaptrack, Linux perf and VTune. It writes each tool's local availability
and its argument list under `exports/native`; it does **not** start those tools.
The standalone `native-workload.jl` checks its answer while exercising the heap.

Memcheck searches for invalid native accesses and leaks. Massif and heaptrack
help attribute native heap activity. Callgrind and Cachegrind instrument work;
Linux perf and VTune can sample CPU behavior. These tools observe Julia startup,
the runtime and native dependencies as well as Julia code. Their overhead and
symbol attribution must be assessed before using the results as evidence.

Prepare Linux plans from Linux with Linux paths. Windows availability does not
establish WSL availability. No native profiler is claimed to have been executed
by merely exporting a plan. See [native profiling](../native-profiling.md) for
the supported scope and the [external-memory guide](../process-memory.md) for
the difference between Julia allocations and process memory.

The package pages also show actual Linux executions of `native-run.jl`, their
Massif timelines, and explicit timeout or availability results. To reproduce:

```sh
julia --startup-file=no setup-linux.jl
julia --startup-file=no --project=.controller/linux setup-native.jl
julia --startup-file=no --project=.controller/linux native-run.jl datastructures
julia --startup-file=no --project=.controller/linux native-run.jl oxygen
```

## Machines, documentation and advice

`native.jl` also records `machine_profile()`. Keep machine and environment
information beside results when comparing hosts. A single host cannot validate
a transfer model; collect overlapping calibration cases on multiple machines
before using [machine transfer](../machine-transfer.md) for CI estimates.

The Documenter and DocumenterVitepress integrations publish recorded plots;
this documentation is one consumer. They need not rerun the example suites.
UnicodePlots, Makie, WGLMakie, Pluto and Web interface (Oxygen) share the
[replay recipes](interfaces.md).

```sh
julia --project=.controller/extras documenter.jl results/ACTUAL-RUN
```

This writes an ordinary Markdown page to `exports/performance.md` for inclusion
in a Documenter project; it does not run that project's tests or redeploy a site.

HTTPAdvisor is optional transport for advice, not a measurement collector.
Model-backed advice requires a configured provider and cannot replace an oracle
or a fresh before/after measurement. No external model request is needed for
either package example. GPU, a multi-machine calibration experiment and remote
network load remain outside these two local demonstrations.
