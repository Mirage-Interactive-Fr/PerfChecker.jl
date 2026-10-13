# PerfChecker companions

These are independently installable Julia companions in the PerfChecker repository.
Each depends on the public PerfChecker engine. Loading the engine does not install
or load any of them. Interface sessions and jobs remain explicit; there is no
global active PerfChecker interface.

| Package | General version | Use |
| --- | --- | --- |
| [PerfCheckerWeb](PerfCheckerWeb/README.md) | 1.0.0 | Oxygen Studio, HTTP routes and remote agents |
| [PerfCheckerPluto](PerfCheckerPluto/README.md) | 1.0.1 | Notebook generation, reactive controls and Pluto launch |
| [PerfCheckerMakie](PerfCheckerMakie/README.md) | 1.0.1 | Figures and plot recipes, with optional WGLMakie rendering |
| [PerfCheckerTachikoma](PerfCheckerTachikoma/README.md) | Pending | Optional keyboard terminal UI and saved-evidence plots |
| [PerfCheckerLinuxPerf](PerfCheckerLinuxPerf/README.md) | 1.0.1 | Optional calling-thread Linux perf-event counter collector |
| [PerfCheckerLIKWID](PerfCheckerLIKWID/README.md) | 1.0.1 | Optional native CPU-window counter collector |

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
PerfCheckerMakie 1.0.4, used by this documentation, is also a source version;
General currently supplies 1.0.1. See the [renderer installation](../website/src/interfaces/visualization.md)
when reproducing the newer interactive figures.

The working source candidates are Core 1.1.1, PerfCheckerLinuxPerf 1.0.2 and
PerfCheckerLIKWID 1.0.2. They are not yet registered; General still provides
Core 1.1.0 and the companion versions listed above.

## ARM compatibility

All six companions depend on Core. The published Core 1.1.0 pins CpuId 0.3.0,
whose import can fail on aarch64, including Apple Silicon. Installing a
companion by name does not bypass that dependency. The Core 1.1.1 source candidate
replaces CpuId with portable Hwloc topology and a native Julia fallback. It needs
its own validation and release before General installations benefit from it;
registration alone does not establish ARM compatibility. See the
[reported failure](https://github.com/JuliaRegistries/General/pull/171531#issuecomment-6145459097).

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
