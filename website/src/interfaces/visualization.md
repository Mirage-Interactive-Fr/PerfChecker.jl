```@raw html
<a id="Makie-and-interactive-plots"></a>
```

# Plots

PerfCheckerMakie turns saved measurements into figures. Every view is built from a saved run; none of them re-measures.

## Build a plot from a saved run

Start Julia in the prepared web environment from `examples/bibliography/`:

```julia
using PerfChecker, PerfCheckerMakie, WGLMakie

bundle_directory = "results/<run>/bundles/<bundle>"  # printed by the suite run
bundle = read_run_bundle(bundle_directory)
catalog = plot_catalog(bundle)
model = performance_plot(bundle)
figure = performance_figure(bundle)
html = performance_plot_html(model)
```

- `plot_catalog` lists views that the bundle actually supports. Missing collectors produce no empty chart.
- `performance_plot` returns a presentation-neutral model.
- `performance_figure` renders it with Makie; `performance_plot_html` exports standalone HTML.

A native-item `testitems.json` is not a suite bundle and is not accepted here.

## Customize and export Makie figures

This section uses the **PerfCheckerMakie 1.0.1 development candidate**:
`figure_kwargs`, `axis_kwargs`, `plot_kwargs`, `saveplot`, `checkres_figures`
and the export behavior below are additions to that companion. The public
1.0.0 companion still provides `performance_figure` and saved-model rendering;
installing registered PerfChecker 1.0.0 does not supply these newer methods.
For the candidate, use the [repository-subdirectory installation](../guide/installation.md#Optional-packages)
with `subdir = "packages/PerfCheckerMakie"` and the reviewed source revision
`f0af0831499cbd05a43eb44974164309f0553e82`, whose
[companion source](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/tree/f0af0831499cbd05a43eb44974164309f0553e82/packages/PerfCheckerMakie)
declares version 1.0.1. These candidate instructions do not assume a published
`v1.0.1` tag or a General registration.

Load `PerfCheckerMakie` and a display or export backend. Makie settings have
three explicit namespaces, so a plot's color cannot collide with an axis or
figure setting. User attributes override presentation defaults; collector names
and tags are appended to customized titles and subtitles. Unavailable
measurements remain gaps. Version tick labels default to vertical (`pi/2`).
Collector names appear in titles and tags in subtitles. Bundle rendering
resolves the collector from its measurement definition. For a manually built
model without collector identity, pass `tool="BenchmarkTools"` (or the actual
collector) explicitly; the default says the collector is unspecified.

```julia
using PerfChecker, PerfCheckerMakie, CairoMakie

figure = performance_figure(bundle;
    figure_kwargs = (size = (1000, 600),),
    axis_kwargs = (backgroundcolor = :white,),
    plot_kwargs = (color = :navy,), tags = [:comparison])
saveplot("comparison.svg", figure) # parent directory must exist
saveplot("comparison.png", figure; px_per_unit = 2)
```

`figure_kwargs` go to `Figure`, `axis_kwargs` to its axes, and `plot_kwargs` to
the primary recipe: lines for trajectories, scatterlines for overlays,
boxplot for distributions, barplot for allocations/deltas/flames, pie or
heatmap for their respective views. Inspection overlays and reference lines
retain their own settings. NamedTuples and Symbol-keyed dictionaries are
accepted; invalid attributes produce Makie's normal error. Static SVG/PNG
images do not retain interactive tooltips or measurement provenance.

For legacy `CheckerResult` values, the same attribute bundles are accepted by
`checkres_to_scatterlines`, `checkres_to_boxplots`, `checkres_to_pie` and
`table_to_pie`. `checkres_figures(result, Val(:benchmark))` collects named
one trajectory and four distribution figures; `Val(:chairmark)` uses Chairmarks and
`Val(:alloc)` collects an allocation trajectory and one pie per version.
Select only relevant views with `kinds=[:trajectory]`, `[:distribution]` or
`[:pie]` as supported by that collector.
Distributions default to `times`, `gctimes`, `memory`, `allocs` for BenchmarkTools
and `times`, `gctimes`, `bytes`, `allocs` for Chairmarks. The `bytes_or_memory`
alias is excluded. Select a subset with `metrics=[:times, :allocs]`; the selected
columns must exist in every table, and filenames identify their metric.
BenchmarkTools time and GC time remain nanoseconds; Chairmarks time remains
seconds and its GC column remains a unitless fraction. Memory is bytes and
allocations are counts. No conversion or mixture of these units is performed.

```julia
figures = checkres_figures(result, Val(:chairmark);
    kinds = [:distribution], metrics = [:times, :bytes, :allocs])
paths = saveplot("visuals", figures; format = :png)
```

Collection exports create the explicit directory, normalize labels into
portable filenames, and reject colliding names before writing. Existing
destinations, including symlinks, are preserved by default. Replacement
requires `overwrite=true`; directories are never replaced. Empty/nonfinite
samples render a labeled figure; nonfinite samples are omitted and missing
versions are not converted into zero measurements. A failed collection export
can retain figures completed earlier in the collection.
Custom colors also update allocation legends. If flamegraph colors are
overridden, a visible note explains that colors no longer encode diagnostics;
the measured frame details remain available through inspection.
`suite_dashboard(result; view=:absolute)` displays minimum elapsed time in
seconds. BenchmarkTools nanoseconds are converted for this figure only;
Chairmarks seconds are retained. A legacy collector without known time units
is excluded with a visible explanation. Original samples and summaries remain
unchanged; their raw values may use different collector units.

## Normalized overlay

The default Benchmarks view overlays elapsed time, GC, allocated bytes and allocation count on one **ratio axis**.

- For each metric, take the minimum sample at each version, then divide by the smallest of those minima.
- Each curve has its own optimum at **1**; `1.5` means 50% above that metric's minimum.
- Optima need not belong to the same version.
- BenchmarkTools GC time and Chairmarks GC fraction keep separate definitions and are never merged.
- A metric that is zero throughout is shown at 1 by convention.

Use `performance_plot(bundle; statistic = :median)` to normalize medians, or `reference_version = :latest` to choose a different denominator. Absolute plots in original units stay available.

```@raw html
<a id="Available-views"></a>
```

## View families

- **Benchmarks** — normalized overlay, version curves, distributions, delta, metric trade-off.
- **Allocations** — pie, totals by file, hotspots by line, line heatmap, allocation flame graph.
- **Profiles** — CPU flame graph, wall-time flame graph.

- A version curve's connecting segment is a visual guide, not a measurement of unmeasured releases.
- A delta view computes `(candidate - baseline) / baseline`. Negative means a reduction for time and bytes. A zero baseline makes the change undefined.
- Allocation pies group sites below 5% of allocated bytes into **Other**. Change the threshold with `performance_plot(bundle, pie_id; min_percentage = 2)`, or disable it with `0`.

```@raw html
<a id="Linked-inspection"></a>
```

## Flame graphs

Flame graph width is the selected weight; depth is nesting — not a timeline or a list of exact durations. Read the metric, unit, source filter and legend before interpreting a wide branch.

Standalone HTML keeps point inspection for distributions and version series, and hover or keyboard focus for flame cells. Makie's `DataInspector` needs a live Julia session and is not preserved by a static export.

## Rendering boundary

Makie, WGLMakie and Pluto run in the controller. A worker receives the target package, workload and selected collector only. Visualization happens after the result crosses the run-bundle boundary.


```@raw html
<a id="Compare-nine-Bibliography-versions"></a>
<a id="Read-the-recorded-evolution"></a>
```

## Recorded examples

```@raw html
<HistoricalPlots />
```

```@raw html
<DocMedia src="/examples/bibliography/history/export-memory.png" alt="Measured Bibliography export allocation curve across nine tags from 0.1.0 to 0.4.0" caption="The recorded export allocations across nine tagged versions. This static capture preserves the same values as the interactive allocated-bytes view above; a profile is needed to locate the code responsible for the differences." />
```

## Next

[Documenter](documentation.md) embeds saved measurements in your own documentation.
