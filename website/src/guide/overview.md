# Overview

PerfChecker answers four different questions that are often mixed together:

1. **What is being measured?** A stable business feature and a representative workload.
2. **How is it measured?** A benchmark, allocation tracker, profiler, network collector, or provider.
3. **Which implementation is measured?** A release, working tree, branch, tag, commit, or Julia runtime.
4. **How is evidence consumed?** A CI gate, interactive plot, report, documentation block, human review, or agent workflow.

Keeping these axes independent is the central design rule. A feature such as
`import_bibtex` should not be duplicated into names such as
`import_bibtex_allocations` and `import_bibtex_profile` in the user interface.
Those are check types attached to one feature.

## Find your way through the documentation

Start with **Installation**, then **Your first result**: a downloadable test item,
one execution and its output. **Suites and comparisons** explains how to group
workloads and compare versions. **Measurements** explains the numbers and tools.
**Interfaces** lets you choose where to run and inspect those same experiments.

Once the local example works, use **Automation and hosting** to repeat it in CI.
**Advanced experiments** adds runtime and machine comparisons. **Optional advice**
is a separate path; no model is needed to follow any of the tutorials.
**Contracts and API** is a lookup reference, not a prerequisite reading sequence.

## Execution model

PerfChecker has a controller/worker boundary:

| Component | Responsibilities | Included in measurements? |
|---|---|---:|
| Controller | Resolve versions, build plans, schedule jobs, write reports, serve UIs | No |
| Malt worker | Load one target, one workload and one collector | Yes |
| Reporter | Convert bundles into tables, plots, documentation and CI evidence | No |
| Oxygen agent | Lease work from a controller and launch local isolated workers | No |

A worker is fresh for every planned feature/target pair. Startup and compilation
can be measured deliberately, but controller compilation, Makie, Oxygen, Pluto
and VS Code never leak into the timed workload by accident.

## Choose what to measure

### Existing test items

Load PerfChecker and TestItemRunner, then call `run_testitems(pwd())` from your
package root in its prepared test environment. This reuses its `@testitem`
declarations. No generated suite is required; the
[first-result tutorial](first-check.md) shows selection and result inspection.

### Direct `@check`

`@check` is the compact API for a single experiment. `PerfConfig` validates the
configuration before processes start, and the legacy `Dict` form remains
supported. A preparation block creates the input; a second block contains the
operation to measure. For example, import a bibliography during preparation,
then time only its export. The [Julia API](../reference/api.md) documents the
macro and its configuration. The [short Bibliography tutorial](../tutorials/quick-tour.md)
provides a complete operation benchmark through the supplied suite.

### Feature suites

`SoftwareSuite` describes a repeatable set of experiments: which operations,
inputs, collectors and versions to use. For example, compare Bibliography export
time and allocations across nine releases with the same input. It produces a
plan and saved results. Define one when that additional configuration is useful;
it is not something to install before measuring an item or using `@check`.

## Save a result and reopen it

The saved result contains your measurements, the code version, the Julia runtime
and the measurement settings. You can reopen it in another interface without
running the benchmark again. Its plots display those saved values.

You will mainly work with a **plan** (the selected checks), **progress** (what is
running), a **saved run** (measurements and context) and **plots** (views of those
measurements). The interfaces handle their file formats for you.

If you write a tool that reads the JSON files directly, see the
[format reference](../reference/run-bundles.md). It explains identifiers such as
`schema_version`, which tell software how to read a file and do not affect which
tests you select.

## What to read next

- [Install PerfChecker](installation.md).
- Follow the [short Bibliography tutorial](../tutorials/quick-tour.md).
- Measure [your first test item](first-check.md).
- Understand [suites and comparisons](../suites-and-comparisons.md).
- Browse the [measurement catalog](../reference/checks.md).
- Choose an [interface](../interfaces/packages.md).
