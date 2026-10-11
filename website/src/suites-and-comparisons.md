# Suites and comparisons

- A **workload** is one operation with its inputs.
- A **suite** groups workloads with the package versions and tools needed to repeat them.
- A **plan** lists the individual measurements before any worker starts.
- A **run** is the saved result of executing a plan.
- A **comparison** is the change from a chosen reference, with optional pass/fail limits.

```@raw html
<a id="A-concrete-example:-Bibliography"></a>
<a id="Start-with-the-code-you-already-have"></a>
```

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

```@raw html
<a id="Follow-one-experiment-through-the-interfaces"></a>
```

## Interfaces do not change meaning

The Julia API, VS Code, Oxygen and Pluto select what to run and read the same saved results. Makie renders them. Choose an interface for convenience, not for a different measurement.


## Recorded examples

```@raw html
<figure class="doc-screenshot">
<iframe class="doc-interactive" src="./examples/bibliography/history/export-time.html" title="Bibliography export medians across nine tagged versions" loading="lazy" sandbox="allow-scripts allow-same-origin allow-downloads"></iframe>
<figcaption>Native interactive export of medians from 100 samples per tag. Windows · Julia 1.13.0 · one worker thread. Inputs match; dependency revisions follow each tag. Values are in nanoseconds (1,000 ns = 1 µs).</figcaption>
</figure>
<p><a href="./examples/bibliography/history/export-time.html">Open the interactive export</a> · <a href="./examples/bibliography/history/export-time.json" download>Download the serialized plot and source revisions</a></p>
```

```@raw html
<a id="Continue-from-here"></a>
```

## Next

[Define a suite](software-suites.md) and add a candidate revision to compare.
