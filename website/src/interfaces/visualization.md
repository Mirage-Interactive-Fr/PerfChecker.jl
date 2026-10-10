```@raw html
<a id="Makie-and-interactive-plots"></a>
```

# Plots

PerfCheckerMakie turns saved measurements into figures. Views come from saved run bundles or previously exported plot models; rendering does not re-measure.

The offline controls and exports described here use the **1.0.1 source candidate**
of Core and PerfCheckerMakie. Install both from the same reviewed revision using
the [candidate recipe below](#Customize-and-export-Makie-figures); registered Core
1.0.0 alone does not provide these additions.

## Build a plot from a saved run

Start Julia in the prepared web environment from `examples/bibliography/`:

```julia
using PerfChecker, PerfCheckerMakie, WGLMakie

bundle_directory = "results/<run>/bundles/<bundle>"  # printed by the suite run
bundle = read_run_bundle(bundle_directory)
catalog = plot_catalog(bundle)
[(entry["id"], entry["title"]) for entry in catalog]
isempty(catalog) && error("This bundle has no supported plots")
plot_id = first(catalog)["id"] # replace with another ID from the catalogue
model = performance_plot(bundle, plot_id)
figure = performance_figure(bundle, plot_id)
display(figure)
html = performance_plot_html(model)
```

- `plot_catalog` lists views that the bundle actually supports. Missing collectors produce no empty chart.
- `performance_plot` returns a presentation-neutral model.
- `performance_figure` renders it with Makie; `performance_plot_html` exports standalone HTML.

A native-item `testitems.json` is not a suite bundle and is not accepted here.

Replace the example directory with an actual bundle path printed by
`write_suite_reports`. Read its collector, version labels and units before
selecting another catalogue ID. A single-version bundle supports views of that
version; it cannot supply a measured version history. Choose a saved campaign
bundle with multiple targets to explore evolution across releases.

### Save interactive HTML

`performance_plot_html` returns HTML text; assigning it to `html` does not write
a file. To retain the view from the example above:

```julia
html_path = "saved-performance.html"
(ispath(html_path) || islink(html_path)) && error("Choose a new export filename")
write(html_path, html)
```

Open that file in a browser. Normalized views retain metric toggles, a measured
version range, exact point inspection, zoom and pan. Their SVG and CSV export
controls preserve the values and complete version labels.
On a phone, the normalized chart keeps a 900-pixel viewport: scroll horizontally
and zoom to inspect it. It does not shrink every label into the screen width.

Series, distributions, version deltas, time/allocation tradeoffs and allocation
file, line, heatmap and pie views retain offline inspection through the point
index and native click tooltips.
Use **Fit**, **+** and **−** to change the view, or focus the plot and use
the **+**, **−** and **0** keys; **0** fits the complete figure. Shift-drag pans a zoomed
view. The point index selects an actual recorded point, including coincident
observations; it does not interpolate between versions. The JSON download
retains the plot model. On narrow screens, **Fit** shows the complete figure;
zoom in to read dense labels and scroll inside the frame. Flame graphs retain their own pointer and
keyboard inspection.

These exported controls work without a running Julia session. Julia
`DataInspector` callbacks are not exported. Keep the original bundle alongside the HTML when
sharing evidence: the figure is a presentation of that bundle, not a replacement
for its provenance. See the [recorded examples](#Recorded-examples) for an
existing multi-version result and the [Pluto walkthrough](repl-pluto.md#Pluto)
for downloadable notebooks.

For several WGL plots, share assets instead of embedding them in every file:

```julia
html_directory = "published-plots"
mkpath(html_directory)
html = performance_plot_html(model;
    asset_directory = joinpath(html_directory, "assets"),
    html_directory = html_directory)
write(joinpath(html_directory, "result.html"), html)
```

Pass both directory options together. The function writes assets and returns
HTML; the caller saves the page. Deploy or move the pages and assets together,
preserving their relative layout. Normalized and flame views remain compact
standalone documents.

### Render a published serialized view again

The real-package galleries also publish plot JSON alongside their SVG exports.
The shipped `examples/kitchen-sink/replay.jl` recipe restores those presentation
models with `saved_plot`. From `examples/kitchen-sink/`, prepare the optional
plot environment and start Julia:

```sh
julia --startup-file=no setup.jl plots
julia --startup-file=no --project=.controller/plots
```

```julia
using PerfChecker, PerfCheckerMakie, WGLMakie
include("replay.jl")
source = "../../website/src/public/examples/real-packages/datastructures/normalized.json"
model = saved_plot(source)
destination = "datastructures-saved-view.html"
(ispath(destination) || islink(destination)) && error("Choose a new export filename")
write(destination, performance_plot_html(model))
```

This is a new HTML rendering of the same serialized values. A plot JSON is not
a complete run bundle: it cannot establish the integrity of the original bundle
or recover omitted measurements. The recipe is shipped example code; the HTML
renderer is the public `performance_plot_html` API.

To refresh the documentation's selected native examples, use the prepared plot
environment:

```sh
julia --startup-file=no --project=.controller/plots publish-evidence.jl --interactive
```

The flag renders 34 guided real-package views across all twelve plot families,
plus six measured Bibliography views. Comparison examples use distinct recorded
versions; the single-version profiles show attribution. Other catalogue entries,
including patch windows, retain their SVG and JSON. WGL views share local assets
in `examples/plot-assets` to avoid repeating large JavaScript modules. Keep that
directory and the pages in the same relative layout when copying these published
exports. To create one self-contained file instead, call `performance_plot_html`
without directory options. The recorded JSON and SVG remain unchanged. To refresh
only the five published normalized views and their two HTML aliases, use
`--interactive-normalized` instead. This mode requires the renderer and publication
recipe to be committed in the same checkout and prints that commit and tree before
rendering. It preserves the catalogues, other HTML exports and shared assets.
With neither flag, the command only refreshes the aliases and downloadable
notebooks and does not load WGLMakie. The documentation embeds the same HTML file
that can be opened separately. Views without a published HTML export show their
actual static SVG instead.

## Customize and export Makie figures

This section uses the **PerfCheckerMakie 1.0.1 development candidate**:
`figure_kwargs`, `axis_kwargs`, `plot_kwargs`, `saveplot`, `checkres_figures`
and the export behavior below are additions to that companion. The public
1.0.0 companion still provides `performance_figure` and saved-model rendering;
installing registered PerfChecker 1.0.0 does not supply these newer methods.
For the candidate, use the [repository-subdirectory installation](../guide/installation.md#Optional-packages)
with `subdir = "packages/PerfCheckerMakie"` and the reviewed source revision
`8864d3a0fec4e58390090324955eb8dbcebd5e07`, whose
[companion source](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/tree/8864d3a0fec4e58390090324955eb8dbcebd5e07/packages/PerfCheckerMakie)
declares version 1.0.1. These candidate instructions do not assume a published
`v1.0.1` tag or a General registration.

Install Core and the companion from the same source revision in a dedicated
environment. The candidate companion requires Core 1.0.1 or later; leaving a
registered Core 1.0.0 beside it does not satisfy that contract:

```julia
using Pkg
repository = "https://github.com/Mirage-Interactive-Fr/PerfChecker.jl"
revision = "8864d3a0fec4e58390090324955eb8dbcebd5e07"
Pkg.add([
    PackageSpec(url = repository, rev = revision),
    PackageSpec(url = repository, rev = revision, subdir = "packages/PerfCheckerMakie"),
])
```

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

bundle = read_run_bundle("results/<run>/bundles/<bundle>")
catalog = plot_catalog(bundle)
isempty(catalog) && error("This bundle has no supported plots")
plot_id = first(catalog)["id"]
figure = performance_figure(bundle, plot_id;
    figure_kwargs = (size = (1000, 600),),
    axis_kwargs = (backgroundcolor = :white,),
    plot_kwargs = (color = :navy,), tags = [:comparison])
saveplot("comparison.svg", figure) # parent directory must exist
saveplot("comparison.png", figure; px_per_unit = 2)
```

Use a fresh output filename, inspect the exported labels and units, then adjust
one attribute group at a time. These calls write the figure, not the suite,
controller settings or measurement bundle. Preserve the Julia customization
snippet if it should become a repeatable report; loading the SVG or PNG does
not recover those settings.

`figure_kwargs` go to `Figure`, `axis_kwargs` to its axes, and `plot_kwargs` to
the primary recipe: lines for trajectories, scatterlines for overlays,
boxplot for distributions, barplot for allocations/deltas/flames, pie or
heatmap for their respective views. Inspection overlays and reference lines
retain their own settings. NamedTuples and Symbol-keyed dictionaries are
accepted; invalid attributes produce Makie's normal error. Static SVG/PNG
images do not retain interactive tooltips or measurement provenance.

For legacy `CheckerResult` values, the same attribute bundles are accepted by
`checkres_to_scatterlines`, `checkres_to_boxplots`, `checkres_to_pie` and
`table_to_pie`. `checkres_figures(result, Val(:benchmark))` returns a named
trajectory and four named distributions; `Val(:chairmark)` uses Chairmarks and
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
overridden, a visible note explains that colors no longer encode diagnostics.
Frame inspection is available in a live Makie figure or the public HTML export;
a static SVG or PNG does not retain those callbacks.
`suite_dashboard(result; view=:absolute)` displays minimum elapsed time in
seconds. BenchmarkTools nanoseconds are converted for this figure only;
Chairmarks seconds are retained. A legacy collector without known time units
is excluded with a visible explanation. Original samples and summaries remain
unchanged; their raw values may use different collector units.

## Normalized overlay

The default Benchmarks view overlays elapsed time, GC, allocated bytes and allocation count on one **ratio axis**.

- For each metric, take the minimum sample at each version, then divide by the smallest of those minima.
- Each curve's lowest observed value is **1**; `1.5` means 50% above that metric's minimum.
- The minima need not belong to the same version.
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
- A time/allocation tradeoff preserves the recorded numbers and their separate units. Read `time_unit` and `allocation_unit` in the model options: a value of `400` recorded in nanoseconds remains `400 ns`. The catalogue omits ambiguous or incompatible metric pairs while keeping their separate series and distributions. Older serialized tradeoffs without these unit fields render as **unit unspecified**; their historical combined label does not prove a conversion to seconds.
- Allocation pies group sites below 5% of allocated bytes into **Other**. Change the threshold with `performance_plot(bundle, pie_id; min_percentage = 2)`, or disable it with `0`.

```@raw html
<a id="Linked-inspection"></a>
```

## Flame graphs

Flame graph width is the selected weight; depth is nesting — not a timeline or a list of exact durations. Read the metric, unit, source filter and legend before interpreting a wide branch.

Use the frame index to inspect an exact recorded frame, including one too narrow
to click. The readout retains its complete path and weight. Click a wider frame
for its tooltip, zoom with **+** or **−**, drag the background to pan, and use
**Fit** or **0** to restore the complete graph. The JSON and SVG downloads retain
every recorded frame; the SVG also includes the diagnostic legend. Colors
identify frame categories, not performance gains. The default native figure
height follows the nesting depth; an explicit `figure_kwargs.size` overrides it.

These HTML controls work without Julia. Makie's `DataInspector` needs a live
Julia session and is not preserved by an exported file. See the
[DataStructures profiles](../real-packages/datastructures.md#Explain-the-cost)
for single-version attribution, alongside the separate measured release history.

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
