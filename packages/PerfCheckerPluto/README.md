# PerfCheckerPluto

Generate and open Pluto notebooks for PerfChecker suites and saved reports.
Loading the companion opens no notebook and starts no measurement.

## Installation

PerfCheckerPluto 1.0.1 is registered in General. Use a separate notebook project:

```julia
using Pkg
Pkg.activate("perf/notebooks")
Pkg.add(["PerfChecker", "PerfCheckerPluto"])
```

The published Core has a [known ARM import limitation](../README.md#arm-compatibility).

## Open a suite notebook

From your package root, with an existing `perf/suite.jl`:

```julia
using PerfChecker, PerfCheckerPluto
notebook = prepare_pluto_dashboard("perf/notebooks/performance.jl";
    suite_path=abspath("perf/suite.jl"),
    project=dirname(Base.active_project()))
launch_pluto_dashboard(notebook)
```

Generation writes notebook source and refuses an existing destination by default.
Launching opens Pluto and evaluates the notebook's cells. Measurements require
the notebook's explicit launch action. Prepare the suite's collectors in its
notebook project before use; workers retain their own measurement environments.

See the [Pluto guide](https://perfchecker.mirageinteractive.fr/dev/interfaces/pluto.html)
for downloadable notebooks, cancellation, saved reports and VS Code integration.
