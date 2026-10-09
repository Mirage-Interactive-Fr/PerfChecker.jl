```@raw html
<a id="Julia-API"></a>
```

# Full API


This is the complete reference generated from PerfChecker's Julia docstrings,
including documented implementation hooks. Start with the [Public API](public-api.md)
for supported package entry points or [Quickstart](../guide/first-check.md) for an
executable introduction. Internal bindings support extensions and maintenance;
their behavior can change independently of the exported interface.

Each entry retains its Julia signature, argument and result documentation, and a
source link pinned to the revision used to build this site. This page keeps the
historical `reference/api` route and function anchors.

- Existing tests: `discover_testitems`, `run_testitems`.
- Inline experiment: `@check`.
- Custom workloads and version matrices: `SoftwareSuite`, `plan_suite`, `run_suite`.
- Shared scenarios: `run_scenarios`, `diagnose`, `compare_scenarios`.
- Optional MCP APIs: `chat_advice` for bounded conversation; `implement_advice` for an explicit tool on a caller-owned isolated checkout. The caller owns checkpointing and diff review outside the VS Code extension; see [the MCP guide](../mcp-advisor.md).

```@raw html
<a id="Interface-API-ownership"></a>
```

## Interface packages

Some entry points are implemented by an interface package. Install and load the owner to get its method.

- **PerfCheckerWeb** — `serve_suite`, `register_oxygen_routes!`, `register_testitem_routes!`, `studio_token_authenticator`, `run_studio_agent`.
- **PerfCheckerPluto** — `prepare_pluto_dashboard`, `launch_pluto_dashboard`, `write_suite_notebook`, `write_investigation_notebook`.
- **PerfCheckerMakie** — `performance_figure`, `suite_dashboard`, `checkres_to_boxplots`, `checkres_to_scatterlines`, `checkres_to_pie`, `checkres_figures`, `saveplot`.
- **PerfCheckerMakie + WGLMakie** — `performance_plot_html`.
- **PerfCheckerTachikoma** — `SuiteTUI`, `tui_model`, `tui`, `refresh!`, `close!`, `plot_pixels`.
- **PerfCheckerLinuxPerf / PerfCheckerLIKWID** — each owns its own `CounterRecord`, `CounterResult`, `measure_counters`, `counter_bundle`, `counter_command`, `counter_executor`, `run_counter_suite`.

The generated index and docstrings below cover the **PerfChecker module**.
The [six companion Public and Full APIs](optional-api.md) render their real
docstrings separately, with signatures and source links pinned to this site's
source revision. Their isolated projects preserve incompatible dependency
requirements and their methods of shared Core bindings. The supplementary
source references below retain the published `1a7577da782ba8676683f3ceefcb8dccf055afe5`
snapshot and Julia help examples. Install the selected owner
using [the source-companion recipes](../guide/installation.md#Source-companions-for-1.0.1)
before using its methods or Julia help.

### Tachikoma terminal API

See the [companion README](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/blob/1a7577da782ba8676683f3ceefcb8dccf055afe5/packages/PerfCheckerTachikoma/README.md)
for keyboard controls, terminal capability fallback and qualification limits.

| Binding | Contract and source docstring |
| --- | --- |
| `SuiteTUI` | [Model with explicit selection and owned job lifetime](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/blob/1a7577da782ba8676683f3ceefcb8dccf055afe5/packages/PerfCheckerTachikoma/src/PerfCheckerTachikoma.jl#L33) |
| `tui_model(plan; overrides=...)`, `tui_model(suite; profile=:quick, ...)`, `tui_model(result)`, `tui_model(bundle)` | [Construct without opening a terminal or launching a worker; saved evidence is read-only](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/blob/1a7577da782ba8676683f3ceefcb8dccf055afe5/packages/PerfCheckerTachikoma/src/PerfCheckerTachikoma.jl#L66) |
| `tui(input; fps=20, ...)` | [Explicit terminal session; run/cancel/exit controls and cleanup](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/blob/1a7577da782ba8676683f3ceefcb8dccf055afe5/packages/PerfCheckerTachikoma/src/PerfCheckerTachikoma.jl#L453) |
| `refresh!(model)` / `close!(model)` | [Nonblocking polling](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/blob/1a7577da782ba8676683f3ceefcb8dccf055afe5/packages/PerfCheckerTachikoma/src/PerfCheckerTachikoma.jl#L118) / [cancel and await owned work; use from `finally` when embedding](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/blob/1a7577da782ba8676683f3ceefcb8dccf055afe5/packages/PerfCheckerTachikoma/src/PerfCheckerTachikoma.jl#L415) |
| `plot_pixels(bundle, plot_id; size=(800, 480))` | [Saved evidence to RGBA; requires explicitly loaded Makie companion/backend](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/blob/1a7577da782ba8676683f3ceefcb8dccf055afe5/packages/PerfCheckerTachikoma/src/PerfCheckerTachikoma.jl#L14) |

```julia
using PerfChecker, PerfCheckerTachikoma
@doc PerfCheckerTachikoma.tui
model = tui_model(read_run_bundle("reports/run")) # no terminal or measurement
# tui(model) explicitly opens the terminal to consult this saved evidence
```

### Hardware counter APIs

Choose one owner in its separate prepared environment. Qualify names with the
module: similarly named LinuxPerf and LIKWID bindings are different APIs.
The [LinuxPerf README](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/blob/1a7577da782ba8676683f3ceefcb8dccf055afe5/packages/PerfCheckerLinuxPerf/README.md)
and [LIKWID README](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/blob/1a7577da782ba8676683f3ceefcb8dccf055afe5/packages/PerfCheckerLIKWID/README.md)
include complete declared-suite examples and their actual worker requirements.

| Binding | LinuxPerf source docstring | LIKWID source docstring |
| --- | --- | --- |
| `CounterRecord`, `CounterResult` | [Raw UInt64 counts, enabled/running nanoseconds, calling-thread scope and statuses](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/blob/1a7577da782ba8676683f3ceefcb8dccf055afe5/packages/PerfCheckerLinuxPerf/src/PerfCheckerLinuxPerf.jl#L43) | [Raw Float64 event values, declared units, CPU-window/access-mode scope and statuses](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/blob/1a7577da782ba8676683f3ceefcb8dccf055afe5/packages/PerfCheckerLIKWID/src/PerfCheckerLIKWID.jl#L18) |
| `measure_counters(f; events=...)` / `measure_counters(f; event_set, cpuids, units)` | [One calling-thread window; accepted events and unavailable reasons](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/blob/1a7577da782ba8676683f3ceefcb8dccf055afe5/packages/PerfCheckerLinuxPerf/src/PerfCheckerLinuxPerf.jl#L162) | [One native CPU window, exact event declarations and inherited affinity](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/blob/1a7577da782ba8676683f3ceefcb8dccf055afe5/packages/PerfCheckerLIKWID/src/PerfCheckerLIKWID.jl#L115) |
| `counter_bundle(result; case_id="counters", target_id="current")` | [Portable evidence without rerunning or writing files](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/blob/1a7577da782ba8676683f3ceefcb8dccf055afe5/packages/PerfCheckerLinuxPerf/src/provider.jl#L1) | [Portable evidence preserving declared units and raw values](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/blob/1a7577da782ba8676683f3ceefcb8dccf055afe5/packages/PerfCheckerLIKWID/src/provider.jl#L1) |
| `counter_command(id; source, environment, package, target_kind, target_version, ...)` | [Declare an isolated worker without executing it](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/blob/1a7577da782ba8676683f3ceefcb8dccf055afe5/packages/PerfCheckerLinuxPerf/src/provider.jl#L97) | [Explicit event/unit/CPU options and target checks](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/blob/1a7577da782ba8676683f3ceefcb8dccf055afe5/packages/PerfCheckerLIKWID/src/provider.jl#L103) |
| `counter_executor(; bundle_sink=...)` | [Explicit Julia runner adapter; retain unavailable evidence](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/blob/1a7577da782ba8676683f3ceefcb8dccf055afe5/packages/PerfCheckerLinuxPerf/src/provider.jl#L201) | [Explicit Julia runner adapter; retain unavailable evidence](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/blob/1a7577da782ba8676683f3ceefcb8dccf055afe5/packages/PerfCheckerLIKWID/src/provider.jl#L209) |
| `run_counter_suite(plan; strict=false, ...)` | [Run declared `:linuxperf` rows with provider qualification/provenance](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/blob/1a7577da782ba8676683f3ceefcb8dccf055afe5/packages/PerfCheckerLinuxPerf/src/provider.jl#L214) | [Run declared `:likwid` rows with provider qualification/provenance](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/blob/1a7577da782ba8676683f3ceefcb8dccf055afe5/packages/PerfCheckerLIKWID/src/provider.jl#L222) |

```julia
using PerfChecker, PerfCheckerLinuxPerf # in the prepared LinuxPerf environment
@doc PerfCheckerLinuxPerf.run_counter_suite
# For a declared, reviewed counter plan with its target already prepared:
# result = PerfCheckerLinuxPerf.run_counter_suite(plan; strict=false)
```

Reading help or constructing a command does not collect counters. Running the
plan does. Counts have unit `1`; cycles are not duration. Missing permissions or
native libraries produce unavailable evidence, not zero values. Default
CLI/VSCode/Pluto/MCP selectors do not select these executors; hardware HTTP/UI
execution and positive physical counters remain separately unqualified. See
[Optional hardware counters](checks.md#Optional-hardware-counters).

## Index

```@index
Modules = [PerfChecker]
```

```@raw html
<a id="Public-docstrings"></a>
```

## Docstrings

```@autodocs
Modules = [PerfChecker]
Public = true
Private = true
Order = [:module, :constant, :type, :macro, :function]
```
