```@raw html
<a id="Read-the-numbers-in-either-interface"></a>
```

# REPL and Pluto

Use the REPL for a short command-driven session. Use Pluto to keep an editable notebook with controls and plots.

```@raw html
<a id="REPL-workflow"></a>
```

## REPL

From `examples/bibliography/`:

```sh
julia --startup-file=no --project=.controller/core repl.jl
```

Or drive the API yourself:

```julia
using PerfChecker

suite = load_software_suite("suite.jl")
selected, overrides = configure_suite_repl(suite; profile = :quick)
result = run_suite_repl(selected; overrides, strict = false)
```

The configurator filters packages, features, check types and targets. It prints the resolved plan before running.

```@raw html
<a id="Use-a-saved-suite-bundle,-as-loaded-in-the-plotting-tutorial."></a>
```

For terminal-native summaries, add UnicodePlots to the controller:

```julia
using UnicodePlots
bundle = read_run_bundle(bundle_directory)
plot_id = first(plot_catalog(bundle))["id"]
terminal_plot(bundle, plot_id)
```

Terminal plots are a compact fallback. They do not replace hover, linked selection or source drill-down in the graphical views.

```@raw html
<a id="Pluto-dashboard"></a>
```

## Pluto

For the **1.0.1 candidate** integrated into VS Code, follow
[Pluto notebooks in VS Code](vscode-workflows.md#Pluto-notebooks-in-VS-Code).
It covers creating and reopening `.jl` notebooks, separate environments,
Launch/Cancel, reactive cell edits, saved reports and session controls. Its
release and native qualification are still in progress. The standalone Pluto
workflow below remains available with the public core and companion.

Download the runnable notebook:

```@raw html
<p><a href="../examples/bibliography/pluto/notebook.jl" download="notebook.jl"><strong>Download the Bibliography notebook (.jl)</strong></a></p>
```

Save it in `examples/bibliography/` and launch it:

```sh
julia --startup-file=no setup.jl pluto
julia --startup-file=no --project=.controller/pluto pluto.jl
```

The notebook has explicit **Launch**, **Cancel**, **Refresh** and **Save** controls. Opening it, changing a selector or reloading the page starts no measurement. Pluto still evaluates reactive Julia cells; inspect unfamiliar notebook source before opening it in a trusted environment.

The download is the notebook's Julia source, including its cells and cell order.
Use the copy shipped with the documentation version you are reading, alongside
that checkout's example files. A screenshot is a recorded result, not a runnable
notebook. If the first cell asks for `.controller/pluto/Project.toml`, check that
you saved `notebook.jl` in `examples/bibliography/` and ran the setup command
there. Reopen that file after correcting its location; changing the directory
does not recreate a measurement.

For HTTP workloads, download the separate Oxygen notebook:

```@raw html
<p><a href="../examples/real-packages/oxygen-notebook.jl" download="oxygen-notebook.jl"><strong>Download the Oxygen notebook (.jl)</strong></a></p>
```

Save it in `examples/kitchen-sink/`, run `julia --startup-file=no setup.jl pluto`
there, then open it in that controller's Pluto session. Its first cell uses
`.controller/pluto` relative to the example directory; `PERFCHECKER_EXAMPLE_ROOT`
can explicitly select that directory when the notebook is stored elsewhere.
The notebook separates an in-process HTTP feature from actual socket traffic,
checks the response oracle, and reads the selected version history. Follow the
[Oxygen walkthrough](../real-packages/oxygen.md) for the workload boundaries and
saved figures.

To generate a notebook for your own suite:

```julia
using PerfChecker, PerfCheckerPluto

notebook = prepare_pluto_dashboard(
    "perf/PerfCheckerDashboard.jl";
    suite_path = "perf/suite.jl",
    factory = :build_suite,
    project = dirname(Base.active_project()),
)

launch_pluto_dashboard(notebook)
```

The controller environment must contain PerfChecker, PerfCheckerPluto, PlutoUI and the collectors the suite uses.

Measurements run in fresh workers. The notebook shows their status and result rows. Commit a generated notebook only when it is meant to be a maintained interface; otherwise regenerate it.


## Recorded examples

```@raw html
<p><a href="../examples/bibliography/pluto/notebook.jl" download="notebook.jl"><strong>Download the runnable Pluto notebook</strong></a></p>
```

```@raw html
<DocMedia src="/examples/bibliography/pluto/completed.png" alt="Pluto displaying a completed Bibliography export check and saved reports" caption="Actual Bibliography execution through Pluto: explicit launch, progress, saved report and completed result. The walkthrough uses the same workload in each interface." />
```

## Next

[Plots](visualization.md) explores saved bundles visually.
