# Makie

PerfCheckerMakie renders saved measurements as Makie figures and interactive
HTML. Rendering does not repeat the workload.

```@raw html
<a id="Makie-and-interactive-plots"></a>
```

```@raw html
<a id="Install-the-renderer"></a>
```

## Install the renderer

PerfCheckerMakie **1.0.4** is registered in General and installs by name in a
separate plotting environment:

```julia
import Pkg
Pkg.activate(joinpath(homedir(), ".julia", "environments", "perfchecker-plots"))
Pkg.add(["PerfChecker", "PerfCheckerMakie", "WGLMakie"])
```

The renderer is versioned independently from Core.

On ARM, use [Core 1.1.1 or newer](../guide/overview.md#ARM-installations).

```@raw html
<a id="Open-a-saved-bundle"></a>
```

## Open a saved bundle

Replace the path with a bundle printed by your completed suite run:

```julia
using PerfChecker, PerfCheckerMakie, WGLMakie

bundle = read_run_bundle("perf/results/ACTUAL-RUN/bundles/ACTUAL-BUNDLE")
catalog = plot_catalog(bundle)
foreach(entry -> println(entry["id"], " · ", entry["title"]), catalog)
isempty(catalog) && error("This bundle has no supported plots")
plot_id = first(catalog)["id"]
model = performance_plot(bundle, plot_id)
display(performance_figure(model))
```

The catalogue lists views supported by the saved observations: four-metric
benchmark histories, distributions, allocation pies and attribution, CPU,
wall-time and allocation flame graphs, or diagnostic series. A single-version
bundle cannot supply a measured release history. Native TestItem JSON is a
different format and is not accepted as a suite bundle.

```@raw html
<a id="Save-interactive-HTML"></a>
```

## Save interactive HTML

```julia
destination = "saved-performance.html"
ispath(destination) && error("Choose a new export filename")
write(destination, performance_plot_html(model))
```

Open the file in a browser. Point and frame selectors show exact saved values;
zoom, pan and Fit work in the exported views. Normalized charts have metric
toggles, version ranges and CSV/SVG downloads. Flame graphs retain frame
inspection and nesting. Julia's live `DataInspector` callbacks are not exported.

This is native interactive output from the recorded DataStructures model:

```@raw html
<NormalizedMeasurements source="/examples/real-packages/datastructures/normalized.json" html="/examples/real-packages/datastructures/normalized.html" package-name="DataStructures · recorded container measurements" />
```

Changing the view above reads the same saved values. It collects no measurements.

```@raw html
<a id="Normalized-overlay"></a>
```

## Normalized overlay

BenchmarkTools and Chairmarks each overlay **elapsed time, GC, allocated bytes
and allocation count on one ratio axis**.

For each metric, take the minimum sample at each version and divide it by the
smallest of those minima across the measured campaign. Each curve's minimum is
1; a ratio of 1.5 is 50% above that metric's minimum. The reference versions can
differ. A metric that is zero throughout is shown at 1 by convention; missing
observations remain unavailable. Inspect a point for its raw value and unit.

BenchmarkTools GC time is in seconds; Chairmarks GC is a fraction. Keep the
collectors separate. Connecting segments guide the eye between recorded
versions; they do not measure intermediate releases.

```@raw html
<a id="Customize-and-export-Makie-figures"></a>
```

```@raw html
<a id="Models,-bundles-and-static-exports"></a>
```

## Models, bundles and static exports

A **run bundle** contains observations, definitions, provenance and integrity
information. A **plot model JSON** is a presentation of selected observations;
it does not replace the complete bundle or recover omitted measurements.

For static output, install CairoMakie and use its backend:

```julia
using CairoMakie
figure = performance_figure(model;
    figure_kwargs = (size = (1000, 600),),
    axis_kwargs = (backgroundcolor = :white,),
    plot_kwargs = (linewidth = 2,))
saveplot("comparison.svg", figure)
saveplot("comparison.png", figure; px_per_unit = 2)
```

Use fresh filenames. `figure_kwargs`, `axis_kwargs` and `plot_kwargs` target
the figure, axes and primary recipe separately; attributes must suit the chosen
recipe. SVG/PNG exports are static snapshots. Keep the bundle with shared HTML
when the original evidence and provenance are needed.

```@raw html
<a id="Render-a-published-serialized-view-again"></a>
```

::: details Replay downloaded models and supplied examples

The shipped `examples/kitchen-sink/replay.jl` supplies `saved_plot` for a
downloaded plot JSON. In that directory's prepared plotting environment:

```julia
using PerfChecker, PerfCheckerMakie, WGLMakie
include("replay.jl")
model = saved_plot("downloaded-plot.json")
write("replayed.html", performance_plot_html(model))
```

This re-renders existing values; it does not validate the original full bundle.
For a complete saved run, `julia --project=.controller/plots export.jl
results/ACTUAL-RUN exports/history` produces its catalogue, interactive HTML,
plot JSON and terminal text. Prepare with `julia setup.jl plots` first.

Real allocation evidence is available as
`allocation-pie-5fa622ca80b2df9b` in these three renderings:

```@raw html
<p><a href="../examples/real-packages/datastructures-profiles/allocation-pie-5fa622ca80b2df9b.html">Interactive HTML</a> · <a href="../examples/real-packages/datastructures-profiles/allocation-pie-5fa622ca80b2df9b.svg">Makie SVG</a> · <a href="../examples/real-packages/datastructures-profiles/allocation-pie-5fa622ca80b2df9b.txt">UnicodePlots text</a></p>
```

:::

```@raw html
<a id="Available-views"></a>
<a id="Linked-inspection"></a>
```

::: details View controls and shared assets

Allocation pies group sites below 5% of bytes into **Other**. Use
`performance_plot(bundle, pie_id; min_percentage = 2)` to change the threshold,
or `0` to disable grouping.

Flame width is recorded weight and depth is nesting, not chronology. Inspect
the metric and unit, select narrow frames from the frame index, and use Fit
or 0 to restore the full graph. Diagnostic series retain their recorded axes:
payload size, memory observations and instruction counts are not releases.

For several HTML pages, pass both `asset_directory` and `html_directory` to
`performance_plot_html`, then write its returned HTML. Keep the referenced
assets and pages together. Omitting those options produces standalone output.

:::
