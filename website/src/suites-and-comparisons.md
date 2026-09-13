# Suites and comparisons

- A **workload** is one operation with its inputs.
- A **suite** groups workloads with the package versions and tools needed to repeat them.
- A **plan** lists the individual measurements before any worker starts.
- A **run** is the saved result of executing a plan.
- A **comparison** is the change from a chosen reference, with optional pass/fail limits.

## A concrete example

To see how BibTeX export changed between Bibliography 0.1.0 and 0.4.0:

- **Workload** — export the same prepared bibliography.
- **Implementations** — nine tagged versions.
- **Measurements** — elapsed time and allocated bytes.
- **Settings** — one worker thread, 100 samples per version.

Inspect a plan before running it. The plan lists rows and marks unsupported combinations `unavailable` with a reason.

Run one of these before measuring:

- Existing `@testitem` — [Quickstart](guide/first-check.md). Setup and assertions are part of the cost.
- One operation — inline `@check`, with preparation outside the measured expression. See the [Julia API](reference/api.md).
- Several workloads, versions or collectors — [Define a suite](software-suites.md).

## Interfaces do not change meaning

The Julia API, VS Code, Oxygen and Pluto select what to run and read the same saved results. Makie renders them. Choose an interface for convenience, not for a different measurement.


## Recorded examples

```@raw html
<DocMedia src="/examples/bibliography/figures/history-time.svg" alt="Bibliography export timing across nine tagged versions, from 0.1.0 to 0.4.0" caption="Actual recorded measurements: 100 samples per version, Windows, Julia 1.13.0, one worker thread. Each point is a median; lower means less elapsed time." />
```

## Next

[Define a suite](software-suites.md) and add a candidate revision to compare.

```@raw html
<a id="A-concrete-example:-Bibliography"></a>
<a id="Start-with-the-code-you-already-have"></a>
<a id="Follow-one-experiment-through-the-interfaces"></a>
<a id="Continue-from-here"></a>
```
