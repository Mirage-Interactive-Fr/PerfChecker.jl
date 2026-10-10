```@raw html
<a id="Investigate-a-performance-change"></a>
```

# Investigate a change

Find which calls account for a cost change.

## Collect a profile

From `examples/bibliography/`, with the controller prepared:

```sh
julia --startup-file=no --project=.controller/core run.jl profile_alloc Bibliography export_bibtex
julia --startup-file=no --project=.controller/core run.jl profile       Bibliography export_bibtex
julia --startup-file=no --project=.controller/core run.jl wall_profile  Bibliography export_bibtex
```

Keep the printed report directory. Each command collects a separate profile of the same operation.

## Use the same investigation in your interface

Use **Bibliography → export_bibtex → profile_alloc** in every tab. Keep the same pinned source and input, inspect the selected plan, then deliberately launch the allocation profile. Open the completed allocation report to inspect its sampled call paths.

::: tabs

== VS Code

1. Open `examples/bibliography/` and select `.controller/core` as **Runner Project**.
2. In Studio, choose `suite.jl`, package **Bibliography**, workload **export_bibtex** and check **profile_alloc**.
3. Inspect the one-row plan, launch, and wait for the saved run.
4. Open that run's allocation artifacts and check their sampling/attribution status before reading stacks.

See [suite controls](../interfaces/vscode-workflows.md) and [controller setup](../interfaces/vscode-configuration.md). A shared-scenario catalog must declare its collector; changing the interface cannot add a measurement.

== Pluto

From `examples/bibliography/`, prepare and open the supplied notebook:

```sh
julia --startup-file=no setup.jl pluto
julia --startup-file=no --project=.controller/pluto pluto.jl
```

Select **Bibliography**, **export_bibtex** and **profile_alloc**. Inspect the one-row plan, press **Launch selected checks**, refresh status and explicitly save the completed reports. Selector edits do not launch a measurement. Open the saved allocation-profile artifact to inspect allocation sites and stacks.

```@raw html
<p><a href="../examples/bibliography/pluto/notebook.jl" download="notebook.jl">Download the actual Bibliography notebook (.jl)</a></p>
```

See [notebook setup and shutdown](../interfaces/repl-pluto.md).

== REPL / CLI

```sh
julia --startup-file=no --project=.controller/core run.jl profile_alloc Bibliography export_bibtex
```

Keep the printed report directory. The command collects only this workload's allocation profile. Open its saved artifacts without rerunning the workload. Use `repl.jl` in the same controller for interactive selection of the identical package, workload and collector.

== Web (Oxygen)

```sh
julia --startup-file=no setup.jl web
julia --startup-file=no --project=.controller/web web.jl
```

Open the example's local `http://127.0.0.1:8871/perfchecker/v1/` while the server runs. Select **Bibliography**, **export_bibtex** and **profile_alloc**, add only that check to the plan, inspect it and launch. Open the completed run and its allocation artifacts. The browser displays results; the controller or explicitly selected remote worker executes the experiment.

See [Web controller setup](../interfaces/web-studio.md) for binding, remote access and authentication.

:::

If the allocation site table is empty, read its allocation-profile status before
changing code. `zero_allocations`, `no_samples`, `outside_target_scope` and
`unattributed_samples` describe different evidence. The measured byte/count
totals are retained even when a location could not be sampled or attributed.
Repeat with a suitable sampling rate and inspect the selected source scope;
do not interpret missing stacks as zero cost. The [collector reference](../reference/checks.md#Profiles)
explains the fields and the difference between raw scenario weights and the
legacy allocation-stack estimates.

A [bounded investigation](../advisors.md) spends its time budget on provider requests, worker startup and dependency loading as well as the operation itself.
A timeout can therefore leave no observations; that absence is neither a measured zero nor evidence of the operation's cost.

## Read a flame graph

- Width is the selected weight: CPU samples, task samples or allocation bytes.
- Depth is nesting. Horizontal position is not a timeline.
- A wide parent includes its descendants. Do not add parent and child percentages.
- Follow a wide branch into the relevant function, then inspect its source line and full call path.
- The same function can appear under different callers.

In the recorded CPU capture, `export_bibtex` accounts for about 98% of retained samples. Its `_write_bibtex` child is part of that share, not additional cost.

## Check the effect of a change

1. Pick a call path that accounts for a large share.
2. Change the code (for export, avoid intermediate strings).
3. Rerun the original benchmark with the same input and verify the output.
4. Repeat when the difference is small relative to sample variation.

Profiling adds overhead, so confirm the change with BenchmarkTools or Chairmarks, not with the profile timings.

## Other costs

- [Process memory](../process-memory.md) — retained RAM.
- [Network measurement](../network-measurement.md) — traffic and packets.
- [Native profiling](../native-profiling.md) — Julia runtime and external libraries.


```@raw html
<a id="Inspect-three-recorded-Bibliography-profiles"></a>
```

## Recorded examples

```@raw html
<MeasuredProfiles />
```

## Next

[Run checks in CI](../tutorials/ci.md).
