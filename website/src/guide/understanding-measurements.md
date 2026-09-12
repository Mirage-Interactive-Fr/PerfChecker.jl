# Understand performance measurements

A performance measurement answers a question about a particular operation.
For Bibliography, that operation might be exporting one prepared bibliography
to BibTeX. Its input size, output and measurement boundary matter as much as the
number on the screen. Timing that export answers a different question from
timing Julia startup, package loading, input construction and export together.

Start with a benchmark to see whether the operation became slower or allocated
more memory. Then use a profiler to investigate where the cost comes from.
Finally, repeat the benchmark after a change and check that the output is still
correct. A useful profile identifies a place to investigate; it does not by
itself demonstrate an improvement.

## Wall time: how long the operation takes

**Wall time**, or elapsed time, is the difference between the clock readings at
the start and end of an operation. It includes time spent computing and time
spent waiting within that boundary. In Bibliography's `export_bibtex` benchmark,
the prepared input already exists when the clock starts. In an import benchmark,
reading the fixture is part of the workload. Always read the workload definition
before interpreting the timing.

Time units are easy to confuse: one second is 1,000 milliseconds (ms), one
millisecond is 1,000 microseconds (µs), and one microsecond is 1,000 nanoseconds
(ns). A displayed value of 7,000 ns means 7 µs. This is an illustrative conversion,
not a performance guarantee for Bibliography. PerfChecker's plot labels and
measurement definitions state the unit; raw collector formats can differ.

In exported data, `By` denotes bytes and `1` denotes a dimensionless quantity,
such as a count or fraction. These are unit labels. They differ from the `/1`
at the end of a [data-format identifier](../reference/run-bundles.md), which
identifies the schema version. A plot may retain an identifier such as
`julia.wall.time` so its measurement can be matched to its definition.

**CPU time** concerns processor execution. It is not interchangeable with wall
time: waiting for a file or a lock can increase elapsed time while doing little
CPU work. Several threads can also consume CPU time simultaneously. A CPU
profile's sample counts are a third quantity: they describe sampled stacks,
not a stopwatch duration for every function call.


```@raw html
<DocMedia src="/examples/bibliography/figures/history-time.svg" alt="Bibliography export medians across nine tagged versions on a linear microsecond axis" caption="One hundred samples per tag, Windows, Julia 1.13.0, one worker thread. Inputs match; the dependency stack evolves with the tags. Lower means less elapsed time." />
```

## Samples, repetitions and distributions

A **benchmark sample** records a measured execution, or a batch of executions
whose timing is normalized per evaluation. `samples` requests how many such
observations to collect; `evals` controls evaluations inside a sample. A time
budget can limit the actual sample count. The Bibliography history requests
100 samples with one evaluation per sample. Read the exported observations to
see what was actually recorded.

Repeated timings differ because of scheduling, caches, GC and other activity.
The **median** is the middle value after sorting the samples. The **minimum**
describes the fastest observed sample; the **mean** is sensitive to slow samples.
A **percentile**, such as p95, is a threshold containing about 95% of the observed
values. A small microbenchmark does not establish a service's production p95:
input diversity, concurrency and load would need their own experiment.

In the [historical gallery](../interfaces/visualization.md), compare the version
curve with the sample distribution. A difference between two medians is less
convincing when the measurements vary widely. Repeat important comparisons in
controlled sessions. A successful measurement run does not imply that a CI
regression policy was evaluated.


```@raw html
<DocMedia src="/examples/bibliography/figures/history-samples.svg" alt="Nine groups containing all 900 export timings, with median markers and visible slow samples" caption="Each dot is one sample; the dark marks are medians. Horizontal displacement only separates dots. Overlap and slow observations remain visible." />
```

## Allocated bytes, allocation count and live memory

An **allocation** obtains memory for an object. Allocated bytes describe the
amount obtained during the operation; allocation count describes how many
allocation events occurred. These answer different questions. One large buffer
can allocate more bytes than many small objects, while the many small objects
may impose more management work. In Bibliography, temporary strings and buffers
are useful candidates to investigate when export allocations increase.

**Live memory** is memory still retained at a point in time. Cumulative allocated
bytes are not the same as live bytes or the process's RAM usage. An operation can
create and discard many temporary objects while keeping a small live result.
Julia allocation measurements also do not account for every native allocator
used by a C library. The [memory guide](../process-memory.md) explains which
process and external-memory counters can complement them.


```@raw html
<DocMedia src="/examples/bibliography/figures/history-memory.svg" alt="Allocated bytes per Bibliography export across nine tags, from 4480 bytes at 0.1.0 to 8352 at 0.4.0" caption="Julia allocation activity per operation. These values are neither retained heap size nor resident process memory. All nine points come from recorded measurements." />
```

## Garbage collection: reclaiming unused objects

The **garbage collector**, usually shortened to **GC**, reclaims managed memory
that the program no longer needs. This saves the programmer from manually
freeing ordinary Julia objects, but collecting memory takes work. Temporary
objects can therefore affect performance even when they do not remain alive.
See Julia's [memory management guide](https://docs.julialang.org/en/v1/manual/memory-management/)
for the runtime's memory model.

**GC time** is the measured time attributed to collection. A **GC fraction** is
that time divided by the sample's elapsed time; multiply by 100 to express a
percentage. These are different units. Zero recorded GC time in a short export
does not mean zero allocations: the collector may simply not have needed to
run during that sample. Do not add GC time to elapsed time; the measured elapsed
interval already contains the collection work that took place in it.

## Flame graphs: where sampled work accumulates

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

## Warm code, first calls and state

Julia compiles methods as needed. A first call can include compilation that a
later call avoids. A **warm** benchmark studies repeated execution after
preparation; a **cold** or first-call experiment must explicitly include the
appropriate startup, loading or compilation boundary. Improving warm export
latency does not establish that `using Bibliography` became faster.

Input state also matters. Repeating a mutating operation on the same object may
change what later samples do. PerfChecker distinguishes fresh prepared state
from explicitly reused state. The Bibliography walkthrough explains why its
short CPU and wall-profile operations use verified reusable inputs, while its
benchmarks prepare fresh state. Keep the policy visible when comparing results.

## Read a result across several tools

| Tool or view | Question it answers | Read first | Do not infer |
| --- | --- | --- | --- |
| BenchmarkTools | How long does this operation take, and what does it allocate? | Time distribution, bytes, allocation count, GC time | Time spent in each internal function |
| Chairmarks | What repeated cost does this operation have under this sampling configuration? | Sample timing, bytes, allocations, GC fraction | Identical sampling semantics to another collector |
| CPU profiler | Which call paths appear frequently while profiling execution? | Stack weight and source location | Exact duration or invocation count of every function |
| Wall-time profiler | Which task stacks occupy the observed interval? | Task states and call paths | That every wide branch consumed CPU |
| Allocation profiler | Where do sampled Julia allocations originate? | Bytes or events, type, stack, sampling rate | Total native memory or a proven memory leak |
| Process memory | How does the worker's memory envelope change? | Counter definition, before/after, scope | That the endpoint delta equals all bytes allocated |
| Static analyzer | What potential code issue deserves investigation? | Diagnostic, source and analysis assumptions | A measured number of nanoseconds saved |

The [check catalog](../reference/checks.md) explains these collectors individually.
VS Code, Oxygen, Pluto and the REPL present the same saved evidence; changing
interface does not change the meaning of the measurement.

## Try it with Bibliography

Open [the version gallery](../interfaces/visualization.md) and choose **Export ·
time**. Inspect a point and read its version and unit. Switch to **Export ·
allocated bytes** to ask whether the memory cost follows the same pattern.
Switch to **Export · sample distribution** to examine variation hidden by the
summary curve, then **Export · change from 0.1.0** for the relative difference.

Before calling a change a regression, check the source and dependency revisions,
available workloads, input contract and correctness result. A negative relative
change means a decrease for these cost metrics. It is not automatically a pass:
the comparison still needs a declared acceptance policy. Follow the
[complete walkthrough](../tutorials/bibliography.md) to reproduce the measurements
and the fixed-dependency comparison that investigates a specific export change.
