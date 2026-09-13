# DataStructures: from a test to a version history

[DataStructures.jl](https://juliacollections.github.io/DataStructures.jl/stable/)
provides containers such as heaps, counters and circular buffers. Here, a small
event-processing workload exercises three of them. A sorted-vector queue gives
us a deliberately simple alternative with an independently checkable answer.

Read [the example setup](index.md) first. All commands below run from
`examples/kitchen-sink`.

## 1. Check the answer

```sh
julia --project=. test/runtests.jl
julia --project=. items.jl list
julia --project=. items.jl run
```

The ordinary test run checks empty, singleton and larger inputs. Heap and vector
queues must produce the same sorted event sequence. Counter and buffer results
are checked against simple reference calculations. Negative input sizes must
throw an error.

`test/items.jl` also contains a larger event queue tagged `:perf_only`. The
example's ordinary test runner explicitly filters it out; `items.jl run` selects
its `:queue` tag for PerfChecker. A `:test_only` item remains a correctness test.
This reuses TestItems instead of requiring a second language for performance tests.

Measuring a whole test item includes its input generation and assertions. The
suite below gives a narrower measurement boundary when you need one.

## 2. Measure one workload

```julia
using PerfCheckerKitchenSink

case = event_case(Dict("kind" => "heap", "n" => 2048, "seed" => 42))
state = case.prepare()
answer = case.operation(state)
@assert case.verify(state, answer)
```

The runner prepares the state before timing the operation, then verifies the
answer outside the timed region. It checks that the operation preserved its
input, too. Each BenchmarkTools or Chairmarks sample uses fresh state and
`evals=1`, so repeated calls do not quietly benchmark an already-drained queue.

| Workload | Operation inside the measurement | Correctness oracle |
| --- | --- | --- |
| `heap_2048` | Construct and drain a `BinaryMinHeap` | Equal to `sort(input)` |
| `vector_2048` | Sort a vector, repeatedly remove its first event | Equal to `sort(input)` |
| `counter_2048` | Count categories with an `Accumulator` | Equal to independently counted categories |
| `buffer_2048` | Append to a 64-entry `CircularBuffer` | Equal to the last 64 input events |

```sh
julia --project=. measure.jl plan
julia --project=. measure.jl quick
```

`plan` only lists the four checks. `quick` executes them on DataStructures 0.19.6.
Input generation, package resolution and Julia startup are outside the reported
operation timing. The report's overall run duration includes orchestration and
should not be confused with a timing sample.

## 3. Follow eight years of releases

```sh
julia --project=. measure.jl history
```

This selects **15 releases, from 0.11.0 (August 2018) to 0.19.6 (July 2026)**:
four BenchmarkTools workloads and one Chairmarks heap workload per version.
The controller prepares separate target environments; the workload source and
seed remain fixed. All **75 recorded checks passed their correctness oracles**.

| Release | Published | Why keep this point? |
| --- | --- | --- |
| 0.11.0 | 2018-08-07 | Earliest release that passed this example on Julia 1.13 |
| 0.12.0 | 2018-09-11 | New sorted-container iteration protocol and package project file |
| 0.13.0 | 2018-09-21 | OrderedCollections split into a dependency |
| 0.14.0 | 2018-09-24 | Last selected generation before the heap constructor rename |
| 0.15.0 | 2019-01-08 | Old heap constructors deprecated |
| 0.16.1 | 2019-07-05 | Intermediate container generation |
| 0.17.0 | 2019-07-05 | Deprecated APIs removed |
| 0.17.20 | 2020-08-04 | Last release before the 0.18 heap refactor |
| 0.18.0 | 2020-08-17 | Heaps adopt Base ordering; circular-container optimizations |
| 0.18.10 | 2021-08-09 | A point within the long-lived 0.18 series |
| 0.18.13 | 2022-05-24 | A later 0.18 point |
| 0.18.15 | 2023-08-03 | A later 0.18 point |
| 0.18.22 | 2025-03-18 | Last release before 0.19 |
| 0.19.0 | 2025-08-01 | Breaking container APIs and a higher minimum Julia version |
| 0.19.6 | 2026-07-17 | Latest selected release |

Dates are GitHub release publication dates, which can differ from the commit
date. Versions are equally spaced in the plots: the distance between points
does not represent elapsed calendar time. The downloaded values include the dates.

### Keep the operation stable across an API break

Before 0.15, the public min-heap constructor was `binary_minheap(input)`.
The example selects it or `BinaryMinHeap(input)` once when the module loads;
the measured operation still constructs and drains a min-heap in both cases.
The sorted-output oracle is unchanged. This bridges a spelling change without
substituting a modern implementation into an old package.

The [0.18 release](https://github.com/JuliaCollections/DataStructures.jl/releases/tag/v0.18.0)
changed heap ordering and optimized circular containers. The
[0.19 release](https://github.com/JuliaCollections/DataStructures.jl/releases/tag/v0.19.0)
also changed queue and disjoint-set APIs. The present workloads do not exercise
every changed API: a stable counter curve cannot establish that all containers
are unchanged. Compare 0.17.20 with 0.18.0 for the heap transition, and 0.18.22
with 0.19.0 for the next major package generation.

### Where the history stops

`compatibility.jl DataStructures` checks old releases in separate processes,
including empty and singleton cases. **0.9.0 and 0.10.0 fail to load on Julia
1.13** because they define methods for the removed `Base.start` iteration API.
They are omitted, rather than plotted as zero or patched inside the package.
0.11.0 passes. Going further back would require a separate historical-Julia
experiment; mixing that into this curve would change both the package and runtime.

All points here are measured *today* on the same Julia runtime and local machine.
They are not measurements of what a machine running Julia in 2018 achieved.

### Four measurements on one plot

Elapsed time measures how long the operation took. GC time measures the part
attributed to Julia's garbage collector, which reclaims unreachable objects.
Allocated bytes and allocation count measure allocation activity, not the size
of the live heap or total resident memory.

Each curve below uses the minimum sample for each version, divided by that
metric's minimum across versions. Thus each metric has a reference value of
one despite having a different unit. You can hide a curve and inspect its raw
values. A zero GC sample is common for a short operation; it does not prove
that the workload never triggers garbage collection.

```@raw html
<NormalizedMeasurements source="/examples/real-packages/datastructures/normalized.json" figure="/examples/real-packages/datastructures/normalized.svg" package-name="DataStructures" />
```

In this recorded run, the heap's minimum elapsed time changes from **116.1 µs
in 0.17.20 to 91.8 µs in 0.18.0**, while the minimum allocation count stays at
six. This is a useful boundary to investigate alongside the heap refactor.
It is not a controlled attribution to that refactor: repeat the pair, inspect
the distributions and compare the vector control before claiming a speedup.

### Explore the separate curves and distributions

The gallery also retains each measure on its own scale. A distribution exposes
sample variation hidden by one summary value. The version trajectory uses its
documented aggregation; do not assume that its median equals the overlay's
minimum. BenchmarkTools and Chairmarks remain separate measurement definitions.

```@raw html
<PackageGallery package-name="DataStructures" directory="/examples/real-packages/datastructures" />
```

The vector implementation mostly exercises Base Julia, so it also acts as a
control. Changes in its timing across package tags can reflect machine noise
rather than a DataStructures change. Investigate and repeat a suspected
improvement before attributing it to a release.

## 4. Select a smaller question

To rerun only the heap-refactor boundary, keep the standard historical workloads
but limit the two release endpoints:

```sh
julia --project=. measure.jl history 0.17.20 0.18.0
```

For a more specific workload selection, use the plan API:

```julia
using PerfChecker
include("suite.jl")
plan = plan_suite(build_suite(); profile=:historical,
    version_provider=_ -> KITCHEN_VERSIONS)
selected = filter_suite_plan(plan; features=[:heap_2048], backends=[:benchmark],
    from_version=v"0.19.0", to_version=v"0.19.6")
print_suite_plan(selected)
# Explicit execution, after reviewing the selection:
# run_suite_repl(selected; reports="results/selected-heap")
```

Use `measure.jl profiles` for allocation, CPU and wall-time diagnostics on a
larger heap workload. `measure.jl all` opts into all sizes, versions and
collectors: 1,080 checks. There is no reason to run that whole matrix just to
learn how one workload behaves.

Next, [put the same data behind Oxygen routes](oxygen.md), or
[open these results in an interface](interfaces.md).
