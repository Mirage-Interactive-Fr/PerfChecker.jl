```@raw html
<a id="Check-catalog"></a>
<a id="Implemented-backends"></a>
```

# Collectors

A **check type** selects how a workload is measured. Each runs in an isolated worker with the chosen collector.

- Use a benchmark to decide **whether** a regression exists.
- Use a profile to find **where** the cost moved.
- Use network collectors for traffic, with attention to attribution.

## Persistent controller defaults

::: info Development API
This integration is a development addition after PerfChecker 1.0.1. It is not
part of the registered 1.0.1 release.
:::

Use Preferences.jl to retain three defaults in the active Julia project:

```julia
using PerfChecker
set_check_preferences!(threads=2, repeat=false, quiet=true)
check_preferences()
```

| Setting | Meaning | Accepted values |
| --- | --- | --- |
| `threads` | Julia threads in each measurement worker | Positive integer representable as `Int`, excluding `Bool` |
| `repeat` | Optional warmup in allocation, profile and network collectors | `Bool` |
| `quiet` | Suppress PerfChecker package-management logs | `Bool` |

BenchmarkTools and Chairmarks manage their own sampling and do not use `repeat`.
Use their `samples`, `evals` and other collector options explicitly. `quiet`
does not silence output printed by the workload.

The default write target is `LocalPreferences.toml` next to the **controller's
active Julia project**. It is unrelated to `PerfConfig.path`, which chooses the
workload environment. A normal check only reads preferences; it does not create
or modify a preference file. No path, command, package selection or credential
can be saved through these three APIs.

The order is collector defaults, inherited preferences, then explicit options.
Julia's normal environment-stack inheritance applies; local preferences override
exported project preferences. Feature and variant options and suite run overrides
remain explicit. The suite's internal `quiet=true` default is below preferences.

Defaults apply only when the caller leaves an option unset. VS Code feature
suites can inherit these controller defaults; an explicit feature setting still
wins. Investigations use their own scenario thread setting (one by default),
and the TestItems CLI explicitly defaults to one thread. These paths do not
automatically inherit the persistent thread default. Preferences and PkgEval do
not require a new editor extension; they are package and qualification features.

```julia
config = PerfConfig(:profile; path=pwd(), threads=1)
# This check uses one thread even when the persistent default is two.
```

For a shared project, opt in to storing defaults in `Project.toml`:

```julia
set_check_preferences!(threads=2, export_prefs=true)
reset_check_preferences!(:threads) # remove the local override; inherit again
reset_check_preferences!(:threads; export_prefs=true) # remove the shared value
reset_check_preferences!(block_inheritance=true) # block all three inherited defaults
```

Resetting without keys selects all three settings. It removes settings only at
the selected storage level and preserves other packages' preferences. A normal
reset allows inherited values to return; `block_inheritance=true` uses
Preferences.jl's clear markers instead. Invalid values and unknown keys are
rejected before an API write.

Changes take effect for future checks without restarting Julia. Each suite
freezes its defaults before preparing workers; changing a preference during that
suite does not change later runs in the same plan. Workers receive those resolved
values and do not reread controller preferences from their own environment.

Each result's qualification contains `check_configuration`, with `values`,
`origins` (`default`, `preferences` or `explicit`) and `config_hash`. Saved suite
bundles retain this evidence. On a cache hit, this snapshot describes the current
request's resolved configuration, not the historical origin of the cached
calculation. The cache hash includes effective values, not their
origins: supplying the same value explicitly or persistently shares an identity;
changing an overridden preference does not invalidate that identity. Keep the
saved configuration evidence when sharing results; a bare workload checkout does
not describe controller defaults inherited from another environment.

See the [Public API](public-api.md) for the full setter, reader and reset contracts
and the [Preferences.jl reference](https://juliapackaging.github.io/Preferences.jl/stable/reference/)
for environment-stack and clear-marker semantics.

For a reproducible CI experiment and an honest assessment of warmup, thread
settings and cache reuse, follow
[persistent defaults in CI](../tutorials/ci.md#Persistent-defaults-in-CI).
Preferences configure future checks; they are not measurements of the cost of
loading Preferences.jl or a claim that a changed default makes a package faster.

## Benchmarks

```@raw html
<a id="BenchmarkTools:-elapsed-time-and-allocation-cost"></a>
```

### `:benchmark` (BenchmarkTools)

Elapsed time, GC time, allocated bytes and allocation count. The default choice.

- Inspect the distribution, not only the median.
- Preparation outside the measured expression is excluded.
- Requires BenchmarkTools.

```@raw html
<a id="Chairmarks:-another-repeated-measurement-collector"></a>
```

### `:chairmark` (Chairmarks)

The same quantities as a low-overhead alternative for short measurements.

- Time is in seconds; GC is a **fraction** of elapsed time, not seconds.
- Do not merge BenchmarkTools and Chairmarks samples into one distribution.

## Profiles

```@raw html
<a id="CPU-profiling:-find-frequently-observed-call-paths"></a>
```

### `:profile` — CPU samples

Sampling profiler call stacks. A sample is not a call count.

- Follow a wide branch into its callees and inspect the source.
- An empty capture is missing evidence, not a zero-cost function.

```@raw html
<a id="Wall-time-profiling:-investigate-tasks-and-waiting"></a>
```

### `:wall_profile` — task wall-time samples

Captures task stacks, including tasks that are waiting. Requires Julia 1.12 or later.

- Use it when elapsed time is high but CPU samples do not explain it.

```@raw html
<a id="Allocation-profiling:-find-where-objects-are-created"></a>
```

### `:profile_alloc` — allocation stacks

Sampled allocation events with types and call stacks.

- Bytes weight the amount; event counts weight the frequency. They can rank hotspots differently.
- Julia-managed sampling does not cover native allocations.

Read `qualification["allocation_profile"]` together with the sites. An empty
site table does not establish that the workload allocated nothing:

| Status | Interpretation |
| --- | --- |
| `complete` | Target source sites were retained; inspect attribution counts and scope |
| `zero_allocations` | The separate byte and allocation-count measurements were both zero |
| `no_samples` | No allocation events were sampled; measured totals may still be positive |
| `outside_target_scope` | Events were captured, but their source sites were outside the selected target |
| `unattributed_samples` | Events were captured without a usable source site |

The record preserves measured `total_bytes` and `total_allocations`, raw and
attributed sample counts, sample rate, repetitions, a message and weight
semantics. Bytes and allocation count come from **two independently prepared
evaluations**, rather than one common observation. Legacy profile plots distribute
these measured totals over retained stacks; scenario profiles retain raw sampled
weights. Keep those definitions distinct. Empty profiles retain their status and
totals and do not produce invented source sites or a zero-valued flame graph.
Scenario results also expose the independent whole-operation totals as separate
observations, with `independent_operation_total` weight semantics and
`whole_operation` scope. A successfully collected empty profile can belong to a
functionally complete bundle; its qualification and diagnostics still determine
what the profile supports. It does not establish a performance improvement.

CSV profile caches retain this qualification in a matching
`.csv.allocation-profile.toml` sidecar. A legacy cache without it is recomputed
instead of guessing what an empty table meant.

```@raw html
<a id="Line-allocation-tracking:-attribute-bytes-to-source"></a>
```

### `:alloc` — allocation by source line

Allocation bytes attributed to file and line.

- Totals depend on collection scope and repetition; do not compare them with a per-call estimate.

Julia's line-allocation tracker creates `source.jl.<worker-pid>.mem` beside the
sources it executes. PerfChecker records each worker's ownership before your
preparation and measured code run. After success, a preparation or measurement
error, or cancellation, it waits for the worker to stop and removes that worker's
new traces. Files from other processes and unrelated `.mem` files are preserved.
If a reused worker PID overwrites an existing trace, PerfChecker reads the new
measurement and restores the previous bytes and permissions afterwards.

For asynchronous suites, call `cancel_suite!(job)` and then `wait_suite(job)`;
the cancellation request alone does not mean cleanup has finished. A cleanup
failure is reported as a failure, including the retained private inventory
directory, even when cancellation was requested. That directory contains the
worker PID, known source roots and a journal including saved original trace
bytes. If writing the inventory metadata also fails, that error is included in
the failure and the already saved journal is retained. PerfChecker does not
automatically delete old traces from earlier runs:
inspect the reported paths and resolve the filesystem or process error first.

The inventory covers the worker environment, development dependencies, package
depots, Julia standard libraries and files loaded through ordinary `include`.
A direct `include_string` that invents a filename outside those roots is not
covered by the include journal. A forcibly killed controller, power loss or
repeated interruption that prevents its cleanup code from running can leave
traces; no blanket deletion of a package's `.mem` files is performed on restart.

```@raw html
<a id="Network-collectors:-payload,-traffic-and-attribution"></a>
```

## Network

- `:network` — counters the workload reports. Safe to gate CI on those counters.
- `:network_interface` — shared host interface. Not CI-worthy unless the machine is hermetic.
- `:network_isolated` — dedicated network namespace. Safe to gate CI.

See [Network measurement](../network-measurement.md) for attribution and which counts double on loopback.

## Optional hardware counters

[PerfCheckerLinuxPerf](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/blob/main/packages/PerfCheckerLinuxPerf/README.md)
and [PerfCheckerLIKWID](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/blob/main/packages/PerfCheckerLIKWID/README.md)
are optional companions with an explicit Julia `run_counter_suite` API or
`counter_executor` passed to a Julia suite runner. Until separately registered,
develop each companion from the monorepo into its prepared worker project.
Keep the worker projects separate: LinuxPerf 0.4.2 requires PrettyTables 2,
whereas LIKWID 0.4.6 requires PrettyTables 3.

LinuxPerf counts the calling OS thread's user-space execution, excluding other
threads and child processes. LIKWID measures a native counter window on selected
CPUs within inherited affinity; attribution depends on its access mode and PID
configuration, and direct/daemon modes can include unrelated activity. Both run
the operation and synchronization once inside the window, then stop before the
oracle. Neither performs an implicit warmup or rerun.

Counts use unit `1`; CPU cycles are counts, not a duration. LinuxPerf records
enabled/running times separately in nanoseconds. LIKWID retains raw event values
with explicitly declared units and a separate group time in seconds; this API
does not expose enabled/running times. Do not mix these windows with benchmark
timing samples or infer elapsed time from cycle counts.

Linux perf-event permissions and, for LIKWID, a usable native `liblikwid` are
prerequisites. The companions do not change kernel settings, capabilities or
affinity. An `unavailable` result is missing evidence, never a zero counter or a
successful hardware measurement. LinuxPerf's `counter_not_scheduled` refusal
can occur after the operation, so inspect its lifecycle before retrying.

This initial integration does not wire a native selector into default CLI,
VSCode, Pluto or MCP workflows. The Web companion forwards an explicit Julia
executor at source level; a real hardware-counter HTTP/UI job has not been
qualified. See the companion READMEs for the exact supported architectures,
worker preparation, raw-value limits and current qualification scope.

```@raw html
<a id="One-feature,-several-checks"></a>
```

## One workload, several checks

Give several `FeatureSpec` entries the same `workload` identifier and different `backend`s. Interfaces then group them under one operation and let the user pick the check type.

```julia
checks = [
    FeatureSpec(:import_bibtex_time; workload = :import_bibtex, backend = :benchmark, entrypoint = "features/import_bibtex.jl"),
    FeatureSpec(:import_bibtex_alloc; workload = :import_bibtex, backend = :profile_alloc, entrypoint = "features/import_bibtex.jl"),
]
```

The entrypoint is ordinary Julia and must return the same result for every target. Keep fixture construction outside the measured expression when setup is not part of the contract.

## Choosing evidence

- Never compare values whose measurement-definition IDs or comparison keys are incompatible. See the [measurement model](../measurement-model.md).

## Recorded examples

```@raw html
<DocMedia src="/examples/bibliography/figures/history-samples.svg" alt="Nine groups containing all 900 export timings, with median markers and visible slow samples" caption="Each dot is one sample; the dark marks are medians. Horizontal displacement only separates dots. Overlap and slow observations remain visible." />
```

```@raw html
<DocMedia src="/examples/bibliography/figures/profile-cpu.png" alt="Recorded Bibliography export flame graph weighted by CPU samples" caption="A real capture at revision 575ec81, weighted by CPU samples. Width includes descendants; the 40 highest-weight stacks are retained. Open the interactive profiles to zoom and inspect full call paths." />
```

```@raw html
<DocMedia src="/examples/bibliography/figures/profile-wall.png" alt="Recorded Bibliography export flame graph weighted by task stack samples" caption="A real capture at revision 575ec81, weighted by task stack samples. Width includes descendants; the 40 highest-weight stacks are retained. Open the interactive profiles to zoom and inspect full call paths." />
```

```@raw html
<DocMedia src="/examples/bibliography/figures/profile-allocations.png" alt="Recorded Bibliography export flame graph weighted by sampled allocation bytes" caption="A real capture at revision 575ec81, weighted by sampled allocation bytes. Width includes descendants; the 40 highest-weight stacks are retained. Open the interactive profiles to zoom and inspect full call paths." />
```
