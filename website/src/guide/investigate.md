# Investigate a performance change

A comparison shows that an operation's cost changed. To decide what to edit,
we need to find the calls responsible for that cost. Continue with the
Bibliography export example: it writes entries to a buffer, so string creation,
writing and buffer growth are useful places to inspect.

The profiles below come from the prepared example used in the manual. They
were collected at revision `575ec81`, after the streaming-export change; they
show where that implementation spends its resources.

## Collect a profile

From the `examples/bibliography/` directory prepared in the
[operation benchmark](../tutorials/quick-tour.md), select an allocation profile:

```sh
julia --startup-file=no --project=.controller/core run.jl profile_alloc Bibliography export_bibtex
```

Keep the printed report directory. Use `profile` in place of `profile_alloc`
for CPU samples, or `wall_profile` for task stacks (Julia 1.12 or later). Each
command collects a separate profile of the same export operation.

## Read a flame graph

A **call stack** records the chain of calls leading to the current function.
A **flame graph** aggregates many such stacks into nested rectangles. Width
represents the selected weight, such as CPU samples or allocated bytes. Depth
shows the calling relationship. The horizontal position is generally not a
timeline: neighbouring rectangles need not represent operations that happened
one after the other. See [Brendan Gregg's flame graph explanation](https://www.brendangregg.com/flamegraphs.html).

A wide parent includes the weight of its descendants. Do not add parent and
child percentages as if they were independent costs. Start with a wide branch,
follow it into the relevant Bibliography function, then inspect its source line
and full call path. The same function can occur under different callers.
PerfChecker's hover or keyboard-focus details retain that path.

For a CPU flame graph, width concerns sampled execution. For a wall-time flame
graph, it concerns sampled task stacks, including waiting tasks where supported.
For an allocation flame graph, it concerns sampled allocation bytes or events.
The geometry is similar, but the quantity is different. Colours follow the
view's legend; they are not a universal temperature scale or a verdict that a
function is defective.

### Inspect three recorded Bibliography profiles

These graphs come from three completed runs of `export_bibtex` on the recorded
development revision `575ec810042cc791fd47a2c025a80246ccf039b5`. They explain how
to read a profile at one revision. The [nine-version gallery](../interfaces/visualization.md)
answers the separate question of how measured cost changes across releases.
All three captures used Windows, Julia 1.13.0 and one worker thread.

Select a weight below and inspect a wide rectangle. Each view retains at most
the 40 highest-weight distinct stacks; its percentages use the retained total.
The source filters and this selection can omit other work. The three runs have
different collection methods, so their weights must not be added or compared
as durations. No correctness oracle or regression threshold was evaluated by
these recorded profile runs.

```@raw html
<MeasuredProfiles />
```

In the recorded CPU view, `export_bibtex` at `Bibliography/src/bibtex.jl:211`
has weight **156 CPU samples out of 159 retained**, or about **98.1%**.
That is a share of this filtered capture, not 156 function calls or 156 ns.
Its `_write_bibtex` child at line 162 accounts for 100 of those samples: this
is work already included in the parent's weight. Follow that branch to see
the string-writing and buffer-growth paths, then use the allocation view to
investigate their memory cost.

To reproduce these views from your own completed walkthrough runs, pass the
CPU, wall-time and allocation report directories in that order:

```sh
julia --startup-file=no --project=examples/bibliography/.controller/web examples/bibliography/export-profiles.jl CPU_REPORT WALL_REPORT ALLOCATION_REPORT profile-html
```

`CPU_REPORT`, `WALL_REPORT` and `ALLOCATION_REPORT` are placeholders for the
directories printed by the [Bibliography runner](../tutorials/bibliography.md).
The exporter reads saved evidence; it does not launch a new measurement.

## Check the effect of a change

Start with a call path that accounts for a substantial part of the profile.
For export, creating fewer intermediate strings is one possible change. The
[streaming-export comparison](../tutorials/comparisons.md) measures a revision
that writes entries to a shared buffer instead. Its allocation measurements
decrease from 3,904 to 2,976 bytes for the small example input.

After editing your own code, check the exported document and rerun the original
benchmark with the same input. Profiling adds overhead, so use BenchmarkTools
or Chairmarks to measure the change in execution time. Repeat the comparison
if the difference is small relative to the variation between samples.

For other costs, use [process memory](../process-memory.md) to study retained
RAM, [network measurements](../network-measurement.md) for traffic, or
[native profiling](../native-profiling.md) for Julia's runtime and external
libraries.

Once the comparison is useful locally, continue to [running checks in CI](../tutorials/ci.md).
