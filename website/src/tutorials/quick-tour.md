# Bibliography in three small steps

This example measures the export of a one-article bibliography to BibTeX.
The input is prepared before timing starts, so the result gives the cost of
export alone. We will inspect the saved results, run the benchmark, and compare
Bibliography releases using the same input.

To measure a whole test, including preparation and assertions, see
[your first result](../guide/first-check.md).

## 1. Read a measured result

This graph compares **nine tagged versions** of Bibliography. Each point is the
median of 100 export timings. The vertical axis is in microseconds (µs); lower
means less elapsed time for this operation. The version labels are equally
spaced, not a calendar timeline.

```@raw html
<DocMedia src="/examples/bibliography/figures/history-time.svg" alt="Median Bibliography export time across nine tags: 13.15 microseconds at 0.1.0 and 15.45 at 0.4.0, with a 16.9 peak at 0.2.10" caption="Recorded on Windows with Julia 1.13.0 and one worker thread. The same input is used throughout; dependency versions follow each historical package stack. The axis is linear and starts at zero." />
```

The curve is not a steady increase: 0.2.0 is slightly below 0.1.0, while 0.2.10
is above both. This tells you where to investigate. It does not tell you which
source change caused the difference. Open the [interactive version gallery](../interfaces/visualization.md)
to inspect individual values, download the data or switch to allocated bytes.

## 2. Run just the export check

From a PerfChecker checkout, prepare the pinned example once. Use Julia 1.12 or
later; the first command needs Git and network access to prepare dependencies.

```sh
cd examples/bibliography
julia --startup-file=no setup.jl
julia --startup-file=no --project=.controller/core run.jl benchmark Bibliography export_bibtex
```

The last command selects **one package, one workload and one collector**.
Preparation and compilation can take longer than the benchmark. Measurement
uses one worker thread and requests 50 samples, one evaluation per sample.
At the end, the terminal prints the directory containing your saved result:

```text
Reports: .../results/benchmark-<unique suffix>
```

Keep the printed directory. It contains the measurements, source revisions and
environment information needed to reopen the run. This example records timings;
the [comparison tutorial](comparisons.md) shows how to compare two revisions.

To investigate allocations instead of time, keep the same selection and change
only the collector:

```sh
julia --startup-file=no --project=.controller/core run.jl profile_alloc Bibliography export_bibtex
```

Read the [allocation profile](../guide/investigate.md#Inspect-three-recorded-Bibliography-profiles)
to see which call paths allocate objects. CPU samples, allocation bytes and
elapsed timings answer different questions even when they describe the same code.

## 3. Compare versions and inspect the variation

Still in `examples/bibliography/`, inspect the historical plan, then run it:

```sh
julia --startup-file=no --project=.controller/core history.jl plan
julia --startup-file=no --project=.controller/core history.jl run
```

This is a larger run: nine versions and four workloads, measured sequentially.
There are 28 runnable combinations and eight unavailable ones because
`read_and_filter` is not defined in the earlier versions. Unavailable does not
mean slow, failed or zero cost.

```@raw html
<DocMedia src="/examples/bibliography/figures/history-samples.svg" alt="All 900 recorded Bibliography export timings grouped by nine tagged versions, with a median marker for each group" caption="One point per recorded export timing; the dark horizontal marks are medians. Slow observations remain visible. This shows sampling variation, not the order in which requests completed." />
```

The samples explain why the first graph is only a starting point. Small changes
in the median can coexist with overlapping distributions. Repeat an important
comparison on your own inputs and machine before setting a CI threshold.

## Choose your next step

The benchmark has given us timings and allocation measurements for the export.
Next, [read those measurements](../guide/understanding-measurements.md): what a
sample contains, why timings vary, and how allocated memory relates to GC.
The [interface guide](../interfaces/packages.md) has the equivalent controls
for VS Code, Web Studio and Pluto.
