# Suites and comparisons

PerfChecker measures code you choose. A **workload** is one operation with its
inputs: for example, exporting a Bibliography document containing a fixed set of
entries. A **suite** groups workloads and the settings needed to repeat their
measurements: which package versions to use and which tools should measure them.

A suite is an experiment description. You do not install one to enable
PerfChecker. You can measure existing tests directly or write a single inline
`@check`. A suite becomes useful when you want several operations or versions
to share a repeatable configuration.

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

A plot shows what was measured. A **comparison** asks how a candidate differs
from a chosen reference. Deciding whether that difference is acceptable requires
a policy: which metric matters and how much change is allowed. Finishing a run
does not by itself establish that performance improved or that a release passed.

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

1. [Measure existing test items](test-items.md) to reuse functional tests.
2. [Define custom workloads](software-suites.md) when you need more control.
3. [Compare versions and revisions](tutorials/comparisons.md) with a chosen baseline.
4. [Follow the complete Bibliography example](tutorials/bibliography.md) across interfaces.

[Machine calibration](machine-transfer.md) and [optional advice](advisors.md)
are additional topics once you have measurements you can reproduce and interpret.
