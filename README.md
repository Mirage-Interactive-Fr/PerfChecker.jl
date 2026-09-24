<p align="center">
  <img src="branding/exports/perfchecker-lockup-light.svg" width="620" alt="PerfChecker.jl">
</p>

[![Documentation](https://img.shields.io/badge/docs-dev-2dd4bf.svg)](https://mirage-interactive-fr.github.io/PerfChecker/dev/)
[![Qualification](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/actions/workflows/Qualification.yml/badge.svg?branch=release%2Fv1.0.0-rc1)](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/actions/workflows/Qualification.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-8b5cf6.svg)](LICENSE)

PerfChecker measures Julia package performance in isolated workers. Reuse existing
TestItems, compare tagged releases and development revisions, then inspect the
same results in VS Code, the web interface, Pluto or the REPL.

**V1 release candidate:** this branch contains **1.0.0-rc1**. General still provides
stable version 0.2.4. Please report reproducible problems through
[GitHub issues](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/issues).

## Install the candidate

In your chosen Julia environment:

```julia
import Pkg
Pkg.add(Pkg.PackageSpec(name="PerfChecker", rev="release/v1.0.0-rc1"))
using PerfChecker
```

Start with [your first test item](https://mirage-interactive-fr.github.io/PerfChecker/dev/guide/first-check)
or the runnable [Bibliography example](examples/bibliography/README.md).
Use `Pkg.add("PerfChecker")` for the registered stable release.

## Interfaces

The Julia API, command line and text REPL are included in PerfChecker.

| Optional package | Interface |
| --- | --- |
| [PerfCheckerWeb](packages/PerfCheckerWeb) | Web interface (Oxygen) |
| [PerfCheckerPluto](packages/PerfCheckerPluto) | Reactive notebooks |
| [PerfCheckerMakie](packages/PerfCheckerMakie) | Individual and overlaid plots |
| [PerfChecker for VS Code](https://github.com/Mirage-Interactive-Fr/PerfCheckerVSCode/tree/release/v0.1.0) | Test Explorer, results and profiling |

The Julia interfaces have separate package identities and dependencies in this
shared repository. Their first General registrations are pending. During the RC:

```julia
Pkg.add(Pkg.PackageSpec(
    url="https://github.com/Mirage-Interactive-Fr/PerfChecker.jl",
    rev="release/v1.0.0-rc1", subdir="packages/PerfCheckerWeb"))
```

Replace the subdirectory with `packages/PerfCheckerPluto` or
`packages/PerfCheckerMakie` as appropriate. See the
[installation guide](website/src/guide/installation.md) for optional collectors.

## Measurements and comparisons

- Run existing `@testitem` declarations individually or filter them by tags.
- Collect BenchmarkTools or Chairmarks timing, GC and allocation measurements.
- Overlay four metrics normalized by their respective minima, or inspect
  individual measurements in their original units.
- Investigate CPU, wall-time and allocation profiles, process memory and native
  dependencies when the required tools are available.
- Export portable run bundles and JSON, Markdown or JUnit reports for CI.

The controller and interfaces stay outside measured workers. Reports retain
workload, source, environment and collector provenance. No model is required.

For test items, `:check_only` runs in PerfChecker measurements and is excluded by
`testitem_filter(:test)`. The existing `:perf_only` spelling is equivalent, including
tag selection. `:test_only` runs in functional tests and is excluded from PerfChecker
measurements; untagged items are shared. Julia's VS Code Test Explorer owns its
functional runs and does not apply PerfChecker's filter automatically. Use an
explicit item selection there, or `testitem_filter(:test)` with TestItemRunner in
functional CI.

For a `:check_only` item that must also be safe under Julia VS Code's **Run All**,
use TestItems' conditional skip option:

```julia
@testitem "Measured case" tags=[:check_only] skip=(get(ENV, "PERFCHECKER_TESTITEM_MODE", "") != "performance") begin
    @test sum(1:1000) == 500500
end
```

PerfChecker sets `PERFCHECKER_TESTITEM_MODE=performance` only in its measured test
item workers. An ordinary TestItemRunner or Julia VS Code run skips this item.
This is opt-in per declaration; the Julia extension does not exclude
`:check_only` or `:perf_only` by tag on its own.

## Contribute and test

See the [release notes](CHANGELOG.md), [qualification matrix](qualification/README.md)
and [documentation contribution guide](website/src/contributing/documentation.md).
The collection tests the core and affected interfaces on Windows and Linux.
Only a complete passing collection can publish the versioned documentation.

PerfChecker is primarily maintained by [Mirage Interactive](https://mirageinteractive.fr/).
Community contributions are welcome.
