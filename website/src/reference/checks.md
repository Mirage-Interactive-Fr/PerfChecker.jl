# Check catalog

A **check type** selects how a workload is measured. For example, `:benchmark`
records timings and allocations for `import_bibtex`, while `:profile_alloc`
collects allocation stacks for that operation. Each check runs in an isolated
worker with the selected collector.

If these terms are new to you, start with
[Understand performance measurements](../guide/understanding-measurements.md).
The sections below explain what each collector contributes to the same
Bibliography experiment, before listing its configuration options.

## BenchmarkTools: elapsed time and allocation cost

Use `:benchmark` when your question is “did exporting this bibliography become
slower or more expensive in memory?” BenchmarkTools repeats the measured
expression and records timings. Inspect the distribution as well as its median:
a single fast observation does not describe the variability of the operation.
Preparation outside the measured expression is excluded; package loading and
Julia startup are not silently included in a warm export measurement.

The raw trial records elapsed and GC times in nanoseconds, plus memory and
allocation-count estimates. Allocated bytes describe Julia-managed allocation
activity, not the output file's size or the process's RAM. `samples`, `evals` and
the duration budget control collection. GC controls also affect the experiment;
keep them consistent across compared versions. See the
[BenchmarkTools manual](https://juliaci.github.io/BenchmarkTools.jl/stable/manual/).


```@raw html
<DocMedia src="/examples/bibliography/figures/history-samples.svg" alt="Nine groups containing all 900 export timings, with median markers and visible slow samples" caption="Each dot is one sample; the dark marks are medians. Horizontal displacement only separates dots. Overlap and slow observations remain visible." />
```

## Chairmarks: another repeated-measurement collector

Use `:chairmark` to measure the same Bibliography workload with Chairmarks. It
also provides sample timing, allocated bytes and allocation counts. Its raw
samples express time in seconds and collection overhead as a `gc_fraction`.
For example, a fraction of 0.02 means 2% of the sample's elapsed time. It is not
0.02 seconds of GC. PerfChecker retains the collector's measurement definition
when creating comparable observations.
The [Chairmarks API](https://chairmarks.lilithhafner.com/v1.3.1/reference)
defines these sample fields.

Choose one collector and consistent options for a version comparison. Running
both tools can help investigate sensitivity to the measurement method, but
mixing their samples into one distribution would hide that difference. In the
Bibliography walkthrough, `benchmark` and `chairmark` are separate selectable
checks under each workload. A timing difference between the two collectors is
not itself evidence of a change in Bibliography.

## CPU profiling: find frequently observed call paths

Use `:profile` after observing a timing change and wanting to locate it. Julia's
sampling profiler periodically records the current call stack. A frequently
observed path is a candidate hotspot. A sample is not a function invocation, and
absence from a short capture does not establish that a function has no cost.
See the [Julia profiling manual](https://docs.julialang.org/en/v1/manual/profile/).

For Bibliography's short export workload, use the recorded repetition and state
policy to understand how enough execution was collected. In the flame graph,
follow a wide export branch into its callees and inspect the source locations.
The displayed percentage is relative to the stacks retained by that view,
including its source filters. It is not necessarily a percentage of the whole
application's elapsed time. A profile with no attributable samples is reported
as insufficient evidence rather than as a zero-cost function.


```@raw html
<DocMedia src="/examples/bibliography/figures/profile-cpu.png" alt="Recorded Bibliography export flame graph weighted by CPU samples" caption="A real capture at revision 575ec81, weighted by CPU samples. Width includes descendants; the 40 highest-weight stacks are retained. Open the interactive profiles to zoom and inspect full call paths." />
```

[Inspect this graph interactively](../guide/understanding-measurements.md#Inspect-three-recorded-Bibliography-profiles).

## Wall-time profiling: investigate tasks and waiting

Use `:wall_profile` when elapsed time is high and execution samples do not explain
it. Julia's wall-time profiler captures task stacks, including tasks that are
not currently running. This can reveal waits for I/O or synchronization. It
requires a runtime that supplies this facility. Sampling multiple tasks does
not make their summed weights equal to one operation's stopwatch duration.
See Julia's [wall-time profiler](https://docs.julialang.org/en/v1/manual/profile/#Wall-time-Profiler).

The `wall` in this collector and in a benchmark both refers to elapsed time,
but the results answer different questions: the benchmark gives a duration for
the measured operation, while the profile helps locate task stacks during an
interval. In Bibliography, compare an import profile with its benchmark before
attributing a wide I/O-related branch to slow parsing. Waiting for input and
computing on input suggest different changes.


```@raw html
<DocMedia src="/examples/bibliography/figures/profile-wall.png" alt="Recorded Bibliography export flame graph weighted by task stack samples" caption="A real capture at revision 575ec81, weighted by task stack samples. Width includes descendants; the 40 highest-weight stacks are retained. Open the interactive profiles to zoom and inspect full call paths." />
```

[Inspect this graph interactively](../guide/understanding-measurements.md#Inspect-three-recorded-Bibliography-profiles).

## Allocation profiling: find where objects are created

Use `:profile_alloc` when an export's allocated-byte or allocation-count result
needs an explanation. `Profile.Allocs` records sampled allocation events with
their types and stacks. The sampling rate controls which events are observed;
small captures can miss rare sites. Bytes weight the amount allocated, whereas
event counts weight how often allocations were sampled. Those views can rank
hotspots differently.

In the allocation flame graph, a wide branch means a large allocation weight,
not a long execution time. Follow it to a string or buffer construction site,
then rerun the timing and allocation benchmark after changing that code. An
allocation hotspot does not prove a leak: retaining unused objects is a different
question. Julia-managed allocation sampling does not cover every allocation by
native dependencies. See [Profile.Allocs](https://docs.julialang.org/en/v1/stdlib/Profile/#Memory-allocation-analysis).


```@raw html
<DocMedia src="/examples/bibliography/figures/profile-allocations.png" alt="Recorded Bibliography export flame graph weighted by sampled allocation bytes" caption="A real capture at revision 575ec81, weighted by sampled allocation bytes. Width includes descendants; the 40 highest-weight stacks are retained. Open the interactive profiles to zoom and inspect full call paths." />
```

[Inspect this graph interactively](../guide/understanding-measurements.md#Inspect-three-recorded-Bibliography-profiles).

## Line allocation tracking: attribute bytes to source

Use `:alloc` for allocation evidence organized by source file and line. The
`targets` and `track` options determine which source is relevant, and repetition
affects the accumulated evidence. Read these totals with their collection scope;
do not compare a repeated line total directly with a per-call benchmark estimate.

For Bibliography, this view can guide an investigation from a file with many
allocated bytes to a particular export line. Compilation and instrumentation
can affect collection, so perform a separate ordinary benchmark to validate a
proposed speedup. A line without attributed bytes does not establish that all
native code called from that line allocated nothing.

## Network collectors: payload, traffic and attribution

Use `:network` for counters explicitly reported by the workload, such as payload
bytes or completed operations. Use `:network_interface` to observe interface
traffic, including protocol overhead and potentially unrelated processes. Use
`:network_isolated` when supported to place the measured process group inside a
dedicated network namespace. These scopes are deliberately different.

A byte count measures data volume; packet count measures packets; drops report
discarded traffic. Latency measures elapsed time within a declared boundary,
while throughput relates completed work or bytes to time. Bibliography's local
`web_render` operation formats content: its name does not imply that it sends
HTTP traffic. Measuring a service built around that output needs an explicit
client/server workload and counters. The [network guide](../network-measurement.md)
explains the contracts and which scopes can support a CI budget.

## Implemented backends

| Backend | Primary evidence | Important options | Notes |
| --- | --- | --- | --- |
| `:benchmark` | BenchmarkTools time distribution, GC time, bytes and allocation count | `samples`, `seconds`, `evals`, `overhead`, `gctrial`, `gcsample` | Best default for steady-state latency and allocations. Requires BenchmarkTools. |
| `:chairmark` | Chairmarks sample distribution and memory statistics | backend-specific Chairmarks options | Low-overhead alternative for short measurements. Requires Chairmarks. |
| `:alloc` | Allocation bytes attributed to source file and line | `threads`, `targets`, `track`, `repeat` | Uses Julia allocation tracking; select source targets deliberately. |
| `:profile` | CPU samples, stack frames, dispatch/GC markers and inferred return status | `profile_seconds`, `profile_delay`, `buffer`, `max_stack_depth`, `max_profile_stacks` | Sampled evidence, suitable for flame graphs and attribution. |
| `:wall_profile` | Task wall-time samples | profile duration/delay and stack limits | Requires a Julia runtime with wall-time profiling support. |
| `:profile_alloc` | Sampled allocation bytes/counts and allocation stacks | `sample_rate`, `profile_repetitions`, stack limits | Uses `Profile.Allocs`; useful for type and stack drill-down. |
| `:network` | Workload-reported payload bytes, operations and optional packet/connection counters | repetitions and workload contract | Strong attribution to the feature, but only for counters the workload reports. |
| `:network_interface` | Host-interface bytes, packets and drops | interface selector | Includes unrelated host traffic unless the interface is controlled. |
| `:network_isolated` | Network-namespace bytes, packets and drops | `NetworkIsolationSpec` | Strong process-group attribution on Linux or WSL2. |

BenchmarkTools and Chairmarks collectors load through Julia package extensions
inside the measurement environment. Interfaces live in separate packages:
PerfCheckerMakie, PerfCheckerWeb and PerfCheckerPluto. Installing the core alone
does not load their graphical or web dependencies. See the
[package architecture](../reference/extensions.md) for the boundary between
interfaces and collectors.

## One feature, several checks

The suite can expose several `FeatureSpec` entries with the same `workload`
identifier and different backends. Every interface groups those entries under
the business feature and lets the user select the check types independently.

This configuration fragment belongs in a suite whose `features/import_bibtex.jl`
file already defines the workload callbacks. It does not execute anything by
itself; see the [software-suite tutorial](../software-suites.md) for composition.

```julia
using PerfChecker
checks = [
    FeatureSpec(:import_bibtex_time;
        workload = :import_bibtex,
        backend = :benchmark,
        entrypoint = joinpath(@__DIR__, "features", "import_bibtex.jl")),
    FeatureSpec(:import_bibtex_allocations;
        workload = :import_bibtex,
        backend = :profile_alloc,
        entrypoint = joinpath(@__DIR__, "features", "import_bibtex.jl")),
    FeatureSpec(:import_bibtex_cpu;
        workload = :import_bibtex,
        backend = :profile,
        entrypoint = joinpath(@__DIR__, "features", "import_bibtex.jl")),
]
```

The entrypoint is ordinary Julia code and should return the same semantic result
for every target. Keep fixture construction outside the measured expression
when setup cost is not part of the contract.

## Choosing evidence

- Use `:benchmark` or `:chairmark` to decide **whether** a regression exists.
- Use `:profile`, `:wall_profile`, `:profile_alloc`, and `:alloc` to investigate
  **where** the cost moved.
- Use `:network` for exact application counters and `:network_isolated` for
  attributed process-tree traffic.
- Treat host-interface latency and traffic as contextual unless the host is
  hermetic.
- Never compare values whose measurement-definition IDs or comparison keys are
  incompatible.

See the [measurement model](../measurement-model.md) for lifecycle phases and
scope, and [interactive plots](../interfaces/visualization.md) for the views
generated from these observations.
