# PerfCheckerMakie

Native Makie figures and interactive HTML exports for recorded PerfChecker evidence.
Load a Makie backend with `PerfCheckerMakie` to render saved performance plots;
load `WGLMakie` to export an interactive document with
`PerfChecker.performance_plot_html(model)`.

## Installation

PerfCheckerMakie 1.0.1 is registered in General. Use a separate plotting project:

```julia
using Pkg
Pkg.activate("perf/plots")
Pkg.add(["PerfChecker", "PerfCheckerMakie", "WGLMakie"])
using PerfChecker, PerfCheckerMakie, WGLMakie
```

The features described below belong to source version 1.0.4, which is not yet
registered. To reproduce them, use the immutable renderer revision in the
[visualization guide](https://perfchecker.mirageinteractive.fr/dev/interfaces/visualization.html#Install-the-renderer).
The published Core has a [known ARM import limitation](../README.md#arm-compatibility).

## Saved evidence

`observation_plot` builds a native saved-evidence model with explicit numeric or
categorical axes. Use it for request payloads, diagnostic operations, implementation
comparisons and profiler timelines. Supply the measured values, units, collector,
scope and provenance. Unavailable values remain unavailable; the renderer never
substitutes zeros or infers package versions.

Interactive observation plots support point inspection, keyboard navigation,
panel and series filters, recorded-version selection, and model/CSV downloads.
The existing version, distribution, normalization, allocation and flame-graph
models retain their own interactive renderers.

See the [visualization guide](https://perfchecker.mirageinteractive.fr/dev/interfaces/visualization.html)
and [public API](https://perfchecker.mirageinteractive.fr/dev/optional-api/makie/public-api.html)
for installation, examples and API documentation. PerfCheckerMakie has an
independent version; it works with PerfChecker 1.0.1 and later in the 1.x series.
