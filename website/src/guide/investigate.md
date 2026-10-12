```@raw html
<a id="Investigate-a-performance-change"></a>
```

# Investigate a change

Find which calls account for a cost change.

## Collect a profile

From `examples/bibliography/`, with the controller prepared:

::: tabs

== CPU samples

```sh
julia --startup-file=no --project=.controller/core run.jl profile Bibliography export_bibtex
```

Recorded result at Bibliography source `575ec81`:

```@raw html
<InteractiveRecordedPlot source="/examples/bibliography/profiles/cpu.json" html="/examples/bibliography/profiles/cpu.html" title="BibTeX export — cpu samples" kind="cpu_flamegraph" />
```

Sampled running call stacks; width is CPU-sample weight. Inspect a frame for its full path and weight.

== Allocation samples

```sh
julia --startup-file=no --project=.controller/core run.jl profile_alloc Bibliography export_bibtex
```

Recorded result at Bibliography source `575ec81`:

```@raw html
<InteractiveRecordedPlot source="/examples/bibliography/profiles/allocations.json" html="/examples/bibliography/profiles/allocations.html" title="BibTeX export — allocation samples" kind="allocation_flamegraph" />
```

Sampled allocation stacks; width is allocation weight, not resident memory. Inspect a frame for its full path and weight.

== Wall-time samples

```sh
julia --startup-file=no --project=.controller/core run.jl wall_profile Bibliography export_bibtex
```

Recorded result at Bibliography source `575ec81`:

```@raw html
<InteractiveRecordedPlot source="/examples/bibliography/profiles/wall.json" html="/examples/bibliography/profiles/wall.html" title="BibTeX export — wall-time samples" kind="wall_flamegraph" />
```

Task stacks including waiting; requires Julia 1.12 or later. Inspect a frame for its full path and weight.

:::

Keep the printed report directory. Each command collects a separate profile of the same operation. The saved figures above are evidence from the published capture.

## Use the same investigation in your interface

Select **Bibliography → export_bibtex → profile_alloc** in the prepared controller, inspect the plan, and launch explicitly. The completed report contains the same kind of allocation evidence shown above. Interface-specific launch, cancellation and report controls are documented in their own guides. Changing the interface cannot add an undeclared collector.

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

The three native views beside the collection commands preserve their original source, runtime and sampling metadata in the downloadable JSON. Profiles attribute one revision; they do not establish an improvement between revisions.

## Next

[Run checks in CI](../tutorials/ci.md).
