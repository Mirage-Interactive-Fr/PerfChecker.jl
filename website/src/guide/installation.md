# Installation

## Core package

The Julia API, command line and text REPL are in PerfChecker itself.

```julia
import Pkg
Pkg.add("PerfChecker")   # stable, currently 0.2.4
```

The V1 release candidate has a different API. Install it in a separate environment:

```julia
Pkg.add(Pkg.PackageSpec(name = "PerfChecker", rev = "release/v1.0.0-rc1"))
using PerfChecker
```

!!! warning "Release candidate"
    These pages describe **1.0.0-rc1**. General still serves **0.2.4**.
    Keep the candidate in its own environment.

## Optional packages

Install only what you need.

- Existing TestItems — `Pkg.add("TestItemRunner")`
- BenchmarkTools — `Pkg.add("BenchmarkTools")`
- Chairmarks — `Pkg.add("Chairmarks")`
- Oxygen web interface — `Pkg.add("PerfCheckerWeb")`
- Pluto notebooks — `Pkg.add("PerfCheckerPluto")`
- Makie figures — `Pkg.add("PerfCheckerMakie")`

The three interface packages await their first General registration. During the release candidate, install one from its repository subdirectory:

```julia
Pkg.add(Pkg.PackageSpec(
    url = "https://github.com/Mirage-Interactive-Fr/PerfChecker.jl",
    rev = "release/v1.0.0-rc1",
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
