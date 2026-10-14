# PerfCheckerWeb

An Oxygen browser controller, HTTP routes and remote agents for PerfChecker.
Measurements run in separate workers. Loading the companion starts no server.

## Installation

PerfCheckerWeb 1.0.0 is registered in General. Use a controller project separate
from the measured target and from Pluto:

```julia
using Pkg
Pkg.activate("perf/controller")
Pkg.add(["PerfChecker", "PerfCheckerWeb"])
```

The published Core has a [known ARM import limitation](../README.md#arm-compatibility).

## Start a local controller

From your package root, with an existing suite and its collectors installed:

```julia
using PerfChecker, PerfCheckerWeb
suite = load_software_suite("perf/suite.jl")
serve_suite(suite; host="127.0.0.1", port=8080,
    profile=:quick, reports_root="perf/results")
```

Open `http://127.0.0.1:8080/perfchecker/v1/`. Opening the page does not launch a
measurement. Select and review a plan before launching it.

See the [Web guide](https://perfchecker.mirageinteractive.fr/dev/interfaces/web-studio.html)
for authenticated remote access, worker agents, cancellation and saved reports.
