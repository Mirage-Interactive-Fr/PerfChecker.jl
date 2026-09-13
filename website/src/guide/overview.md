# Overview

A test can pass while the code it checks becomes slower. The result is still
correct, but a new temporary array, an extra parse or a different algorithm
may have increased its cost. PerfChecker helps measure those changes and find
where they come from.

It runs existing Julia TestItems or operations defined in a performance suite.
You can compare package releases, Git revisions and Julia runtimes, then open
the saved timings and profiles in the terminal, VS Code, a browser or a notebook.

## Start with one operation

The manual uses Bibliography, a package for importing and exporting
bibliographic entries. We first measure a test that imports an article,
exports it and checks that its title and citation key survive. That gives
us the cost of the whole test.

Next, we measure export alone, with the input prepared before timing starts.
This lets us compare the same operation across versions. We will read its
timings and allocations, profile the calls inside it, and use the comparison
in CI.

Begin with [installation](installation.md), then [measure the test](first-check.md).
The **Next page** links follow this sequence. If you already have a runnable
benchmark, start at [understanding the result](understanding-measurements.md).

## Adapt the example

Replace the Bibliography input and operation with code from your own package.
Keep a check of the result: an optimization should still produce the expected
answer. When you need several workloads or versions, put those choices in a
[suite](../suites-and-comparisons.md).

### Direct `@check`

For an inline experiment, `@check` accepts a preparation block and an operation
to measure. Its [API reference](../reference/api.md) describes the configuration.
`PerfConfig` validates that configuration before execution; the older `Dict`
form is also supported.
The manual uses TestItems and suites because their definitions can also be
selected from the graphical interfaces.

## What runs, and where

The workload, collector and version are separate choices. For example,
`export_bibtex` remains one operation when you switch from timing it to collecting
allocation stacks. You do not need to copy its implementation for each tool.

PerfChecker's **controller** prepares the selected versions, schedules work and
writes reports. A **worker** is a separate Julia process that loads and measures
the target. The interface and plotting code run outside that measurement.
Within the worker, the collector determines the boundary: an operation benchmark
can exclude input preparation, whereas a TestItem measurement includes its setup
and assertions. Startup and compilation can also be measured explicitly.
The [suite chapter](../software-suites.md#Why-the-worker-has-its-own-environment)
explains which dependencies belong in each environment.

## Save a result and reopen it

A **plan** lists the checks you selected. Executing it creates a **run** whose
saved result contains the measurements, source revision, Julia runtime and
measurement settings. A plot reads those saved values. You can reopen the same
run in another interface without executing the workload again.

The interfaces handle the report files for you. If you need to read their JSON
directly, the [format reference](../reference/run-bundles.md) explains the fields
and format-version identifiers such as `schema_version`.

## Explore a larger example

[DataStructures](../real-packages/datastructures.md) compares construction and
use of 35 containers. [Oxygen](../real-packages/oxygen.md) compares HTTP handlers
and adds network measurements. Both include the scripts, saved results and
Pluto notebooks, so you can inspect the figures or run the experiments yourself.

Use the **Interfaces** section to choose where to work, and **Reference** to
look up a function or option. **Further topics** covers native tools, remote
workers and comparisons between machines.
