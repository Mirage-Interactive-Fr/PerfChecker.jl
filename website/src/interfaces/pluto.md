# Pluto

Open a reactive Julia notebook with suite selectors, explicit launch/cancel
controls, saved reports and plots. The downloadable notebooks below contain
their experiment definitions; use them through Pluto's notebook interface.

```@raw html
<a id="Pluto"></a>
<a id="Pluto-dashboard"></a>
```

```@raw html
<a id="Install-and-open-a-notebook"></a>
```

## Install and open a notebook

Install Pluto in a separate Julia environment, then start it:

```julia
import Pkg
Pkg.activate(joinpath(homedir(), ".julia", "environments", "perfchecker-pluto"))
Pkg.add(Pkg.PackageSpec(name = "Pluto", version = "1.0.4"))
using Pluto
Pluto.run()
```

Use Julia **1.12+** for the supplied examples. Download one file, then select
**Open a notebook** in Pluto's browser interface and choose that file.

```@raw html
<ul>
<li><a href="../examples/bibliography/pluto/notebook.jl" download="bibliography-notebook.jl">Bibliography notebook (.jl)</a> — export workloads and a nine-release history.</li>
<li><a href="../examples/real-packages/datastructures-notebook.jl" download="datastructures-notebook.jl">DataStructures notebook (.jl)</a> — container workloads, correctness checks and release comparisons.</li>
<li><a href="../examples/real-packages/oxygen-notebook.jl" download="oxygen-notebook.jl">Oxygen notebook (.jl)</a> — HTTP workloads, correctness checks and release comparisons.</li>
</ul>
```

On first opening, review the notebook's setup cell and preparation instructions.
Dependency and source preparation needs Git and internet access. Select the
package, workload, collector and targets; review the plan before choosing
**Launch selected checks**. Changing a selector requests no measurement.
Pluto still evaluates reactive cells, including any explicit setup cell.

Use **Refresh status**, **Cancel active job** and **Save completed reports**.
A completed report preserves evidence independently of the notebook source;
Pluto saves cell edits into the `.jl` file. Keep both when retaining an experiment.

```@raw html
<DocMedia src="/examples/bibliography/pluto/completed.png" alt="Completed Bibliography check in Pluto with status and saved report paths" caption="Existing recorded Bibliography execution: explicit launch, completed status and saved evidence." />
```

```@raw html
<a id="Generate-a-notebook-for-your-suite"></a>
```

## Generate a notebook for your suite

Prepare a separate notebook project containing PerfChecker,
PerfCheckerPluto **1.0.1**, PlutoUI and your suite's collectors.
PerfCheckerPluto 1.0.1 is registered in General:

```julia
import Pkg
Pkg.activate("perf/notebooks")
Pkg.add(["PerfChecker", "PerfCheckerPluto", "PlutoUI"])
```

On ARM, use [Core 1.1.1 or newer](../guide/overview.md#ARM-installations).
From your package root, using that notebook project:

```julia
using PerfChecker, PerfCheckerPluto

notebook = prepare_pluto_dashboard("perf/notebooks/performance.jl";
    suite_path = abspath("perf/suite.jl"),
    project = dirname(Base.active_project()))
launch_pluto_dashboard(notebook)
```

Generation writes source and refuses an existing destination by default.
Launching opens Pluto and evaluates its cells; checks use the notebook's explicit
launch action. Without a suite path, the generator creates a saved-report reader.
`write_investigation_notebook` supplies the investigation variant.

[VS Code](vscode.md#Pluto,-terminal-and-debugging) can create and reopen these
native `.jl` notebooks inside the editor. Keep its Pluto project separate from
an HTTP 2 MCP controller.
