# REPL

Configure and run a suite from an ordinary Julia terminal. PerfChecker supplies
the text interface; [Tachikoma](tachikoma.md) adds an optional keyboard UI.

```@raw html
<a id="REPL"></a>
<a id="REPL-workflow"></a>
```

```@raw html
<a id="Select,-run-and-save"></a>
```

## Select, run and save

Start Julia in a prepared controller containing PerfChecker and the collectors
declared by your suite. From your package root:

```julia
using PerfChecker, BenchmarkTools, Chairmarks

suite = load_software_suite("perf/suite.jl")
selected, overrides = configure_suite_repl(suite; profile = :quick)
result = run_suite_repl(selected; overrides, strict = false)
suite_summary(result)
paths = write_suite_reports(result, "perf/results/repl-example")
foreach(println, paths)
```

The configurator lists packages, features, collectors and targets, then asks for
filters and measurement settings. Review the selected rows before confirming.
Blank selectors include all matching rows. Configuration returns the plan;
`run_suite_repl` starts the measurement.

After a completed run, the report paths include `suite-report.md`,
`suite-result.json`, `suite-junit.xml` and `bundles/run-…`. Use a fresh report
directory: exporting replaces ordinary report files. Reports save results;
they do not rewrite the suite or save your interactive selection as a new suite.
A one-target run without a comparison policy has no regression verdict.

```@raw html
<a id="Display-a-saved-plot"></a>
```

## Display a saved plot

Install UnicodePlots in the controller, then select a catalogue view from an
actual saved bundle:

```julia
using PerfChecker, UnicodePlots

bundle = read_run_bundle("perf/results/repl-example/bundles/ACTUAL-BUNDLE")
catalog = plot_catalog(bundle)
foreach(entry -> println(entry["id"], " · ", entry["title"]), catalog)
isempty(catalog) && error("This bundle has no supported plots")
display(terminal_plot(bundle; plot_id = first(catalog)["id"],
    width = 70, height = 18))
```

Expected output: a text chart with its saved title, targets and unit.
Replace `ACTUAL-BUNDLE` with the directory printed by the run. Rendering starts
no measurement. Read the collector and units before comparing values.

```@raw html
<p>Real saved output: <a href="../examples/real-packages/oxygen-features/normalized-metrics-24034c4be099f2e2.txt" download="oxygen-normalized.txt">Oxygen fourteen-release terminal chart</a>. The original values remain available through the <a href="../real-packages/oxygen.html">Oxygen example</a>.</p>
```

::: details Supplied package examples

From `examples/bibliography/`:

```sh
julia setup.jl core
julia --project=.controller/core repl.jl
```

Select `Bibliography → export_bibtex → benchmark`, review the targets, then
confirm. The wrapper saves reports in a new directory and prints its location.

From `examples/kitchen-sink/`, `julia --project=. replay.jl results/ACTUAL-RUN`
prints a completed bundle's catalogue with UnicodePlots and saves text under
`exports/terminal`. It collects no new measurements. The shipped `replay.jl`
also supplies `saved_plot("downloaded-plot.json")` for a downloaded presentation
model; that JSON is smaller in scope than a complete run bundle.

:::
