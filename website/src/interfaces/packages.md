# Choose an interface

Choose where you want to run a check or read a result. The Julia API and scripts
work with PerfChecker alone; the graphical interfaces add controls around the
same execution and report APIs. You can start with one interface.

| I want to… | Use | Try it with Bibliography |
| --- | --- | --- |
| Run an existing test individually while editing code | [VS Code](vscode.md) | Discover the two example items and run only the export item |
| Select workloads and versions in a browser | [Oxygen Web Studio](web-studio.md) | Select one export benchmark, then reopen its plot |
| Choose checks from a terminal | [REPL](repl-pluto.md) | Filter the pinned suite before launching it |
| Keep editable analysis in a notebook | [Pluto](repl-pluto.md#Pluto-dashboard) | Download the notebook, choose a version set and save the result |
| Explore or export measured curves and profiles | [Makie](visualization.md) | Inspect nine versions and download their measurements |
| Include saved measurements in my own documentation | [Documenter](documentation.md) | Select the export observations from a saved suite bundle |

## What to have ready

For existing test items, prepare the package's test dependencies and load
TestItemRunner with PerfChecker. The [first-result tutorial](../guide/first-check.md)
provides a downloadable item if you need an example.

For the suite controls, start with a suite that identifies the workloads and
versions to run. The [Bibliography walkthrough](../tutorials/bibliography.md)
supplies this file and the launch commands for each interface. A **plan** selects
what will execute; a **saved result** contains what already executed.

Plotting and Documenter examples require a saved **suite run bundle**. The
`testitems.json` report from native test items is a different format; it cannot
be passed to `read_run_bundle` or plotted by the suite plot API. Use the suite
benchmark in the Bibliography walkthrough to obtain the plotting example.

## Which package supplies each interface?

| Package | Capability |
| --- | --- |
| PerfChecker | Julia API, command line and text REPL |
| PerfCheckerWeb | Oxygen Studio and HTTP endpoints |
| PerfCheckerPluto | Notebook controls and Pluto launch |
| PerfCheckerMakie | Makie figures; WGLMakie adds interactive HTML |

See [installation](../guide/installation.md) for what to add and current V1
availability. The interface packages' first General registrations are pending.
VS Code is an editor extension with a separate installation, described on its page.

Loading Oxygen, Pluto or Makie alone does not load the PerfChecker interface.
Use separate environments if their dependency versions conflict; saved suite
bundles can be read by each environment. Opening a notebook does not redirect
an existing VS Code or web run to a different backend.

The repository arrangement is a maintainer concern: the interfaces are ordinary
Julia packages with separate identities. See [package registration](../architecture-roadmap.md#Register-packages-from-the-shared-repository)
for the General/subdirectory details.
