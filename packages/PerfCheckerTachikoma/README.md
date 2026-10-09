# PerfCheckerTachikoma

An optional terminal companion for PerfChecker 1.x, built with Tachikoma 2.7
and UnicodePlots 3. This companion is version 1.0.1 and requires Julia 1.10 or
newer. Its source is `packages/PerfCheckerTachikoma` in the PerfChecker repository;
it is not yet a separately registered package.
The qualification lanes target Ubuntu with Julia 1.10 and the current Julia
release. Windows has not been qualified for this companion.

Install from a reviewed checkout under `~/.julia/dev/PerfChecker`:

```julia
using Pkg
Pkg.develop(path=joinpath(homedir(), ".julia", "dev", "PerfChecker"))
Pkg.develop(path=joinpath(homedir(), ".julia", "dev", "PerfChecker",
    "packages", "PerfCheckerTachikoma"))
```

Open a resolved suite without measuring until you press **R**:

```julia
using PerfChecker, PerfCheckerTachikoma
suite = load_software_suite("perf/suite.jl")
model = tui_model(plan_suite(suite; profile=:quick))
tui(model)
```

Use **Up/Down** to move, **Space** to toggle a run, **R** to run exactly the
ordered selection, **C** to cancel, **Tab** to switch selection/results, **P** to
plot completed evidence and **Left/Right** to change the plot. **Q**, Escape or
Ctrl+C requests exit; the interface stays alive until owned measurement-worker
cleanup finishes. A cancelled job cannot be mistaken for a completed measurement.
Feature errors and missing evidence remain visible. No report is saved automatically.

Consult an existing bundle without launching a worker:

```julia
using PerfChecker, PerfCheckerTachikoma
bundle = read_run_bundle("reports/run")
tui(bundle)
```

UnicodePlots provides a text plot for ordinary terminals. To enable optional
raster plots, install and explicitly load the Makie companion and a renderer:

```julia
using Pkg
Pkg.develop(path=joinpath(homedir(), ".julia", "dev", "PerfChecker",
    "packages", "PerfCheckerMakie"))
Pkg.add("CairoMakie")

using PerfChecker, PerfCheckerTachikoma, PerfCheckerMakie, CairoMakie
tui(read_run_bundle("reports/run"))
```

The adapter uses `Makie.colorbuffer` and Tachikoma's `render_rgba!` with real
row-major RGBA bytes. Raster output requires Kitty or sixel support detected by
Tachikoma; otherwise the interface retains its UnicodePlots fallback. This is
an evidence renderer, not an embedded GLMakie window or a new measurement backend.
Plot preparation runs outside `view`, and inspecting or switching plots never
starts a workload.
Text plots adapt to the actual terminal area and keep their axes on separate
rows. A reserved footer identifies the plotted quantity and unit from the
canonical performance model (for example, allocated bytes in `By`), even while
panning. Missing metadata is labeled unknown. If unusual labels still exceed
the area, use **Up/Down** and **h/l** to
pan vertically/horizontally, or **0** to reset. Resizing prepares a new rendering
of the same saved evidence; it does not launch another measurement.

For embedding, construct `tui_model` and use `refresh!` to poll; call `close!`
from `finally` to request cancellation and await cleanup. `tui` forwards
Tachikoma's explicit `io`, `input` and `tty_size` options for isolated terminals.
The tests use `TestBackend` and an injected terminal stream rather than a human
terminal, plus actual isolated allocation workers for run/cancel/cleanup.

Run the companion's ordinary tests with `Pkg.test("PerfCheckerTachikoma")`.
To also verify the optional raster adapter, use a disposable Julia environment
containing the three developed packages above and CairoMakie, then run:

```julia
using PerfCheckerTachikoma
ENV["PERFCHECKER_TACHIKOMA_TEST_PIXELS"] = "1"
include(joinpath(pkgdir(PerfCheckerTachikoma), "test", "runtests.jl"))
```

The optional tests rasterize real measured evidence and verify isolated Kitty
encoding. They do not establish that a particular physical terminal supports
that protocol. The ordinary tests also compare the rendered plot rows at
40×12 and 80×24 cells, including axes, panning and resize behavior.

Upstream API references: [Tachikoma architecture and app](https://github.com/kahliburke/Tachikoma.jl/blob/main/src/app.jl),
[virtual terminal tests](https://github.com/kahliburke/Tachikoma.jl/blob/main/docs/src/testing.md),
[RGBA and graphics protocols](https://github.com/kahliburke/Tachikoma.jl/blob/main/docs/src/canvas.md).
