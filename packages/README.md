# PerfChecker companions

These are independently installable Julia companions in the PerfChecker repository.
Each depends on the public PerfChecker engine. Loading the engine does not install
or load any of them. Interface sessions and jobs remain explicit; there is no
global active PerfChecker interface.

| Package | Use |
| --- | --- |
| PerfCheckerWeb | Oxygen Studio, HTTP routes and remote agents |
| PerfCheckerPluto | Notebook generation, reactive controls and Pluto launch |
| PerfCheckerMakie | Figures and plot recipes, with optional WGLMakie rendering |
| [PerfCheckerTachikoma](PerfCheckerTachikoma/README.md) | Optional keyboard terminal UI and saved-evidence plots |
| [PerfCheckerLinuxPerf](PerfCheckerLinuxPerf/README.md) | Optional calling-thread Linux perf-event counter collector |
| [PerfCheckerLIKWID](PerfCheckerLIKWID/README.md) | Optional native CPU-window counter collector |

The three original Web/Pluto/Makie interfaces are available from the immutable
`v1.0.0` tag. Install the registered core and the selected tagged interface:

```julia
using Pkg
Pkg.add(Pkg.PackageSpec(name="PerfChecker", version="1.0.0"))
Pkg.add(Pkg.PackageSpec(
    url="https://github.com/Mirage-Interactive-Fr/PerfChecker.jl",
    rev="v1.0.0", subdir="packages/PerfCheckerWeb"))
using PerfChecker, PerfCheckerWeb
```

Replace the last directory with PerfCheckerPluto or PerfCheckerMakie as needed.
These packages await their first General registrations. Once registered, install
them by name with `Pkg.add`. The CLI and text REPL remain in
PerfChecker. The VS Code client uses the same versioned process protocol.

Tachikoma and the hardware-counter companions are **1.0.1 source packages**,
absent from `v1.0.0` and not separately registered. Use the
[source-companion installation recipes](../website/src/guide/installation.md)
at reviewed revision `1a7577da782ba8676683f3ceefcb8dccf055afe5`; they explicitly
develop both the core and chosen companion from that checkout. The
[API ownership index](../website/src/reference/api.md) links
their source docstrings and Julia help examples. The per-package READMEs provide
the detailed terminal or counter contracts.

Use separate controller environments when interfaces require incompatible HTTP
versions. Workers continue to use their own environments; Web/Pluto/Makie renderer
dependencies do not belong in a measurement environment. Counter workers do need
their chosen counter companion and exact target. Keep LinuxPerf 0.4.2 / PrettyTables 2
and LIKWID 0.4.6 / PrettyTables 3 worker projects separate. Missing permissions or
native libraries remain unavailable; native CLI/VSCode/Pluto/MCP counter selection
and hardware HTTP/UI qualification are not supplied by these packages.
See [qualification](../qualification/README.md) for
the shared test matrix and the [website sources](../website/) for the autonomous DocumenterVitepress site.
