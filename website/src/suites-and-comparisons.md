# Suites and comparisons

A **workload** is one operation with its
inputs: for example, exporting a Bibliography document containing a fixed set of
entries. A **suite** groups workloads and the settings needed to repeat their
measurements: which package versions to use and which tools should measure them.

A suite is useful when several operations or versions share a configuration.
For a single measurement, you can also run an existing TestItem or write an
inline `@check`.

## A concrete example: Bibliography

Suppose you want to understand how BibTeX export changed between Bibliography
0.1.0 and 0.4.0. The experiment needs four choices:

| Choice | In this example |
| --- | --- |
| Workload | Export the same prepared bibliography |
| Implementations | Nine tagged Bibliography versions |
| Measurements | Elapsed time and Julia allocation bytes |
| Execution settings | One worker thread and 100 samples per version |

These choices form the suite's configuration. PerfChecker turns it into a
**plan**, which lists the individual measurements before any worker starts.
You can inspect and filter that plan. Executing it creates a **run**; the run's
saved results can be opened in another interface without measuring again.

The recorded example produced this export-time series:

```@raw html
<DocMedia src="/examples/bibliography/figures/history-time.svg" alt="Bibliography export timing across nine tagged versions, from 0.1.0 to 0.4.0" caption="Actual recorded measurements: 100 samples per version, Windows, Julia 1.13.0, one worker thread. Each point is a median; lower means less elapsed time." />
```

A **comparison** calculates the change from a chosen reference. For example,
a CI check might allow export time to increase by at most 10% while requiring
allocation bytes to stay unchanged. Those limits form the comparison policy;
the historical plot above has no such pass/fail limits.

In this historical example, dependencies evolve with the versions, so the
graph describes the package stacks together. The
[fixed-dependency Bibliography experiment](tutorials/bibliography.md#Extend-to-historical-comparisons)
shows how to focus on one code change instead.

## Start with the code you already have

If your package already has `@testitem` declarations, PerfChecker can discover
and measure them. Their imports, setup and assertions are part of the item cost.
Start with [existing test items](test-items.md); you do not need to duplicate them
in a suite file.

If you want to time only one operation, use the
[inline check API](guide/overview.md#Direct-@check). Put input preparation outside
the measured expression when preparation is not part of the question.

If you want several custom workloads, historical versions or different
collectors, define a [software suite](software-suites.md). It records the
configuration you would otherwise repeat manually. The optional template
generator only writes example configuration files.

A reusable suite with its own implementation and dependencies can be distributed
as an ordinary Julia package exposing that configuration. Its users install the
package through Pkg; they should not need to reconstruct its development folders.

## Follow one experiment through the interfaces

The Julia API, VS Code, Oxygen and Pluto let you select what to run and inspect
results. Makie renders those results. The interface does not change what a
workload means; use matching inputs, versions and measurement settings when
comparing runs.

The [Bibliography walkthrough](tutorials/bibliography.md) follows the same
workloads through preparation, execution, filtering, reports and interfaces.
The [measurement guide](guide/understanding-measurements.md) explains what the
numbers mean.

## Continue from here

Next, [open and adapt the Bibliography suite](software-suites.md). We will
inspect its workload definition, select the export operation and save a result
before adding a candidate revision to compare.
