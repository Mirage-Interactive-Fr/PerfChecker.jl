# Choose an interface

All interfaces read the same saved runs; none of them changes what a measurement means.

- Run one item while editing — [VS Code](vscode.md)
- Select workloads and versions in a browser — [Web interface (Oxygen)](web-studio.md)
- Work from a terminal — [REPL](repl-pluto.md)
- Select suite runs with terminal keys — [optional Tachikoma UI](#Optional-terminal-UI)
- Keep an editable notebook — [Pluto](repl-pluto.md)
- Explore or export measured plots — [Makie](visualization.md)
- Put saved measurements in your own docs — [Documenter](documentation.md)

```@raw html
<a id="What-to-have-ready"></a>
<a id="Which-package-supplies-each-interface?"></a>
```

## Which package supplies it

- **PerfChecker** — Julia API, command line, text REPL.
- **PerfCheckerWeb** — Oxygen studio and HTTP endpoints.
- **PerfCheckerPluto** — notebook controls and Pluto launch.
- **PerfCheckerMakie** — Makie figures; WGLMakie adds interactive HTML.
- **PerfCheckerTachikoma** — optional terminal selection and saved-result views.
- **VS Code extension** — Testing view, commands, investigation panel.

Load the package that supplies the interface. If two interfaces need conflicting dependencies, put them in separate environments and open the same saved run in each.

See [Installation](../guide/installation.md) for what to add.

## Optional terminal UI

PerfCheckerTachikoma is a **1.0.1 source companion**, loaded explicitly rather
than enabled by default. It uses Tachikoma 2.7 and UnicodePlots 3. It is not a
separately registered package; its [source and installation recipe](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/tree/8864d3a0fec4e58390090324955eb8dbcebd5e07/packages/PerfCheckerTachikoma)
are in `packages/PerfCheckerTachikoma` at revision `8864d3a0`.

After preparing that companion and your suite's controller:

```julia
using PerfChecker, PerfCheckerTachikoma
suite = load_software_suite("perf/suite.jl")
tui(tui_model(plan_suite(suite; profile = :quick)))
```

Opening the interface starts no measurement. **Space** selects runs, **R** launches
the selection, **C** cancels and **P** plots completed evidence. To inspect a
saved run without a launch action, use `tui(read_run_bundle(bundle_directory))`.
UnicodePlots is the text fallback; optional Makie raster output needs a terminal
with supported graphics. Controlled terminal-stream and raster tests do not
establish support in every physical terminal, on macOS or on Windows.

### Inspect a saved bundle first

In the prepared companion environment, replace the path with an existing bundle:

```julia
using PerfChecker, PerfCheckerTachikoma
bundle = read_run_bundle("perf/results/bundles/<run-directory>")
tui(bundle)
```

This opens a read-only result model. Press **P** to prepare a plot, then
**Left/Right** to inspect other available views. Read the quantity and unit in
the footer. The available views come from the saved observations; switching
views and resizing the terminal do not collect new evidence.

### Select, run and retain results

For the plan example above, all rows start selected. Use **Up/Down** to inspect
them and **Space** to remove unwanted rows before pressing **R**. The run uses
the selected IDs in their plan order. **Tab** switches between selection and
results, while **C** requests cancellation. Wait for the final status: a
cancelled or unavailable row is not a completed measurement.

To keep the result after closing the UI, retain its model explicitly:

```julia
using PerfChecker, PerfCheckerTachikoma
suite = load_software_suite("perf/suite.jl")
model = tui_model(plan_suite(suite; profile = :quick))
try
    tui(model)
finally
    close!(model)
end
if model.result !== nothing
    paths = write_suite_reports(model.result, "perf/results/terminal-example")
    foreach(println, paths)
end
```

**Q**, **Escape** and **Ctrl+C** request exit and wait for owned worker cleanup.
The interface does not save reports automatically. Choose a fresh export
directory; exporting a completed result preserves its failed or unavailable
rows as well. It saves evidence, not a revised suite definition or a reusable
keyboard selection.

### Text and optional raster plots

UnicodePlots supplies the text view. If a label exceeds the visible area,
**Up/Down** and **h/l** pan the plot; **0** resets it. To request raster rendering,
prepare the [Makie companion](../guide/installation.md#Source-companions-for-1.0.1)
and CairoMakie in the same controller, then load them before opening the bundle:

```julia
using PerfChecker, PerfCheckerTachikoma, PerfCheckerMakie, CairoMakie
tui(read_run_bundle("perf/results/bundles/<run-directory>"))
```

Raster output uses terminal graphics support detected by Tachikoma; an ordinary
terminal retains the text fallback. The [Pluto walkthrough](repl-pluto.md#Pluto)
provides downloadable notebooks when an editable graphical document fits the
experiment better.
