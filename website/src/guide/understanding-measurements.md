# Understand performance measurements

Suppose exporting a bibliography has become slow. A benchmark can tell us how
long the export takes and how much memory it allocates. A profile can then
show which calls account for those costs. After changing the code, we repeat
the benchmark and check that the exported document is still correct.

The examples below use that export operation to explain timing, allocation
and profiling results. The input is already prepared when timing starts.
Loading Julia, loading Bibliography and constructing the input are measured
separately when we investigate startup latency.

## Wall time: how long the operation takes

**Wall time**, or elapsed time, is the difference between the clock readings at
the start and end of an operation. It includes time spent computing and time
spent waiting within that boundary. In Bibliography's `export_bibtex` benchmark,
the prepared input already exists when the clock starts. In an import benchmark,
reading the fixture is part of the workload. Always read the workload definition
before interpreting the timing.

Time units are easy to confuse: one second is 1,000 milliseconds (ms), one
millisecond is 1,000 microseconds (µs), and one microsecond is 1,000 nanoseconds
(ns). For example, 7,000 ns is 7 µs. Check the unit in the plot label or
measurement definition when comparing outputs from different collectors.

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

A flame graph shows which call paths account for sampled time or allocations.
Wide rectangles have more samples or bytes; rectangles above them represent
nested calls. Once a comparison shows a change worth investigating, use a
profile to find the relevant code.

### Inspect three recorded Bibliography profiles

The [chapter on investigating a change](investigate.md) works through
Bibliography's CPU, wall-time and allocation profiles, including the figures
and the commands to reproduce them.

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

Before treating a difference as a regression, check that the inputs, source and
dependency revisions, measurement settings and correctness checks match the
comparison you intend. A decrease in time is an observation; a CI pass also
requires a declared acceptance policy.

Next, [group workloads in a suite](../suites-and-comparisons.md). The suite
records the inputs, versions and measurement settings used by the example,
so you can repeat the same comparison as your package changes.
