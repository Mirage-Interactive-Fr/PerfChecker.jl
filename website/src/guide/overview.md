# Introduction

A test can pass while the code it checks becomes slower. PerfChecker measures that change and helps you find where it comes from.

## The problem

- Unit tests check correctness, not cost.
- A new temporary array, an extra parse or a different algorithm can slow an operation without failing any test.
- Two runs on the same machine differ anyway, so a single number proves nothing.

PerfChecker measures the same operation repeatedly, records the distribution, and keeps the conditions of the run with the numbers.

## The workflow

```text
choose a workload → measure it → save the result → compare or profile it
```

- **Workload** — one operation and its inputs, or an existing test item.
- **Collector** — what to record: time, allocations, a CPU profile, network counters.
- **Run** — the saved result, with source revision, runtime and settings attached.
- **Comparison** — the change from a reference, with optional pass/fail limits.

Every interface reads the same saved run. Changing from the REPL to VS Code to the browser does not re-measure anything.

## What runs, and where

- The **controller** is your Julia process. It prepares versions, schedules work and writes reports.
- A **worker** is a separate Julia process that loads and measures the target.
- The collector decides the measurement boundary inside the worker.
- Interface and plotting code never runs inside the worker.

A whole-test measurement includes setup and assertions. An operation benchmark can exclude input preparation. Both are useful; pick the boundary that matches your question.

## Start

- [Installation](installation.md)
- [Quickstart: measure a test](first-check.md)
- [Measure an operation](../tutorials/quick-tour.md)
- [Understand the result](understanding-measurements.md)

## Measure safely

- Keep a correctness check. A faster wrong answer is not an improvement.
- Save the run. Reports record the source, environment and settings needed to judge comparability.
- Do not promote a planned feature or platform to a real one. If a tool is unavailable, the report says `unavailable` — not zero.

```@raw html
<a id="Overview"></a>
<a id="Start-with-one-operation"></a>
<a id="Adapt-the-example"></a>
<a id="Save-a-result-and-reopen-it"></a>
<a id="Explore-a-larger-example"></a>
```
