# PerfChecker Studio in VS Code

PerfChecker combines Julia performance tests, saved results, plots and optional agent conversations inside VS Code. **Studio opens as a full editor tab**: keep it beside your source, move it into another editor group, or return to the compact PerfChecker views in the activity bar.

Follow this page for a first measurement and a version comparison. Continue with
[configuration](vscode-configuration.md), [plots and Julia tools](vscode-workflows.md)
or [MCP advice and implementation](../mcp-advisor.md) when you reach those steps.

The guides include **native VS Code captures** and earlier webview captures.
Each caption identifies its source and whether it shows demonstration data or
measured package results. Select an image to inspect it at full resolution.
The editor's theme and layout can differ on your machine.

Extension **1.0.1** adds integrated Pluto notebooks, guided workspace setup,
generic HTTP/stdio MCP connections and additional plot controls. See the
[release notes and download](https://github.com/Mirage-Interactive-Fr/PerfCheckerVSCode/releases/tag/v1.0.1)
and the [platform qualification](#Qualification-and-reporting-a-problem).
The earlier native suite-designer captures below use extension commit
[`4fab779`](https://github.com/Mirage-Interactive-Fr/PerfCheckerVSCode/commit/4fab779eae49968b3233fab6ed1d48e4acfbd1b3)
in VS Code 1.141.0 on Linux, with a controlled test package. The
[profile walkthrough](vscode-workflows.md#Follow-a-recorded-profile) shows
separately recorded, measured DataStructures results.

## Version compatibility

Choose a released extension from the Marketplace. Guided controller setup and
integrated Pluto check these versions:

| Extension | Core accepted by guided setup and integrated Pluto | Pluto companion |
| --- | --- | --- |
| 1.0.1 | 1.0.1 or newer within the 1.x series | PerfCheckerPluto 1.0.1 or newer within the 1.x series |
| 1.0.2 | 1.1.0 or newer within the 1.x series | PerfCheckerPluto 1.0.1 or newer within the 1.x series |

Both notebook integrations use Pluto 1.0.4 and the companion source at the root
`v1.0.1` tag while its separate General registration is pending. The companion
tag is independent of the Core version. Guided setup shows the required version
before installation; an existing controller or Pluto environment needs an
explicit upgrade when it does not meet those setup checks.

## Install and prepare

1. Install VS Code **1.96 or newer** and Julia **1.10 or newer**.
2. Install [PerfChecker from the Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=mirage-interactive-fr.perfchecker-vscode), or search the Extensions view for `@id:mirage-interactive-fr.perfchecker-vscode`. You can also download the [1.0.1 VSIX](https://github.com/Mirage-Interactive-Fr/PerfCheckerVSCode/releases/download/v1.0.1/perfchecker-vscode-1.0.1.vsix) and use **Extensions → … → Install from VSIX…**. Reload VS Code if prompted. See [VS Code's installation instructions](https://code.visualstudio.com/docs/configure/extensions/extension-marketplace) for either route.
3. Open the package folder. Trust the workspace when you are prepared to execute its Julia code.
4. Run **PerfChecker: Open Studio** from the command palette. In a workspace with several folders, select the package to inspect.
5. Choose **Set up workspace and create suite**, then **Create controller environment**. Review the required Core version and packages, then confirm **Install controller**. Setup installs that Core version, BenchmarkTools, Chairmarks and TestItemRunner in `perf/controller`, and selects it as this folder's runner project. This step downloads Julia packages; opening Studio alone does not.
6. When setup finishes, open **Feature suite** in Studio. Inspect the generated starter or your existing suite before selecting a run. Continue with [Get a first result](#Get-a-first-result) below.

If a suitable controller already exists, choose **Use an existing controller**
instead. For a custom Julia executable, additional collectors, scenario workers
or package test dependencies, follow [VS Code configuration](vscode-configuration.md).

The [extension release notes](https://github.com/Mirage-Interactive-Fr/PerfCheckerVSCode/releases/tag/v1.0.1)
identify the qualified artifact. PerfChecker's Julia registry release and its VS Code
extension are distributed separately; installing the Julia package does not
install the extension.

Opening Studio reads configuration and presents actions. It does not install packages, start Julia, download a model or launch an agent. A controller should contain `HTTP` if you enable MCP. JET and other analyzers belong in the environment selected for their workers.

```@raw html
<DocMedia src="/assets/screenshots/vscode-studio.png" alt="PerfChecker V1 Studio webview rendered in Chromium, with the selected Example package and actions for suites, results, Julia tests and agent chat" caption="Start here: check the selected package and expand Workspace environment to inspect its controller, then choose an action. This is the running extension webview with a demonstration workspace." />
```

The [guided setup](vscode-configuration.md#Guided-setup-from-Studio) keeps the
controller separate from your package's normal dependency environment. For an
advanced or manually prepared environment, use [Prepare a controller](vscode-configuration.md#Prepare-a-controller).
Existing TestItems also need the package under test and its test dependencies
in that controller; guided setup does not install them automatically.

See [Installation](../guide/installation.md) for the core and interface packages, and [VS Code configuration](vscode-configuration.md) for complete settings and environment examples.

```@raw html
<a id="Run-one-existing-item"></a>
<a id="Read-the-result-before-comparing-it"></a>
```

## Get a first result

1. In Studio, open **Feature suite**. For a newly generated suite, review `perf/suite.jl` and `perf/features/smoke.jl`. The starter checks the package identity; replace it with a representative operation before assessing application performance.
2. Clear the selection, then select one check and target. Review the exact selected-run preview; filtering alone does not deselect hidden runs.
3. Choose **Run 1 selected**. The first run may need to prepare its target environment; installation and worker startup are separate from its measured operation.
4. Read the run's collection and correctness status. Open its **Open visual output** control to inspect the saved measurements. A completed measurement without a comparison policy is not a performance-regression verdict.
5. Keep the report directory shown in the worker output. Use [saved plots](vscode-workflows.md#Plot-saved-results) to reopen it and [Design a suite and compare targets](#Design-a-suite-and-compare-targets) for a two-version experiment.

### Run existing TestItems

For a project using `@testitem`:

1. Studio → **Existing Julia tests**, or command palette → **PerfChecker: Discover existing test items**.
2. Open VS Code's **Testing** view and expand the PerfChecker controller named for your selected folder.
3. Select one item and run it. PerfChecker measures the selected item in a fresh worker.
4. Inspect the item's Testing output for measured milliseconds, sample count and correctness. The summary includes setup and assertions; it does not compare a performance budget.
5. Open **View → Output** and select **PerfChecker test items**. Follow the `Evidence:` file path to inspect the JSON report's item validation and each sample's `seconds`, `bytes` and `correctness`.

If your package has no test items yet, add a small correctness-checked example to
`test/performance.jl`:

```julia
using TestItems

@testitem "Vector reduction" tags = [:performance] begin
    data = collect(1:10_000)
    @test sum(data) == 50_005_000
end
```

Save the file, discover again and select **Vector reduction**. The item measures
its setup and assertion as well as the reduction; use a [shared scenario](../shared-scenarios.md)
when you want prepared inputs outside the measurement. The ordinary `performance`
tag is an example filter, not a required or special tag. The package must have
`TestItems` available for its test declarations.

The Testing session's elapsed time can include worker startup. Each item's reported measured duration has its own boundary. A green functional test does not establish a performance budget. Use [TestItems and tags](../test-items.md) to distinguish shared, functional-only and performance-only items.

Native TestItem JSON is a separate result from a suite report. The extension's
**Open visual output** reads saved suite measurements; prepare and run a suite
for the distribution, profile and version-series workflow below.


Browse the [video walkthroughs](vscode-videos.md) for the related workflow.

For a suite, use **PerfChecker: Create feature suite** if you need a starter, or configure your existing `perf/suite.jl`. Studio → **Feature suite** opens the full visual editor. Select a workload, checks and a target, run that selection, then open the resulting report.

## Work across the full editor

| Surface | Purpose |
| --- | --- |
| Studio | Start the workflow, inspect the selected project and open the next action |
| Suite designer | Choose features, checks, targets and comparisons |
| Testing view | Discover and run existing Julia TestItems |
| Visual output | Inspect saved distributions, allocations, flame graphs and version comparisons |
| Investigations | Discover scenarios, measure, diagnose and read deterministic advice |
| Advisor chat | Discuss saved evidence; explicitly request implementation and review its diff |
| Pluto notebook | Edit reactive Julia cells and explicitly launch suite checks or investigations |
| PerfChecker terminal | Use a dedicated Julia session in the controller project |

These are VS Code editor tabs and native surfaces. Arrange them with VS Code's editor groups; the activity bar is an entry point, not the available working area.

### Choose an action and its prerequisites

| Action | Prepare first | Guide |
| --- | --- | --- |
| Existing TestItems | Runner, TestItems/TestItemRunner 1.3.2 or newer, package test dependencies | [First result](#Get-a-first-result) |
| Suite selection and comparison | Suite factory, collectors, declared target environments | [Design and compare](#Design-a-suite-and-compare-targets) |
| Visual output | Completed suite reports containing the requested observations | [Saved plots](vscode-workflows.md#Plot-saved-results) |
| Integrated Pluto | Compatible extension/Core versions from the table above and a separate Pluto project | [Notebook workflow](vscode-workflows.md#Pluto-notebooks-in-VS-Code) |
| Julia terminal or debugger | Julia/controller; Julia extension and saved source for debugging | [Julia tools](vscode-workflows.md#Dedicated-Julia-terminal) |
| Advice conversation | Authenticated supported CLI or configured MCP advice tool | [MCP connection](../mcp-advisor.md#Choose-a-connection) |
| Reviewed implementation | Saved files, Git HEAD and a separate implementation tool | [Review and apply](../mcp-advisor.md#Switch-from-advice-to-implementation) |
| Cancel, stop or restore | Wait for cleanup and review repository drift | [Cancellation](#Cancel-a-run-and-wait-for-cleanup) |
| Beautiful Landscape companion | Actual game assets, renderer environment, explicit quality profile and corrected Core 1.0.1 | [Live measurement](vscode-workflows.md#Measure-a-Beautiful-Landscape-scene) |

```@raw html
<a id="Visual-suite-editor"></a>
```

## Design a suite and compare targets


The suite editor supports global and per-feature check selection, version ranges, filtering, sorting and ordering. Name targets for a branch, tag, commit, working tree or release, then choose exact or grouped baselines. Grouped references can use median, mean, minimum or maximum aggregation.

The corrected 1.0.1 suite designer orders numeric target labels first: `1`,
`1.2` or `1.2.3`, optionally prefixed by `v` or `dev@`, with prerelease and build
suffixes. Prereleases precede their matching release; numeric prerelease
components compare as numbers and precede text components, which use ASCII
order. A shorter otherwise equal prerelease precedes a longer one. At equal
version precedence, a release label precedes `dev@`; remaining label ties use
lexical order. Opaque Git labels follow lexically, and bare `dev` comes last.
For example:
`0.1.0 < dev@0.1.0 < 0.5.0 < baseline < dev`.

Release bounds compare version precedence rather than label spelling or build
metadata: `1`, `1.0` and `1.0.0` are equivalent, and a bound of `1.2.3` includes
the release label `v1.2.3+build.7`. These bounds apply to declared release
targets. Sorting and filtering control the suite selection; they do not change
the recorded version-series data.

Save the selection with **Save configuration** in the suite editor. The default
is `perf/perfchecker-ui.json`; compatible web and documentation interfaces can
read the same configuration. Extension 1.0.1 also fixes the separate command-palette
action **PerfChecker: Save shared UI configuration**. If you still use 1.0.0,
save with the editor button or upgrade. Running the selection
shows progress and leaves saved evidence for later review.

The editor separates filtering from selection. Search, package/target filters and release bounds change what is visible without deselecting hidden runs. **Select visible** and **Clear visible** act on the current filter; **Clear selection** affects the entire selection. The counter reports selected runs, visible runs and selected runs outside the filter. **Run N selected** includes those hidden selections, so review the exact identifier preview before execution. **Show more** pages workload groups without restricting bulk selection.

Collector toggles select or deselect matching runs. Unavailable conditions show their reason. Add targets from discovered branches, tags and recent commits or enter a supported ref/URL, then inspect the comparison matrix. Missing or overlapping references are reported before a run; refreshing the plan preserves existing selections when their identifiers still exist.

```@raw html
<DocMedia src="/assets/screenshots/vscode/v101/suite-designer-linux-4fab779.png" alt="Detail of the native VS Code 1.141.0 PerfChecker suite editor, with collector toggles, filter controls and the exact selected-run preview" caption="Native Linux capture, extension candidate 4fab779, cropped to the Suite editor without altering its contents. Review the exact runs before executing: filtering changes visibility, while selection determines what runs. PerfCheckerNativeFixture is the controlled test package." />
```


```@raw html
<a id="Results"></a>
```

## Choose the evidence for your question


| Question | Start with | Read before selecting |
| --- | --- | --- |
| Did this operation become slower? | `benchmark` or `chairmark` | Samples, time units, prepared inputs and the same collector for both targets |
| Which call path uses CPU time? | `profile` | Stack sample weights; an empty capture does not prove zero cost |
| Where do allocations occur? | `profile_alloc` or `alloc` | Sampling/source-line scope and measured totals |
| Why does waiting dominate? | `wall_profile` | Requires Julia 1.12 or newer; task stacks include waits |
| How much traffic does the operation generate? | A network collector | Reported counters, shared interface or isolated namespace have different attribution |

The designer shows combinations made available by your suite and environment;
it does not install a missing collector. See [Collectors](../reference/checks.md)
for every supported check and its interpretation.

### Compare a working change with a known revision


1. Prepare a suite containing the same workload for both targets.
2. Add a named baseline from a branch, tag or recent commit. Prefer a full commit
   identifier when you need an unambiguous recorded reference.
3. Add the candidate working tree or another supported revision, and inspect the
   plan's resolved target information. A Git target is a version of the measured
   package; `juliaExecutable` separately chooses the Julia runtime.
4. Choose an exact baseline for a simple before/after comparison. Use grouped
   references only when their aggregation answers your question.
5. Select the same checks and inputs for both targets. Inspect selected runs,
   including any hidden by filters, then run the selection.
6. Open both saved reports and inspect correctness, comparison compatibility and
   the observations. Retain the baseline until the candidate is validated.

```@raw html
<DocMedia src="/assets/screenshots/vscode/v101/git-reference-linux-4fab779.png" alt="Native VS Code suite editor with workload and collector selections beside the Comparison targets panel, discovered Git reference selector, reference input and Add comparison target button" caption="Choose a discovered reference or enter one explicitly, inspect its label, then add the target. This native 4fab779 capture demonstrates the real controls with a test package; it does not establish a performance difference." />
```

Changing a branch name or editor selection does not manufacture a compatible
baseline. The saved evidence records the actual measured configuration.

The suite tree follows:

```text
package → feature → check type → target
```

Read [Suites and comparisons](../suites-and-comparisons.md) before interpreting a result across environments or machines. Never infer an improvement from a profile weight alone.

### Read a flame graph with names and colors

In the saved suite's visual output, select the CPU collector and **View →
Flame graphs**. Keep the package, workload, release and metric visible while
following a call path.

- **Color by → Function** uses stable colors for function names. Colors help
  follow calls; they do not indicate speed, improvement or an inference
  diagnostic. Different names can share a color.
- **Color by → Diagnostics** shows recorded runtime-dispatch, non-concrete
  inference and garbage-collection markers. An `unknown` or missing inference
  status is not a warning. Read the legend and the selected frame's details.
- **Labels → Function name** keeps recognized Julia frame labels compact.
  **Full frame** includes their source location. Labels that do not fit are
  hidden; **Inspect frame** and the readout still expose the complete call path.
- Use **Zoom +**, the pan arrows and **Fit** to explore without changing the
  saved weights. Frame widths include child calls, so parent and child weights
  must not be added together.

These complementary views show one **DataStructures 0.18.13**, **heap_2048**
CPU capture, not a comparison between versions. It contains 425 retained
samples. Frame 3 attributes 299 of them, about 70.35%, to the inclusive
`pop! → heappop! → percolate_down!` path. This share is neither elapsed time
nor a percentage slowdown.

::: tabs

== Controls

```@raw html
<DocMedia src="/assets/screenshots/vscode/v101/datastructures-cpu-01813-controls-e68a.png" alt="Native VS Code event_lab output for DataStructures 0.18.13 heap_2048, showing Color by Function, Labels Function name and the function-color legend" caption="Choose the presentation mode explicitly. This native viewport shows the controls; the graph and inspector are shown in the next tabs." />
```

== Zoomed call path

```@raw html
<DocMedia src="/assets/screenshots/vscode/v101/datastructures-cpu-01813-zoom-e68a.png" alt="Native VS Code CPU flame graph zoomed to the real pop!, heappop! and percolate_down! branch, with complete function names and varied function colors" caption="Zoom reveals function names in the selected branch. Narrow frames remain in the saved model even when their labels do not fit." />
```

== Complete inspector

```@raw html
<DocMedia src="/assets/screenshots/vscode/v101/datastructures-cpu-01813-inspector-e68a.png" alt="Native VS Code inspector showing Frame 3 of 94, inclusive weight 299, metric julia.cpu.samples, the full heap-pop source path and Julia inference unknown" caption="The inspector preserves the full source path and the recorded unknown inference status. Its 70.352941% value is a share of this capture's 425 samples." />
```

:::

The [profile walkthrough](vscode-workflows.md#Follow-a-recorded-profile)
includes separate CPU, wall-time and allocation views for DataStructures 0.19.6.

::: details Capture provenance

The images are unchanged native viewports captured on 10 October 2026 (UTC)
with the published 1.0.1 viewer, archive `e68a9264…`, built from extension
source [`53d22da`](https://github.com/Mirage-Interactive-Fr/PerfCheckerVSCode/commit/53d22da767664e1072bdfa576dd13bbfa05b7dc5).
They read historical bundle `8f2ffde5-55b9-43de-b35a-08503f9b6639`, measured on
Linux with Julia 1.13.1 using Core development source
[`63f5cc4`](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/commit/63f5cc4bfc2c55de521487f68b0df143107762f3).
The data was not recollected with General 1.0.1. Each tab shows a different
scroll position, rather than all controls and details at once.

:::

```@raw html
<a id="Optional-investigations"></a>
```

## Investigate and verify


Use **PerfChecker: Open investigations** for shared scenarios. **Discover scenarios from tests** inspects declarations and proposes candidates without executing the target program. Proposed candidates need an explicit factory and correctness oracle before they become measurable cases.

- **PerfChecker: Browse tool catalogue** opens the installed controller's
  inventory. A listing does not install a tool or qualify its results.
- **PerfChecker: Relate scenarios to CI** proposes combinations from declared
  scenarios and literal CI matrices. It does not establish that a CI job runs
  them; dynamic expressions and reusable workflows can remain unresolved.
- **PerfChecker: Prepare a shared case from a test** opens an unsaved Julia
  draft for a discovered proposal. Complete its factory and correctness oracle,
  save it inside the package, then use **Adopt a shared factory into the
  catalogue → Add declaration** explicitly. Preparation does not rewrite the
  original tests, adopt the draft or run a measurement.

Measure declared cases, diagnose with available analyzers, and choose **Advise from saved evidence**. Missing analyzers appear as unavailable; they are not installed automatically. After a change, rerun the same correctness checks and compare compatible before/after measurements.

**Run bounded investigation** can select declared experiments within count and time budgets. Optional model selection requires structured MCP replies and `advisorInvestigates = true`; it remains separate from implementation chat.

Extension **1.0.1** also provides **PerfChecker: Open saved
diagnostic report**. It displays an existing diagnostic JSON file without
running Julia or adding a history entry. The imported report keeps its reported
statuses; its SHA-256 identifies the loaded bytes and does not verify their
origin or conclusions. See [saved diagnostic reports](vscode-workflows.md#Open-a-saved-diagnostic-report)
for the file limit, latency cards and reachable-memory table.

## Cancel a run and wait for cleanup


Use **Cancel** in a suite execution notification, the suite Testing profile, an
investigation or a native Testing run. PerfChecker asks the Julia controller to
interrupt its current task and finish its cleanup. Accepting that request does
not mean cleanup has finished: wait for the final run status. Closing a suite or
investigation editor also requests cancellation. A new run stays blocked until
the previous controller has closed.

A clean interruption finishes as cancelled. If cleanup fails, the run finishes
as failed; **PerfChecker: Show worker output** contains the cause and any retained
private inventory directory. See [allocation cleanup](../reference/checks.md)
before handling leftover traces or recovering an inventory.

The extension allows **60 seconds** for the controller to finish. If that deadline
expires, it forces the controller to stop and displays a warning that cleanup was
not confirmed. Detached workers, allocation traces or inventories may remain.
Closing VS Code forcibly, an operating-system shutdown or repeated interruption
can also prevent cleanup; restarting the extension does not delete old `.mem`
files indiscriminately.

Cancelling a request through a local stdio or optional Codex connector waits for
that connector to disconnect and its owned processes to stop. Reconnect
explicitly before asking another question. If cleanup fails, PerfChecker keeps
the isolated implementation copy and checkpoint, blocks new requests and asks
you to retry the relevant **Disconnect** action. It does not silently delete
those recovery materials. See [checkpoints and recovery](../mcp-advisor.md#Checkpoints-and-recovery).

A remote HTTP server or agent may continue working after the local request
closes. Local cancellation does not prove that remote work stopped or that an
agent made no edits.

## Advice and explicit implementation

Studio → **Talk to your agent** opens **PerfChecker: Chat with performance advisor**. Choose **Configure MCP connection** for a [saved HTTP advice tool](../mcp-advisor.md#Configure-the-advice-tool), or **Connect local MCP server** for an [explicit stdio connection](../mcp-advisor.md#Connect-a-local-stdio-server). Both routes are available in extension **1.0.1**; extension 1.0.0 did not include the stdio connector. Discover the tool's schema and select its actual prompt and required arguments. MCP connects PerfChecker to that tool; a server is not necessarily an agent and must provide an advice service to answer questions.

Both routes require `HTTP` in the Julia controller. A local stdio executable runs on the extension host, which may be a Remote SSH host or container. Choose **Connect for this editor session** after checking its advice and optional implementation tools; no advice is requested by connection alone. Choose saved evidence if useful, then ask a question. Chat also works without evidence for configuration and usage questions; the tool is told no measurements were attached. **Disconnect local MCP server** resumes saved provider configuration, and restarting the editor requires an explicit reconnect. The [local Codex connector](../mcp-advisor.md#Connect-an-authenticated-Codex-CLI) remains under **Optional Codex CLI connector**.

Review the answer. You can apply the advice yourself, or explicitly select **Prepare implementation from reviewed advice**. The latter requires a separately configured implementation tool that honors the isolated checkout, and a Git repository with an existing commit. The review and recovery controls work with that configured tool; they are not exclusive to the optional Codex connector.

Before sending implementation, save your files. The extension warns that generated changes may be incorrect, saves a Git checkpoint of the current on-disk state and prepares an isolated temporary checkout. The configured implementation tool must access and honor that checkout; MCP supplies neither filesystem access nor an operating-system sandbox. The original working tree receives no proposed changes until you inspect the diff and select **Apply reviewed implementation changes**. **Restore implementation checkpoint** reverses that applied patch when the repository has not drifted. Cancellation or server shutdown does not undo edits already made to the temporary checkout.

Read the [MCP guide](../mcp-advisor.md) for configuration, what is transmitted, checkpoint recovery, cancellation and the filesystem-access requirements of the agent tool.

## Julia, notebooks and terminals

**PerfChecker: Open Julia terminal** creates a terminal named for the package and
starts the selected Julia executable with the controller project.

Extension **1.0.1** uses **New Pluto notebook** and **Open Pluto notebook**
for editable `.jl` notebooks in an interactive editor tab. Follow the
[Pluto workflow](vscode-workflows.md#Pluto-notebooks-in-VS-Code) for generation,
Launch/Cancel, reactive edits, saved source/reports and Stop/Restart controls.
Extension **1.0.0** used **New investigation notebook**, an untitled
notebook with discovery, measurement and diagnosis cells; select an installed
Julia kernel for that earlier workflow.

**PerfChecker: Debug current Julia file** delegates a saved Julia source file to the installed Julia VS Code debugger. Debugging needs `julialang.language-julia`. The debugger and notebook kernel are separate from isolated measurement workers; stepping through a program is not a performance measurement.

See [Plots, notebooks and Julia tools](vscode-workflows.md) for supported displays, notebook prerequisites and a practical debugging sequence.

## Companion and 3D integrations

A companion extension can open Studio for an explicit workspace URI using `perfchecker.openStudioForWorkspace`. Existing suite-editor and live-landscape integration commands remain available. They select the requested package folder rather than silently using the first folder in a multi-root workspace.

This provides the workspace boundary used by the Etendu/Beautiful Landscape integration. PerfChecker does not implement a new 3D renderer; the companion owns its scene and live graphics workflow. Verify its supported extension versions and selected folder before starting a run. [Plots, notebooks and Julia tools](vscode-workflows.md) describes the command contract.

## Resolve common problems

| Symptom | Check |
| --- | --- |
| Studio command missing | Installed extension is the current stable version; reload the extension host |
| Worker cannot import PerfChecker | Runner Project contains the matching package and a `Project.toml` |
| Analyzer unavailable | Scenario Project contains that analyzer and its target dependencies |
| No plots | A completed saved report contains the relevant observations/profile artifacts |
| Chat refuses the configuration | Protocol is `mcp_http`, response is `text`, and an advice tool is selected |
| Implementation cannot proceed | A separate tool is configured; Git/HEAD exists; all buffers are saved |
| Wrong folder in multi-root workspace | Reopen Studio and select the intended package |

Use **PerfChecker: Show worker output** for execution diagnostics. See [configuration troubleshooting](vscode-configuration.md#Troubleshooting) and the [MCP failure table](../mcp-advisor.md#Troubleshooting) for the next checks.

### Qualification and reporting a problem

The [1.0.1 release report](https://github.com/Mirage-Interactive-Fr/PerfCheckerVSCode/releases/tag/v1.0.1)
links the native checks for the published VSIX, with Julia **1.13.1** and
registered Core **1.0.1**. Its checksum and original packaging provenance are
attached to the release. Earlier screenshots keep their original source labels;
they are not evidence that every later build passed.

| Platform | Verified scope for extension 1.0.1 |
| --- | --- |
| Linux and Windows, VS Code 1.96 and stable 1.141.0 | Full native workflow suite, editor controls, HTTP MCP, stdio MCP, reload and saved evidence; interactive Pluto figures passed on all four combinations |
| Intel macOS, stable VS Code 1.141.0 | Normal installation, fresh workspace setup, HTTP MCP, editor controls, reload and narrative workflows passed; Pluto figures and their keyboard interactions rendered successfully |
| Intel macOS limits | The Pluto figure check failed while inspecting a disappearing process after **Close notebook view**, so physical cleanup after Close remains unqualified. Its final **Stop session** verified the owned processes and listener had gone. Native stdio remains unqualified because a separate controller preparation with automatic precompilation disabled timed out importing HTTP before stdio started |

Use the documented installation with normal Julia package precompilation on
macOS; the first installation can spend several minutes compiling dependencies.
The stdio result does not establish a stdio defect or imply that macOS is
unsupported. Apple Silicon and testing on a physical Mac have not been
established here. The native color-picker gesture is qualified on Linux only;
Windows/macOS picker gestures and the Landscape companion's native rendering
controls remain unqualified. Software rendering does not qualify a physical GPU.

Controlled MCP providers exercise discovery, advice, reviewed changes, Apply,
Restore and cancellation in the editor. They do not establish compatibility
with every authenticated model or remote service. The complete authenticated
Bibliography demonstration is separate and remains unqualified. Core CI has
its own platform matrix; it does not substitute for native extension checks.

Report editor/UI issues in
[PerfCheckerVSCode](https://github.com/Mirage-Interactive-Fr/PerfCheckerVSCode/issues/new)
and Julia execution issues in
[PerfChecker.jl](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/issues/new).
Include OS and CPU architecture, VS Code/extension/Julia/core versions, the
chosen action, a minimal reproducible workload, selected project settings and
redacted output. Keep credentials and Pluto session URLs out of the report.

## Recorded example

```@raw html
<DocMedia src="/examples/bibliography/vscode/native-items.png" alt="Bibliography export workload passed in VS Code while its format API item remains unrun" caption="Earlier native Testing controller example: one selected Bibliography item executed. This image does not show the Studio or implementation workflow." />
```
