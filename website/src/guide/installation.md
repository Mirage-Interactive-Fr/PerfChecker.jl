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

### Source companions for 1.0.1

PerfCheckerTachikoma, PerfCheckerLinuxPerf and PerfCheckerLIKWID are separate
**1.0.1 source companions**, not registered packages. They are absent from the
immutable `v1.0.0` tag. The recipes below use reviewed revision
`63f5cc4bfc2c55de521487f68b0df143107762f3` and do not imply a new General release
or hardware qualification. Keep an existing checkout unchanged: the following
commands assume a new, unused destination under `~/.julia/dev`.

```sh
git clone https://github.com/Mirage-Interactive-Fr/PerfChecker.jl \
    "$HOME/.julia/dev/PerfChecker-source-101"
git -C "$HOME/.julia/dev/PerfChecker-source-101" checkout --detach \
    63f5cc4bfc2c55de521487f68b0df143107762f3
```

For the optional terminal interface, choose an unused controller project:

```julia
import Pkg
source = joinpath(homedir(), ".julia", "dev", "PerfChecker-source-101")
controller = joinpath(homedir(), ".julia", "environments", "perfchecker-tachikoma-101")
Pkg.activate(controller)
Pkg.develop([
    Pkg.PackageSpec(path = source),
    Pkg.PackageSpec(path = joinpath(source, "packages", "PerfCheckerTachikoma")),
])
Pkg.instantiate()
using PerfChecker, PerfCheckerTachikoma
Pkg.status()
@doc PerfCheckerTachikoma.tui
```

The companion declares compatibility with Tachikoma starting at 2.7 and
UnicodePlots 3; inspect the actual resolved versions. Loading it starts no
terminal or measurement. See its
[README](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/blob/63f5cc4bfc2c55de521487f68b0df143107762f3/packages/PerfCheckerTachikoma/README.md)
for explicit `tui` calls, run/cancel controls and optional raster setup. Controlled
terminal tests do not qualify every physical terminal or macOS/Windows.

Hardware-counter companions belong in their **explicit worker projects**, with
the exact target already prepared. They are collectors, unlike the Web/Pluto/Makie
rendering interfaces. Do not combine the current LinuxPerf 0.4.2 / PrettyTables 2
and LIKWID 0.4.6 / PrettyTables 3 projects. Choose one recipe per fresh project;
`target_source` below must be your existing, reviewed Julia target checkout.

```julia
import Pkg
source = joinpath(homedir(), ".julia", "dev", "PerfChecker-source-101")
target_source = joinpath(homedir(), ".julia", "dev", "Example")
worker_project = joinpath(homedir(), ".julia", "environments", "perfchecker-linuxperf-worker-101")
Pkg.activate(worker_project)
Pkg.develop([
    Pkg.PackageSpec(path = source),
    Pkg.PackageSpec(path = joinpath(source, "packages", "PerfCheckerLinuxPerf")),
    Pkg.PackageSpec(path = target_source),
])
Pkg.instantiate()
using PerfChecker, PerfCheckerLinuxPerf
Pkg.status()
@doc PerfCheckerLinuxPerf.run_counter_suite
```

For LIKWID, use a different project and develop its companion instead:

```julia
import Pkg
source = joinpath(homedir(), ".julia", "dev", "PerfChecker-source-101")
target_source = joinpath(homedir(), ".julia", "dev", "Example")
worker_project = joinpath(homedir(), ".julia", "environments", "perfchecker-likwid-worker-101")
Pkg.activate(worker_project)
Pkg.develop([
    Pkg.PackageSpec(path = source),
    Pkg.PackageSpec(path = joinpath(source, "packages", "PerfCheckerLIKWID")),
    Pkg.PackageSpec(path = target_source),
])
Pkg.instantiate()
using PerfChecker, PerfCheckerLIKWID
Pkg.status()
@doc PerfCheckerLIKWID.run_counter_suite
```

Both companions' compatibility bounds pin their native Julia wrapper version.
Inspect the resolved environment and target path before running the declared
suite. The [LinuxPerf recipe](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/blob/63f5cc4bfc2c55de521487f68b0df143107762f3/packages/PerfCheckerLinuxPerf/README.md)
uses backend `:linuxperf`, an explicit `counter_environment`, exact events and a
verified workload. The [LIKWID recipe](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/blob/63f5cc4bfc2c55de521487f68b0df143107762f3/packages/PerfCheckerLIKWID/README.md)
uses backend `:likwid`, exact event/counter pairs, declared units and CPUs inside
inherited affinity. Its worker launch removes `LIKWID_PERF_PID` temporarily and
restores the controller environment afterwards; it does not retarget a foreign PID.

Linux perf-event access and LIKWID's native library are independent prerequisites.
Installing Julia packages does not grant permissions, install `liblikwid` or
change CPU affinity. Refusal remains unavailable, never zero or hardware success.
Default CLI/VSCode/Pluto/MCP selectors do not wire these executors. Use the
[explicit Julia counter API](../reference/api.md#Hardware-counter-APIs); hardware
HTTP/UI qualification remains pending.

### Prepare the integrated Pluto candidate

The VS Code Pluto integration is being qualified for extension **1.0.1** and
requires corrected **PerfChecker core 1.0.1** and **PerfCheckerPluto 1.0.1**.
Wait for the corrected extension, Core 1.0.1 in General and TagBot's `v1.0.1`
repository tag before following its installation steps. Public extension 1.0.0 retains its earlier
notebook workflow; the standalone Pluto interface above is already available.

The candidate's explicit **Install Pluto environment** action prepares
`perf/pluto`. Review the listed packages and selected folder before confirming.
For a disposable setup check, run this after the registration and tag above are
available. It creates a new project and does not modify an existing controller
or notebook environment:

```julia
import Pkg
pluto_project = mktempdir()
Pkg.activate(pluto_project)
Pkg.add(Pkg.PackageSpec(name = "PerfChecker", version = "1.0.1"))
Pkg.add(Pkg.PackageSpec(name = "Pluto", version = "1.0.4"))
Pkg.add(["PlutoUI", "BenchmarkTools", "Chairmarks"])
Pkg.add(Pkg.PackageSpec(
    url = "https://github.com/Mirage-Interactive-Fr/PerfChecker.jl",
    rev = "v1.0.1",
    subdir = "packages/PerfCheckerPluto"))
using PerfChecker, PerfCheckerPluto, Pluto, PlutoUI
@assert v"1.0.1" <= Base.pkgversion(PerfCheckerPluto) < v"2.0.0"
Pkg.status()
```

`mktempdir()` removes this disposable environment when Julia exits. For ongoing
manual use, choose an unused project directory instead; for guided setup,
confirm installation or the explicit upgrade of your selected Pluto project.
An older companion is reported as incompatible rather than upgraded silently.
The companion installation uses its repository subdirectory at `v1.0.1`; the
companion is not yet separately registered in General. Core registration alone
does not make `Pkg.add("PerfCheckerPluto")` available; that requires its own
[subdirectory registration](../contributing/documentation.md#Register-Core-and-its-companions).
The other companion packages retain their own versions. Pluto 1.0.4's published
dependency range uses HTTP 1.x; the qualified MCP controller
uses HTTP 2.x. Keep these environments separate. Later Pluto versions can have
different dependency ranges; check their published compatibility before changing
the qualified version.

Set `perfchecker.plutoProject` to the persistent project you explicitly prepared
(the guided default is `perf/pluto`), then follow
[the integrated notebook workflow](../interfaces/vscode-workflows.md#Pluto-notebooks-in-VS-Code)
for generation, reactive editing, explicit checks and session cleanup. Packages
and analyzers used by measured workers belong in their selected target project.
Existing generated suite notebooks retain their earlier cells; use
[a new notebook file](../interfaces/vscode-workflows.md#Use-the-corrected-suite-plot-renderer)
to obtain the corrected plot renderer without overwriting saved work.

## Environments

- Put PerfChecker and its collectors in your **controller** environment.
- The measured target and its dependencies go in the **worker** environment.
- Web/Pluto/Makie rendering interfaces belong outside measurement environments.
  Optional hardware-counter companions are required in their explicitly selected
  worker projects; follow the separate recipes above.

A suite declares its worker environment; PerfChecker prepares it before measuring.

## Editor

Install the [VS Code extension](../interfaces/vscode.md) and point it at a Julia environment containing PerfChecker.

## Next

[Get a first result](first-check.md), or read [Suites and comparisons](../suites-and-comparisons.md).
