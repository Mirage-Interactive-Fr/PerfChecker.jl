# REPL and Pluto

Use the REPL for a short command-driven session, or Pluto to keep an editable
notebook with controls and plots. For existing `@testitem` declarations, the
[first-result tutorial](../guide/first-check.md) gives the complete discovery,
selection and execution commands. The suite workflows below use the separate
Bibliography benchmark example.

Both interfaces let you select a `SuitePlan` and save its results for later use.

Shared scenarios additionally support `write_investigation_notebook` with explicit
Launch, Cancel and Refresh controls. `investigation_view` displays saved reports
in either interface without running the target. See
[Shared scenarios](../shared-scenarios.md) for setup and examples.

## Read the numbers in either interface

A terminal summary and a Pluto plot can show the same saved observations.
Check the selected metric and unit: elapsed time is the duration of the
declared operation, and allocated bytes are allocation activity during that
operation. A table of samples reveals variation that a single median hides.
Changing interface does not change these definitions.

For Bibliography, inspect the export timings first, then open the allocation
profile to locate temporary strings and buffers. The notebook's own loading
and rendering time is separate from the saved export measurement. See the
[measurement tutorial](../guide/understanding-measurements.md) for GC, memory
and flame-graph interpretation.

## REPL workflow

First [prepare the Bibliography example](../tutorials/bibliography.md#Prepare-the-example-once).
From `examples/bibliography/`, launch its prepared controller:

```sh
julia --startup-file=no --project=.controller/core repl.jl
```

The launcher opens the selector. To call the API yourself, start Julia with the
same `--project` argument in that directory and run:

```julia
using PerfChecker

suite = load_software_suite("suite.jl")
selected, overrides = configure_suite_repl(suite; profile = :quick)
result = run_suite_repl(selected; overrides, strict = false)
```

The configurator lets you filter packages, business features, check types, and
targets. It prints the resolved plan before execution and reports progress while
workers run. For scripted use, `filter_suite_plan` and `select_suite_plan` apply
the same selection without prompts.

Install UnicodePlots in the controller environment to render terminal-native
summaries. This API fragment uses `bundle_directory`, the path to a saved suite
bundle; the [plotting tutorial](visualization.md#Build-a-plot-from-a-saved-run)
shows how to select one from a Bibliography report:

```julia
using UnicodePlots
# Use a saved suite bundle, as loaded in the plotting tutorial.
bundle = read_run_bundle(bundle_directory)
plot_id = first(plot_catalog(bundle))["id"]
terminal_plot(bundle, plot_id)
```

Terminal plots are a compact fallback; they do not replace hover, linked
selection, or source drill-down in WGLMakie.

## Pluto dashboard

Start with the actual Bibliography notebook rather than recreating the example:

```@raw html
<p><a href="../examples/bibliography/pluto/notebook.jl" download="notebook.jl"><strong>Download the runnable Pluto notebook</strong></a></p>
```

Save it in `examples/bibliography/` and follow the
[two preparation and launch commands](../tutorials/bibliography.md#Open-Pluto).
It offers the current pinned suite and a nine-version historical comparison,
with explicit Launch, Cancel, Refresh and Save controls. The image below is an
overview of those controls; the downloaded notebook is editable and executable.

To generate a dashboard for your own suite instead, first supply a working
`perf/suite.jl` with a `build_suite()` factory and a prepared controller environment:

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

The selected controller environment must contain PerfChecker, PerfCheckerPluto and PlutoUI, plus
the collectors used by the suite. The Bibliography setup script prepares it.
The notebook activates that environment even when saved in another directory.

Choose a package, workload, collector and target, then review the plan. Changing
a selector does not start workers. **Launch selected checks** starts the chosen
plan; **Refresh status** reads progress and completed results. **Cancel active
job** requests cancellation. **Save completed reports** writes a new directory
containing the bundle and reports. The default is one worker thread.

```@raw html
<DocMedia src="/examples/bibliography/pluto/completed.png" alt="Pluto displaying a completed Bibliography export check and saved reports" caption="Actual Bibliography execution through Pluto: explicit launch, progress, saved report and completed result. The walkthrough uses the same workload in each interface." />
```

The generated notebook is an editable controller surface. Measurements execute
in fresh Malt workers; the notebook displays their status and report rows.
Use [the plotting interface](visualization.md) for visual exploration of saved
bundles. Commit the generated notebook
only when it is meant to be a maintained project interface; otherwise regenerate
it from the suite.
