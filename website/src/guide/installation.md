# Installation

Install the V1 release candidate in your chosen Julia environment:

```julia
import Pkg
Pkg.add(Pkg.PackageSpec(name="PerfChecker", rev="release/v1.0.0-rc1"))
using PerfChecker
```

The Julia API, command line and text REPL are included in PerfChecker.

!!! warning "Release candidate"
    PerfChecker is registered in General, currently through version **0.2.4**.
    These pages describe **1.0.0-rc1**, available from the RC branch above.
    Use `Pkg.add("PerfChecker")` for the registered stable release.
    The new interface packages below also await their first General
    registrations. Their installation by name will be available after registration.
    [Check registered versions](https://github.com/JuliaRegistries/General/blob/master/P/PerfChecker/Versions.toml).

## Optional packages

Install only the additions you want:

| For | Add to the Julia environment |
| --- | --- |
| Measuring existing TestItems | `Pkg.add("TestItemRunner")` |
| BenchmarkTools measurements | `Pkg.add("BenchmarkTools")` |
| Chairmarks measurements | `Pkg.add("Chairmarks")` |
| Oxygen web interface | `Pkg.add("PerfCheckerWeb")` — registration pending |
| Pluto notebooks | `Pkg.add("PerfCheckerPluto")` — registration pending |
| Makie figures | `Pkg.add("PerfCheckerMakie")` — registration pending |

During the RC, install an interface directly from its repository subdirectory:

```julia
Pkg.add(Pkg.PackageSpec(
    url="https://github.com/Mirage-Interactive-Fr/PerfChecker.jl",
    rev="release/v1.0.0-rc1",
    subdir="packages/PerfCheckerWeb"))
```

Use `packages/PerfCheckerPluto` or `packages/PerfCheckerMakie` for those interfaces.
No local clone or generated suite is needed to install a package.

For interactive Makie plots, also add `WGLMakie` and `Bonito`.
For the editor interface, install the [VS Code extension](../interfaces/vscode.md)
and select the Julia environment containing PerfChecker.

Next: [get a first result](first-check.md), or read
[what a suite and a comparison mean](../suites-and-comparisons.md).
