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
separately registered package; its [source and installation recipe](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/tree/1a7577da782ba8676683f3ceefcb8dccf055afe5/packages/PerfCheckerTachikoma)
are in `packages/PerfCheckerTachikoma` at revision `1a7577da`.

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
