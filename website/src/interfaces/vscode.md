# VS Code

PerfChecker brings Julia performance checks into the editor: select workloads and
versions, run existing TestItems, inspect saved plots, and investigate results.
Studio opens in a full editor tab beside your source.

```@raw html
<a id="Version-compatibility"></a>
```

```@raw html
<a id="Install-and-prepare"></a>
```

## Install and prepare

The controller is the Julia project that runs PerfChecker and coordinates measurement workers. Create one in `perf/controller`, or select an existing compatible project.

1. Use VS Code **1.96+** and Julia **1.10+**.
2. Install [PerfChecker from the Marketplace](https://marketplace.visualstudio.com/items?itemName=mirage-interactive-fr.perfchecker-vscode), or search Extensions for `@id:mirage-interactive-fr.perfchecker-vscode`. Extension **1.0.3** installs **Core 1.1.1+ within 1.x** for a new controller or integrated Pluto project. Existing guided projects using **Core 1.1.0+ within 1.x** and CLI controllers using **Core 1.0.1** remain compatible. Linux ARM and Apple Silicon require **Core 1.1.1+**.
3. Open your package folder and run **PerfChecker: Open Studio**. In a multi-root workspace, select the intended package.
4. Choose **Set up workspace and create suite**. Create a controller in `perf/controller`, or select an existing project containing compatible PerfChecker packages. Review and confirm the installation when offered.
5. Inspect the selected environment. Existing TestItems also need your package and its test dependencies; guided setup supplies collectors, not every package's dependencies.

Opening Studio starts no measurement and installs no packages. Target workers load the measured package and collectors.

```@raw html
<a id="Get-a-first-result"></a>
<a id="Run-one-existing-item"></a>
<a id="Read-the-result-before-comparing-it"></a>
```

```@raw html
<a id="Run-one-check"></a>
```

## Run one check

1. Open **Feature suite**. Review the generated `perf/suite.jl` and `perf/features/smoke.jl`; replace the identity-check starter with a representative operation.
2. Clear the selection and select one workload, collector and target. Review the exact selected-run preview.
3. Choose **Run 1 selected** and wait for the final status.
4. Choose **Open visual output** to inspect the saved result. Keep the report directory shown in **PerfChecker: Show worker output**.

Filtering changes visibility; it does not deselect hidden runs. **Clear
selection** resets the whole selection, while **Select visible** and **Clear
visible** act on the current filter. A completed measurement without a comparison
policy has no regression verdict.

```@raw html
<DocMedia src="/assets/screenshots/vscode/v101/suite-designer-linux-4fab779.png" alt="Native VS Code suite editor with workload, collector and target controls and a selected-run preview" caption="Existing Linux capture of the 1.0.1 suite designer, commit 4fab779, using a controlled test package. Review the exact selection before running." />
```

```@raw html
<a id="Existing-Julia-TestItems"></a>
```

### Existing Julia TestItems

Choose **Existing Julia tests** in Studio, or **PerfChecker: Discover existing
test items**. In VS Code's **Testing** view, expand your package's PerfChecker
controller and run one item. Inspect its correctness, measured duration and
sample count. **View → Output → PerfChecker test items** prints the JSON
`Evidence:` path.

After changing tests, save the files, choose **Refresh Tests** or **Discover
existing test items**, and wait for the current list before choosing **Run Test**.
Refresh again if you change the selected controller or workspace package.

The whole item includes setup and assertions and has no automatic warmup.
A green functional test does not establish a performance budget.
See [TestItems](../test-items.md) for tags, dependencies and measurement boundaries.

```@raw html
<DocMedia src="/examples/bibliography/vscode/native-items.png" alt="Bibliography export workload completed in native VS Code Testing while another item remains unrun" caption="Recorded Bibliography TestItem execution. This older capture shows the Testing surface, independently of Studio's suite results." />
```

```@raw html
<a id="Design-a-suite-and-compare-targets"></a>
<a id="Visual-suite-editor"></a>
<a id="Results"></a>
<a id="Plot-saved-results"></a>
<a id="Read-normalized-overlays"></a>
<a id="Read-timing-measurements"></a>
```

```@raw html
<a id="Compare-and-inspect-saved-results"></a>
```

## Compare and inspect saved results

In **Feature suite**, add releases or named Git targets, choose the baseline and
candidate, and review the comparison matrix before running. Exact baselines and
grouped baselines with median, mean, minimum or maximum aggregation are supported.
**Save configuration** retains the selection in `perf/perfchecker-ui.json`;
reports retain the measured evidence.

Select a completed suite report and use **PerfChecker: Open visual output**.
Choose a package, feature and view; inspect points for their original value and
unit. **Version series** compares recorded targets. Distributions need samples;
flame graphs need recorded stacks. Missing evidence cannot supply a plot.

BenchmarkTools and Chairmarks histories use four normalized curves on one ratio
axis: elapsed time, GC, bytes and allocation count. Each metric uses its own
minimum; inspect the original values before interpreting a ratio.
[Makie](visualization.md#Normalized-overlay) explains the rule.

For flame graphs, use the frame selector to inspect narrow frames, change
**Color by** and **Labels**, and use **Fit**, zoom and pan. Width represents
recorded weight; depth represents nesting.

```@raw html
<a id="Investigate-and-verify"></a>
<a id="Advice-and-explicit-implementation"></a>
```

```@raw html
<a id="Investigations-and-agent-conversations"></a>
```

## Investigations and agent conversations

**PerfChecker: Open investigations** lets you discover scenarios, measure
declared cases, diagnose with installed analyzers and read deterministic advice.
A proposed case needs an explicit factory and correctness oracle before adoption.
Unavailable analyzers remain unavailable.

**Open saved diagnostic report** reads an existing JSON report without running
Julia. Its hash identifies the loaded bytes; it does not authenticate the report.
**Run bounded investigation** uses declared experiments within count and time
budgets.

**Chat with performance advisor** connects an explicitly selected MCP advice
tool. Advice and implementation use separate controls: review the answer, request
an implementation in an isolated checkout, inspect its diff, then apply or restore.
Follow [MCP connection](../agentic/mcp.md),
[advice and implementation](../agentic/advice.md), and
[providers](../agentic/providers.md) for configuration and recovery.

```@raw html
<a id="Pluto,-terminal-and-debugging"></a>
<a id="Pluto-notebooks-in-VS-Code"></a>
<a id="Julia,-notebooks-and-terminals"></a>
<a id="Investigation-notebooks"></a>
<a id="Dedicated-Julia-terminal"></a>
<a id="Julia-debugging"></a>
```

## Pluto, terminal and debugging

- **New Pluto notebook** creates an editable `.jl` notebook; **Open Pluto notebook** reopens one. Choose a Feature suite or Investigation notebook, review the separate `perf/pluto` installation, then launch the selected action explicitly. Refresh status and save completed reports.
- Pluto saves edited cells to the notebook source. **Open source**, **Stop session** and **Restart session** manage that file's session. Stop it before editing source externally. Closing the notebook tab requests shutdown.
- **Open Julia terminal** starts a dedicated session in the selected controller. Check `VERSION` and `Base.active_project()` there.
- **Debug current Julia file** delegates a saved source file to the installed Julia extension. Inspect the debugger's actual project; stepping is separate from performance measurement.

Keep Pluto separate from an HTTP 2 MCP controller: the qualified Pluto **1.0.4**
environment uses HTTP 1.x and **PerfCheckerPluto 1.0.1**. Updating the companion
does not rewrite old generated notebooks; create a new notebook to adopt corrected
plot cells. For standalone notebooks, use [Pluto](pluto.md).

::: warning Known limitation in 1.0.3: Pluto on Intel macOS

The first integrated Pluto notebook may fail to be created on Intel macOS. In
the release qualification, the expected notebook file was still absent after
one hour. The cause remains undetermined, so this integration is not fully
qualified on Intel macOS. A correction is planned for the next extension
version. The passing configured and prepared notebook cases do not remove this
first-use limitation. Standalone notebook setup is documented in [Pluto](pluto.md).

:::

```@raw html
<a id="Open-a-saved-diagnostic-report"></a>
<a id="Try-the-recorded-Oxygen-reports"></a>
```

::: details Import a saved diagnostic report

Use **PerfChecker: Open saved diagnostic report**, select a regular UTF-8
`perfchecker-diagnosis/1` JSON file (up to 32 MiB), then read the import notice,
source path, scope and limitations. **Open imported JSON snapshot** shows the
loaded text without rereading or changing the original. Invalid files preserve
the previous view; finish an active investigation before importing.

Latency cards separate source loading, first lifecycle and warm lifecycle in
seconds. Reachable-memory rows show state before, state after, and state plus
result in bytes; they are separate from allocation traffic and process RSS.

Download a genuine Oxygen report to try the import:

```@raw html
<p>Oxygen 1.10.2: <a href="../examples/real-packages/oxygen-saved-diagnostics/latency-1.10.2.json">latency</a> · <a href="../examples/real-packages/oxygen-saved-diagnostics/memory-1.10.2.json">memory</a>. Oxygen 1.11.0: <a href="../examples/real-packages/oxygen-saved-diagnostics/latency-1.11.0.json">latency</a> · <a href="../examples/real-packages/oxygen-saved-diagnostics/memory-1.11.0.json">memory</a>.</p>
```

These reports retain **performance: not_compared**. Their separate dependency
environments and diagnostic observations do not establish a regression.

:::

```@raw html
<a id="Cancel-a-run-and-wait-for-cleanup"></a>
```

```@raw html
<a id="Cancel-and-recover"></a>
```

## Cancel and recover

Use **Cancel**, then wait for the final worker status before another run. A clean
interruption finishes as cancelled; a cleanup failure finishes as failed and
retains diagnostics in worker output. The extension allows 60 seconds for
controller cleanup before forcing a stop with a warning. Inspect retained
inventories before restarting; see [allocation cleanup](../reference/checks.md).

A local MCP cancellation disconnects its session; reconnect explicitly.
A remote HTTP tool or worker can continue after the local request closes.
See [remote workers](web-studio.md#Cancel-and-stop-safely).

```@raw html
<a id="Core-and-suite-settings"></a>
```

```@raw html
<a id="Settings"></a>
```

## Settings

Use folder settings in a multi-root workspace. Paths resolve from that package
folder. An executable setting accepts an executable or launcher, not a shell
command with added arguments.

```json
{
  "perfchecker.juliaExecutable": "julia",
  "perfchecker.runnerProject": "perf/controller",
  "perfchecker.suite": "perf/suite.jl",
  "perfchecker.plutoProject": "perf/pluto"
}
```

The tables below use the `perfchecker.` prefix. Optional packages are installed
only through an explicit setup action.

::: details Controller, suite and TestItem settings

| Setting | Default | Purpose |
| --- | --- | --- |
| `juliaExecutable` | `julia` | Julia executable or launcher |
| `runnerProject` | `perf` | Controller; default-only fallback to `perf/controller` if `perf/Project.toml` is absent |
| `suite` | `perf/suite.jl` | Suite file |
| `factory` | `build_suite` | Zero-argument suite factory |
| `profile` | `quick` | `quick`, `ci`, `historical` or `release` |
| `reports` | `perf/results/vscode` | Suite report directory |
| `uiConfiguration` | `perf/perfchecker-ui.json` | Shared selection file |
| `gitTargets` | `[]` | Named package/revision targets; optional source and compatibility version |
| `comparisonPolicies` | `[]` | Baselines, candidates, comparison key and aggregation |
| `plutoProject` | `perf/pluto` | Separate notebook environment |
| `testItemTags` | `[]` | Any selected tag; empty selects all except `test_only` |
| `testItemExcludeTags` | `[]` | Additional excluded tags |
| `testItemSamples` | `1` | Repetitions, each in a fresh worker |

The visual editor manages targets and comparison policies. See
[comparison configuration](../reference/comparisons.md) for their fields.

:::

::: details Scenario and investigation settings

| Setting | Default | Purpose |
| --- | --- | --- |
| `scenarioCatalog` | `perf/scenarios.toml` | [Catalog of declared workloads, factories and collectors](../tools/scenarios.md#Declare-a-catalog) |
| `scenarioProject` | `perf` | Worker environment; same default fallback as `runnerProject` |
| `scenarioSamples` | `10` | Fresh-state samples |
| `scenarioThreads` | `1` | Threads per scenario worker |
| `analysisTools` | `["jet", "alloccheck", "latency"]` | Requested installed analyzers |
| `analysisTimeout` | `120` | Worker deadline in seconds |
| `investigationReports` | `perf/results/investigations` | Saved investigation evidence |
| `investigationMaxExperiments` | `4` | Maximum declared experiments |
| `investigationBudgetSeconds` | `300` | Total deadline including startup and requests |

Prepare the target, scenario dependencies and analyzers in `scenarioProject`.
An import in the controller does not establish availability in a target worker.

:::

::: details Advice, MCP and implementation settings

Use **Configure MCP connection and models** for HTTP, or **Connect local MCP
server (stdio)** for an explicit editor-session connection. Both need `HTTP`
in the controller. The local executable runs on the extension host, including
Remote SSH/container hosts. Connection discovery sends no saved evidence.

| Setting | Default | Purpose |
| --- | --- | --- |
| `advisorEnabled` | `true` | Permit explicitly requested optional advice |
| `advisorConfig` | empty | JSON configuration path; overrides provider settings |
| `advisorProtocol` | `chat_completions` | Chat requires `mcp_http`; other protocols serve other advice APIs |
| `advisorEndpoint` | `http://127.0.0.1:8081/v1/chat/completions` | Existing provider endpoint |
| `advisorModel` | `local` | Model for non-MCP protocols |
| `advisorInstructions` | empty | Additional advice instructions |
| `advisorMcpTool` | empty | Explicit advice tool |
| `advisorMcpPromptArgument` | `prompt` | Tool's prompt argument |
| `advisorMcpArguments` | `{}` | Required extra arguments, without secrets or prompt override |
| `advisorMcpResponse` | `text` | Chat uses text; [structured responses](../agentic/advice.md#Bounded-investigations) contain validated evidence IDs and a declared experiment selection |
| `advisorMcpVersion` | `2026-07-28` | Supported protocol revision; also accepts `2025-11-25` |
| `advisorAllowRemote` | `false` | Permit remote HTTPS evidence transmission |
| `advisorKeyEnvironment` | empty | Environment variable holding the credential |
| `advisorTimeout` | `90` | Total provider-worker deadline in seconds |
| `advisorInvestigates` | `false` | Permit structured selection of declared experiments |
| `advisorMcpStdioCommand` | empty | Absolute native executable prefilling the connection form |
| `advisorMcpStdioArguments` | `[]` | Literal executable argument array |
| `advisorMcpStdioDirectory` | empty | Absolute working directory; empty prefills selected folder |
| `codexExecutable` | `codex` | Executable for the optional explicit Codex connection |
| `advisorImplementationMcpTool` | empty | Separate implementation tool |
| `advisorImplementationMcpPromptArgument` | `prompt` | Implementation prompt argument |
| `advisorImplementationMcpWorkspaceArgument` | `workspace` | Isolated-checkout argument |
| `advisorImplementationMcpArguments` | unset | Independent arguments; unset falls back to advice arguments |

The prompt and workspace argument names must differ. Extra arguments cannot
override them. The implementation tool must honor and access the supplied
checkout; remote HTTPS supplies no filesystem access. Live stdio connections
are session-only and take precedence over saved provider settings until
disconnected. Keep credentials out of settings and argument fields.

:::

::: details Manual controller setup

Run from your package root, using a fresh controller project:

```julia
import Pkg
Pkg.activate("perf/controller")
Pkg.add([
    Pkg.PackageSpec(name = "PerfChecker", version = "1.1.1 - 1"),
    Pkg.PackageSpec(name = "BenchmarkTools"),
    Pkg.PackageSpec(name = "Chairmarks"),
    Pkg.PackageSpec(name = "TestItemRunner"),
])
Pkg.develop(path = ".")
```

Add the package's test dependencies deliberately; add `HTTP` for MCP.
Set `runnerProject` to `perf/controller` and inspect it with **Open Julia
terminal**. Extension 1.0.3 uses Core 1.1.1+ within 1.x for new projects;
existing guided projects with Core 1.1.0+ within 1.x and CLI controllers with
Core 1.0.1 remain compatible. ARM hosts require Core 1.1.1+.

:::

::: details Companion extension commands

An extension can target a workspace folder explicitly with
`perfchecker.openStudioForWorkspace(uri)` or
`perfchecker.openDesignerForWorkspace(uri)`.
`perfchecker.runLandscapeLiveForWorkspace(uri, quality)` requires the actual
Beautiful Landscape game, assets, renderer environment, quality configuration
and `perf/live_provider.jl`. The companion owns the scene and rendering;
PerfChecker retains measured evidence. Current CPU/submission-interval metrics
do not establish GPU timing or displayed frame rate.

:::

```@raw html
<a id="Qualification-and-reporting-a-problem"></a>
<a id="Resolve-common-problems"></a>
```

```@raw html
<a id="Troubleshooting-and-qualified-scope"></a>
```

## Troubleshooting and qualified scope

| Symptom | Check |
| --- | --- |
| Controller import fails | Selected folder, `Project.toml`, Core version and test dependencies |
| Analyzer unavailable | The analyzer and target dependencies in `scenarioProject` |
| No plots | Completed suite reports with the required observations or stacks |
| Saved MCP settings ignored | `advisorConfig` or an active session connection takes precedence |
| Chat configuration refused | `mcp_http`, text mode, actual tool schema and required arguments |
| Pluto cannot resolve HTTP | Separate `plutoProject` from the MCP controller |
| First integrated Pluto notebook is not created on Intel macOS | Known 1.0.3 limitation above; retain the Pluto output when reporting it |
| Notebook or cleanup error | **View → Output → PerfChecker Pluto** or **Show worker output** |

The screenshots retain their **1.0.1** provenance and that release's recorded limits.
The **1.0.3** release retains the results and limitations recorded in its
[release report](https://github.com/Mirage-Interactive-Fr/PerfCheckerVSCode/releases/tag/v1.0.3).
The [native qualification](https://github.com/Mirage-Interactive-Fr/PerfCheckerVSCode/actions/runs/38826278250/attempts/1)
passed **34 of 35 functional groups**: all seven groups on Linux and Windows
with VS Code 1.96/stable, and six of seven on Intel macOS with stable VS Code.
The remaining Intel group failed during first integrated Pluto notebook
creation, as described above. The campaign is therefore a recorded failure;
the release accepts this known limitation rather than claiming a complete pass.

Separate fresh-install bootstrap checks passed **45 cases on nine lanes**:
[25 x64 cases](https://github.com/Mirage-Interactive-Fr/PerfCheckerVSCode/actions/runs/38769699307)
and [20 Linux ARM / Apple Silicon cases](https://github.com/Mirage-Interactive-Fr/PerfCheckerVSCode/actions/runs/38772625253).
They loaded registered Core 1.1.1 in both the controller and Pluto project.
These bootstrap checks do not establish full ARM feature coverage or native
qualification of upgrades to existing Pluto projects.

MCP and provider tests use controlled protocol fixtures; they do not establish
commercial model inference or physical GPU support. Arbitrary Pluto cleanup
callbacks and a second cancellation during cleanup remain outside the recorded
guarantees. Consult the release report for collector availability and the scope
of each teardown check.

Use the [extension release reports](https://github.com/Mirage-Interactive-Fr/PerfCheckerVSCode/releases)
for the scope of each released build. Report UI issues to
[PerfCheckerVSCode](https://github.com/Mirage-Interactive-Fr/PerfCheckerVSCode/issues/new)
and Julia execution issues to
[PerfChecker.jl](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/issues/new).
Include versions, selected projects, the action and redacted output.
