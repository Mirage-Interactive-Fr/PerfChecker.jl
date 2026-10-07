# Installation

## Core package

The Julia API, command line and text REPL are in PerfChecker itself. **PerfChecker
1.0.0 is registered in Julia General** and requires Julia 1.10 or newer:

```julia
import Pkg
Pkg.add(Pkg.PackageSpec(name = "PerfChecker", version = "1"))
using PerfChecker
```

If an existing environment still resolves the 0.2 series, refresh its registries
and request V1 explicitly. Dependency constraints can prevent an upgrade; keep
your performance controller separate from the package being measured:

```julia
Pkg.Registry.update()
Pkg.add(Pkg.PackageSpec(name = "PerfChecker", version = "1"))
Pkg.status("PerfChecker")
```

The V1 API differs from the 0.2 series. Use a separate environment when migrating
an existing project, and select the V1 package explicitly.

## Optional packages

Install only what you need.

- Existing TestItems — `Pkg.add("TestItemRunner")`
- BenchmarkTools — `Pkg.add("BenchmarkTools")`
- Chairmarks — `Pkg.add("Chairmarks")`
- Oxygen web interface — `PerfCheckerWeb`, installed from the subdirectory below
- Pluto notebooks — `PerfCheckerPluto`, using `packages/PerfCheckerPluto`
- Makie figures — `PerfCheckerMakie`, using `packages/PerfCheckerMakie`

The three interface packages have separate identities. Until their first General
registrations, install one from its repository subdirectory at the stable tag:

```julia
Pkg.add(Pkg.PackageSpec(
    url = "https://github.com/Mirage-Interactive-Fr/PerfChecker.jl",
    rev = "v1.0.0",
    subdir = "packages/PerfCheckerWeb"))
```

Use `packages/PerfCheckerPluto` or `packages/PerfCheckerMakie` for the others.

### Prepare the integrated Pluto candidate

The VS Code Pluto integration is being qualified for extension **1.0.1** and
requires corrected **PerfChecker core 1.0.1**. Wait for these releases before
following its installation steps. Public extension 1.0.0 retains its earlier
notebook workflow; the standalone Pluto interface above is already available.

The candidate's explicit **Install Pluto environment** action prepares
`perf/pluto`. Review the listed packages and selected folder before confirming.
For manual setup, run this from the package root after Core 1.0.1 is in General:

```julia
import Pkg
Pkg.activate("perf/pluto")
Pkg.add(Pkg.PackageSpec(name = "PerfChecker", version = "1.0.1"))
Pkg.add(Pkg.PackageSpec(name = "Pluto", version = "1.0.4"))
Pkg.add(["PlutoUI", "BenchmarkTools", "Chairmarks"])
Pkg.add(Pkg.PackageSpec(
    url = "https://github.com/Mirage-Interactive-Fr/PerfChecker.jl",
    rev = "v1.0.0",
    subdir = "packages/PerfCheckerPluto"))
using PerfChecker, PerfCheckerPluto, Pluto, PlutoUI
Pkg.status()
```

The companion's v1.0.0 source supports the corrected core within its 1.x range.
The final extension qualification will record its exact companion tag. Pluto
1.0.4's published dependency range uses HTTP 1.x; the qualified MCP controller
uses HTTP 2.x. Keep these environments separate. Later Pluto versions can have
different dependency ranges; check their published compatibility before changing
the qualified version.

Set `perfchecker.plutoProject` to `perf/pluto`, then follow
[the integrated notebook workflow](../interfaces/vscode-workflows.md#Pluto-notebooks-in-VS-Code)
for generation, reactive editing, explicit checks and session cleanup. Packages
and analyzers used by measured workers belong in their selected target project.

## Environments

- Put PerfChecker and its collectors in your **controller** environment.
- The measured target and its dependencies go in the **worker** environment.
- Interface packages never belong in a measurement environment.

A suite declares its worker environment; PerfChecker prepares it before measuring.

## Editor

Install the [VS Code extension](../interfaces/vscode.md) and point it at a Julia environment containing PerfChecker.

## Next

[Get a first result](first-check.md), or read [Suites and comparisons](../suites-and-comparisons.md).
