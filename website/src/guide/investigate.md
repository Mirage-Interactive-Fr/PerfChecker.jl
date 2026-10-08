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

If the allocation site table is empty, read its allocation-profile status before
changing code. `zero_allocations`, `no_samples`, `outside_target_scope` and
`unattributed_samples` describe different evidence. The measured byte/count
totals are retained even when a location could not be sampled or attributed.
Repeat with a suitable sampling rate and inspect the selected source scope;
do not interpret missing stacks as zero cost. The [collector reference](../reference/checks.md#Profiles)
explains the fields and the difference between raw scenario weights and the
legacy allocation-stack estimates.

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
