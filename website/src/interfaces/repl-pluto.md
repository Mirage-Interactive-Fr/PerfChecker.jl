# REPL and Pluto

Use the REPL for a short command-driven session. Use Pluto to keep an editable notebook with controls and plots.

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

For terminal-native summaries, add UnicodePlots to the controller:

```julia
using UnicodePlots
bundle = read_run_bundle(bundle_directory)
plot_id = first(plot_catalog(bundle))["id"]
terminal_plot(bundle, plot_id)
```

Terminal plots are a compact fallback. They do not replace hover, linked selection or source drill-down in the graphical views.

## Pluto

Download the runnable notebook:

```@raw html
<p><a href="../examples/bibliography/pluto/notebook.jl" download="notebook.jl"><strong>Download the Bibliography notebook (.jl)</strong></a></p>
```

Save it in `examples/bibliography/` and launch it:

```sh
julia --startup-file=no setup.jl pluto
julia --startup-file=no --project=.controller/pluto pluto.jl
```

The notebook has explicit **Launch**, **Cancel**, **Refresh** and **Save** controls. Opening it, changing a selector or reloading the page starts no measurement.

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

```@raw html
<a id="Read-the-numbers-in-either-interface"></a>
<a id="REPL-workflow"></a>
<a id="Use-a-saved-suite-bundle,-as-loaded-in-the-plotting-tutorial."></a>
<a id="Pluto-dashboard"></a>
```
