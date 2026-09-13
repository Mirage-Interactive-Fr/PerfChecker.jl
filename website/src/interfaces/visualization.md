# Makie and interactive plots

PerfCheckerMakie turns saved measurements into figures. Version curves show
changes across releases, distributions show the variation between samples, and
relative deltas compare a result with a baseline. For an introduction to wall
time, GC and flame graphs, see
[Understand performance measurements](../guide/understanding-measurements.md).

## Compare nine Bibliography versions

Compare 0.1.0, 0.2.0, 0.2.5, 0.2.10, 0.2.15, 0.2.20, 0.3.0, 0.3.1 and 0.4.0
on the same BibTeX input. Start with the four overlaid metrics, then switch to export timing, allocated bytes, import
timing, sample distributions and changes relative to 0.1.0. Each graph comes
from an actual recorded run; the values and pinned revisions are downloadable.
This campaign ran on Windows with Julia 1.13.0 and one worker thread.

```@raw html
<HistoricalPlots />
```

The dependency revisions follow explicit historical pairings, with a corrected
compatible BibParser pin for 0.2.10 as explained in the walkthrough.
These curves therefore compare the versioned package stack. To isolate one code
change while holding dependencies fixed, follow the
[streaming export comparison](../tutorials/bibliography.md#Extend-to-historical-comparisons).

The availability table identifies workloads absent from older releases. Their
points are omitted from the curves. Downloads contain the measurements and a
digest of the source manifest; local paths and machine identifiers are removed.

### Read the recorded evolution

Version positions are equally spaced; they do not represent elapsed calendar
time between releases. The combined plot uses a linear ratio axis, with each
metric's minimum at 1. The individual positive-valued version curves use Makie's
`pseudolog10` vertical scale, which compresses larger values. For those individual
views, read the tick labels or the value table instead of estimating a percentage
from pixel distances.

In this campaign, export allocations rise from **4,480 bytes at tag 0.1.0 to
8,352 bytes at tag 0.4.0**. The median export timings are **13.15 µs and 15.45 µs**
respectively. Allocated bytes nearly double, while the median time increases
by about 17%. Time and allocated bytes therefore tell different parts of the
story. Inspect the intermediate releases and sample distributions to choose
a pair to investigate, then repeat it with your own inputs.
These values describe the one-article export workload and its resolved
dependencies; other Bibliography operations may evolve differently.

The streaming-export example uses later development commits. A package can
still declare version `0.4.0` after the `v0.4.0` tag was created, so its declared
version alone does not identify its code. The gallery measures the tag at
`73bae9d`, while the quick suite uses the later commit `575ec81`. Their different
allocation results are not interchangeable. Keep the full source revision when
comparing or reporting a result.

The usual Makie 2D zoom and Julia `DataInspector` callbacks require a live Julia
session. The standalone export adds its own offline point inspection, using
WGLMakie tooltips and JavaScript point selection. This distinction also applies to
HTML plots opened by the web studio. See the
[WGLMakie export documentation](https://docs.makie.org/stable/explanations/backends/wglmakie).

To export your own completed timing run, use the web controller environment
prepared in the walkthrough. Run these commands from `examples/bibliography/`
after `setup.jl` and `setup.jl web`. Replace `<history-run>` with the directory
printed by `history.jl run`:

```sh
julia --project=.controller/core history.jl plan
julia --project=.controller/core history.jl run
julia --project=.controller/web export-history.jl results/<history-run> generated/history
```

## Build a plot from a saved run

For stack-based views, open the [recorded Bibliography flame graphs](../guide/understanding-measurements.md#Inspect-three-recorded-Bibliography-profiles).
Switch between CPU samples, wall-time task samples and allocation bytes to read
the different weights. Those profiles describe one development revision; use
the historical gallery above for comparisons across releases.

Plots are built from a presentation-neutral grammar. `plot_catalog` discovers
valid views for a bundle, `performance_plot` materializes one view model, and
renderers turn that model into Makie figures, interactive HTML, terminal plots,
or documentation blocks.

After a [Bibliography suite benchmark](../tutorials/quick-tour.md#2.-Run-just-the-export-check),
keep the printed report directory. Start Julia in the prepared web environment
(`julia --project=.controller/web`, from `examples/bibliography/`). Enter that
report directory when prompted below. This avoids guessing a run ID:

```julia
using PerfChecker, PerfCheckerMakie, WGLMakie

println("Paste the Reports directory printed by the completed suite run:")
report_directory = readline()
bundle_directories = filter(isdir,
    readdir(joinpath(report_directory, "bundles"); join=true))
bundle_directory = first(sort(bundle_directories))
bundle = read_run_bundle(bundle_directory)
catalog = plot_catalog(bundle)
model = performance_plot(bundle) # Default: overlaid collector metrics / minimum
figure = performance_figure(model)
html = performance_plot_html(model)
```

`bundle_directories` lists the bundle folders in that report; choose another
entry if the run contains several. `figure` displays the selected plot in Julia;
`html` contains the standalone HTML representation. A native-item
`testitems.json` is not a suite bundle and is not accepted by this API.

## Available views

The default BenchmarkTools and Chairmarks view overlays elapsed time, GC,
allocated bytes and allocation count on one **ratio axis**. For each metric,
take the minimum sample at each version and divide by the smallest of those
values across the compared versions. Each curve therefore has its own optimum
at **1**; 1.5 means 50% more than that metric's minimum. The optima need not belong
to the same version. Tagged releases and development targets can share this plot.
These minima describe recorded samples, not a confidence interval or a CI verdict.

BenchmarkTools records GC time; Chairmarks records the fraction of time spent
in GC. They retain their distinct definitions and are never merged into one curve.
When a metric is zero throughout, it is shown at 1 as unchanged, explicitly by
convention. A nonzero value divided by a zero reference has no finite ratio and
leaves a gap. Missing measurements remain missing.

Use `performance_plot(bundle; statistic=:median)` to normalize medians instead,
or `reference_version=:latest` (or a specific version label) to select a target
as the denominator. The minimum remains the default. **Individual absolute plots
remain available** in the catalogue and interface selectors; their original units
are useful when deciding whether a measured difference matters.

A version curve's vertical axis carries a measurement unit. Its points summarize
the available observations for each version; a connecting segment is a visual
guide, not a measurement of intermediate releases. A distribution keeps the
individual samples visible. The delta view computes `(candidate - baseline) /
baseline`: for time and allocated bytes, a negative value means a reduction.
When the baseline is zero, a relative change is undefined.

A flame graph has a different meaning. Nested rectangles show call paths and
width shows their accumulated weight. CPU, wall-time and allocation flame graphs
can look similar while weighting different observations. Read the metric, unit,
source filter and colour legend before interpreting a wide branch; it is not a
timeline or a list of exact function durations.

| Family | Views |
| --- | --- |
| Benchmarks | normalized overlay, individual trajectories, sample distributions, candidate delta, metric trade-off |
| Allocations | percentage pie, totals by file, hotspots by line, line heatmap, allocation flame graph |
| Profiles | CPU flame graph, wall-time flame graph |

Every catalog entry is derived from evidence actually present in the bundle.
An unavailable collector therefore does not produce an empty decorative chart.

Allocation pies group source lines contributing **less than 5% of allocated
bytes** into **Other allocation sites**. A line at exactly 5% keeps its own legend
entry. The combined slice preserves the total; the line table and flame graph
remain available to inspect the small sites individually. To change the threshold,
use `performance_plot(bundle, pie_id; min_percentage=2)` or set it to `0` to
disable this grouping. `top=40` still limits the total number of legend entries.

## Linked inspection

Standalone HTML overlays use SVG curves with metric toggles, keyboard-accessible
points and a raw-value table; they work without a running Julia process.
The same model can be rendered as a Makie figure in Julia.
Other standalone HTML exports support point inspection for timing distributions and
version series, and inspection of SVG flame cells. Other Makie views can use
Julia's `DataInspector` in a live session; that inspector is not preserved by a
static HTML export.
For flame graphs, hover or keyboard focus reveals the complete call path, source
file and line, absolute weight, and percentage. Colours distinguish ordinary
frames from allocation-only evidence and, when present, runtime dispatch,
inference instability, and garbage collection. A visible legend documents the
active colour semantics.

Allocation analysis follows a useful drill-down path:

```text
percentage slice → file → line hotspot → allocation stack → source
```

Filters and selected versions are serializable so another interface can reopen
the same view. Static Makie export remains available for CI artifacts and print
documentation.

```@raw html
<DocMedia src="/examples/bibliography/history/export-memory.png" alt="Measured Bibliography export allocation curve across nine tags from 0.1.0 to 0.4.0" caption="The recorded export allocations across nine tagged versions. This static capture preserves the same values as the interactive allocated-bytes view above; a profile is needed to locate the code responsible for the differences." />
```

## Rendering boundary

Makie, WGLMakie, and Pluto run in the controller. They are not installed into
every target worker merely because a result is visualized. A worker receives the
target package, workload, and the selected collector only; visualization happens
after the result crosses the run-bundle boundary.
