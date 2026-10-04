# Installation

## Core package

The Julia API, command line and text REPL are in PerfChecker itself.

```julia
import Pkg
Pkg.add(Pkg.PackageSpec(name = "PerfChecker", version = "1"))
using PerfChecker
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

## Environments

- Put PerfChecker and its collectors in your **controller** environment.
- The measured target and its dependencies go in the **worker** environment.
- Interface packages never belong in a measurement environment.

A suite declares its worker environment; PerfChecker prepares it before measuring.

## Editor

Install the [VS Code extension](../interfaces/vscode.md) and point it at a Julia environment containing PerfChecker.

## Next

[Get a first result](first-check.md), or read [Suites and comparisons](../suites-and-comparisons.md).
