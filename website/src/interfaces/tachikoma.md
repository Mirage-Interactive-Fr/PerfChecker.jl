# Tachikoma

PerfCheckerTachikoma is an optional keyboard terminal interface for suite
selection, progress and saved-result plots. Ordinary text commands are in
[REPL](repl.md).

```@raw html
<a id="Install"></a>
```

## Install

The companion is version **1.0.1** and its [General registration PR #171531](https://github.com/JuliaRegistries/General/pull/171531)
is pending. It is not yet installable by name.
Use its reviewed source revision in a separate controller:

```julia
import Pkg
Pkg.activate(joinpath(homedir(), ".julia", "environments", "perfchecker-terminal"))
Pkg.add(Pkg.PackageSpec(name = "PerfChecker", version = "1.1"))
Pkg.add(Pkg.PackageSpec(
    url = "https://github.com/Mirage-Interactive-Fr/PerfChecker.jl",
    subdir = "packages/PerfCheckerTachikoma",
    rev = "9947de5e4163388c0a14f0d439e6c578a4676597"))
```

After registration merges, `Pkg.add("PerfCheckerTachikoma")` can replace the
source specification. Published Core has a [known ARM import limitation](../guide/overview.md#ARM-installations).

It uses Tachikoma 2.7 and UnicodePlots 3. Loading the companion opens no terminal
and starts no measurement.

```@raw html
<a id="Optional-terminal-UI"></a>
```

```@raw html
<a id="Inspect-a-saved-bundle"></a>
```

## Inspect a saved bundle

```julia
using PerfChecker, PerfCheckerTachikoma

bundle = read_run_bundle("perf/results/ACTUAL-RUN/bundles/ACTUAL-BUNDLE")
model = tui_model(bundle)
println(model.message)
tui(model)
```

Expected message before the interface opens:

```text
Saved evidence; no measurement launched
```

Press **P** to prepare a plot and **Left/Right** to change saved views.
Read the quantity and unit in the footer. This model is read-only and cannot
launch measurements.

```@raw html
<p>The real Bibliography allocation-bundle <a href="../examples/tool-recipes/receipts.json">model receipt</a> records this message, <strong>9 catalogue views</strong> and <strong>worker_started=false</strong>. It verifies model preparation and cleanup, rather than a captured physical terminal session.</p>
```

```@raw html
<a id="Select,-run-and-save"></a>
```

## Select, run and save

Prepare your suite's collectors in the controller, then:

```julia
using PerfChecker, PerfCheckerTachikoma, BenchmarkTools

suite = load_software_suite("perf/suite.jl")
model = tui_model(plan_suite(suite; profile = :quick))
try
    tui(model)
finally
    close!(model)
end
if model.result !== nothing
    foreach(println, write_suite_reports(model.result, "perf/results/terminal-example"))
end
```

All planned rows start selected. Use **Up/Down** to inspect them and **Space**
to deselect rows. **R** launches the selected IDs in plan order.
**Tab** switches selection/results; **C** requests cancellation.
**Q**, **Escape** or **Ctrl+C** requests exit and waits for owned worker cleanup.
Wait for the final status; a cancelled or unavailable row is separate from a
completed measurement.

No reports are saved automatically. The code exports a returned result to a
fresh directory, including failed/unavailable rows, suite reports and bundles.
If no result exists, it writes nothing. Export retains evidence, not a changed
suite or a reusable keyboard selection.

::: details Text and optional raster plots

UnicodePlots is the text fallback. Use **Up/Down** or **h/l** to pan clipped
plots and **0** to reset.

For raster plots, install [PerfCheckerMakie](visualization.md) and CairoMakie
in the same controller, then load them before calling `tui`:

```julia
using PerfCheckerMakie, CairoMakie
tui(bundle)
```

Raster output requires terminal graphics support; otherwise text remains
available. `plot_pixels(bundle, plot_id)` returns RGBA bytes and actual pixel
dimensions through the optional Makie extension. Neither renderer remeasures.
Controlled stream/raster checks do not establish every physical terminal,
macOS or Windows combination.

:::
