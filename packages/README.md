# PerfChecker companions

These are independently installable Julia companions in the PerfChecker repository.
Each depends on the public PerfChecker engine. Loading the engine does not install
or load any of them. Interface sessions and jobs remain explicit; there is no
global active PerfChecker interface.

| Package | General version | Use |
| --- | --- | --- |
| [PerfCheckerWeb](PerfCheckerWeb/README.md) | 1.0.0 | Oxygen Studio, HTTP routes and remote agents |
| [PerfCheckerPluto](PerfCheckerPluto/README.md) | 1.0.1 | Notebook generation, reactive controls and Pluto launch |
| [PerfCheckerMakie](PerfCheckerMakie/README.md) | 1.0.4 | Figures and plot recipes, with optional WGLMakie rendering |
| [PerfCheckerTachikoma](PerfCheckerTachikoma/README.md) | Pending | Optional keyboard terminal UI and saved-evidence plots |
| [PerfCheckerLinuxPerf](PerfCheckerLinuxPerf/README.md) | 1.0.2 | Optional calling-thread Linux perf-event counter collector |
| [PerfCheckerLIKWID](PerfCheckerLIKWID/README.md) | 1.0.2 | Optional native CPU-window counter collector |

The five published companions install by name from General. For example, prepare
a separate Web controller environment:

```julia
using Pkg
Pkg.activate("perf/controller")
Pkg.add(["PerfChecker", "PerfCheckerWeb"])
using PerfChecker, PerfCheckerWeb
```

Follow the dedicated companion READMEs linked above for installation instructions
and the appropriate controller or worker environment. The CLI
and text REPL remain in PerfChecker. The VS Code client uses the same versioned
process protocol.

Tachikoma 1.0.1 is proposed in [General PR #171531](https://github.com/JuliaRegistries/General/pull/171531)
and is not yet installable by name. Its README gives an immutable source recipe.

## ARM compatibility

All six companions depend on Core. On ARM, including Apple Silicon, use
**Core 1.1.1 or newer**, available in General. It replaces CpuId 0.3.0 with
Julia's native CPU information and Hwloc topology. Core 1.1.0 remains affected.
Update Core in each existing controller or worker project using the
[ARM installation instructions](../website/src/guide/overview.md#ARM-installations).
Successful loading does not establish hardware-counter access.

## Environments and qualification

Use separate controller environments when interfaces require incompatible HTTP
versions. Workers continue to use their own environments; Web/Pluto/Makie renderer
dependencies do not belong in a measurement environment. Counter workers do need
their chosen counter companion and exact target. Keep LinuxPerf 0.4.2 / PrettyTables 2
and LIKWID 0.4.6 / PrettyTables 3 worker projects separate. Missing permissions or
native libraries remain unavailable; native CLI/VSCode/Pluto/MCP counter selection
and hardware HTTP/UI qualification are not supplied by these packages.
See [qualification](../qualification/README.md) for
the shared test matrix and the [website sources](../website/) for the autonomous DocumenterVitepress site.
