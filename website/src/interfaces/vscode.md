# PerfChecker Studio in VS Code

PerfChecker combines Julia performance tests, saved results, plots and optional agent conversations inside VS Code. **Studio opens as a full editor tab**: keep it beside your source, move it into another editor group, or return to the compact PerfChecker views in the activity bar.

Follow this page for a first measurement and a version comparison. Continue with
[configuration](vscode-configuration.md), [plots and Julia tools](vscode-workflows.md)
or [MCP advice and implementation](../mcp-advisor.md) when you reach those steps.

The screenshots below show the **actual V1 extension webviews running in an
isolated Chromium test harness**, with demonstration projects and results. They
are not drawings or screenshots of a complete VS Code window. In VS Code, the
same webviews open in editor tabs; the surrounding editor and theme may differ.
Select any screenshot to open its full-resolution image, including the form
fields and implementation diff.

The **1.0.1 candidate** adds integrated Pluto notebooks and guided workspace
setup. Their qualification and publication are still in progress. The six
screenshots on these pages describe the public 1.0.0 webviews with demonstration data;
new native screenshots will accompany the qualified Pluto release.

## Install and prepare

1. Install VS Code **1.96 or newer** and Julia **1.10 or newer**.
2. Install [PerfChecker from the Visual Studio Marketplace](https://marketplace.visualstudio.com/items?itemName=mirage-interactive-fr.perfchecker-vscode), or search the Extensions view for `@id:mirage-interactive-fr.perfchecker-vscode`. You can also download the [qualified V1 VSIX](https://github.com/Mirage-Interactive-Fr/PerfCheckerVSCode/releases/download/v1.0.0/perfchecker-vscode-1.0.0.vsix) and use **Extensions → … → Install from VSIX…**. Reload VS Code if prompted. See [VS Code's installation instructions](https://code.visualstudio.com/docs/configure/extensions/extension-marketplace) for either route.
3. Open the package folder. Trust the workspace when you are prepared to execute its Julia code.
4. Prepare a Julia controller environment containing the matching PerfChecker build and the collectors you intend to use. Existing TestItems also require TestItemRunner and the package's test dependencies.
5. Set **PerfChecker: Runner Project** (`perfchecker.runnerProject`) to the controller environment. For shared scenarios, set **Scenario Project** (`perfchecker.scenarioProject`) to the environment containing the measured code and its dependencies.
6. Run **PerfChecker: Open Studio** from the command palette. In a workspace with several folders, select the package to inspect.

The [extension release notes](https://github.com/Mirage-Interactive-Fr/PerfCheckerVSCode/releases/tag/v1.0.0)
identify the qualified artifact. PerfChecker's Julia registry release and its VS Code
extension are distributed separately; installing the Julia package does not
install the extension.

Opening Studio reads configuration and presents actions. It does not install packages, start Julia, download a model or launch an agent. A controller should contain `HTTP` if you enable MCP. JET and other analyzers belong in the environment selected for their workers.

```@raw html
<DocMedia src="/assets/screenshots/vscode-studio.png" alt="PerfChecker V1 Studio webview rendered in Chromium, with the selected Example package and actions for suites, results, Julia tests and agent chat" caption="Start here: check the selected package and expand Workspace environment to inspect its controller, then choose an action. This is the running extension webview with a demonstration workspace." />
```

If this is your first setup, follow [Prepare a controller](vscode-configuration.md#Prepare-a-controller) before running an item. Use the dedicated controller so adding a profiler or MCP client does not change your package's normal dependency environment.

The candidate's [guided setup](vscode-configuration.md#Guided-setup-from-Studio)
offers an explicit controller installation or an existing project. It requires
registered Core 1.0.1 before the new notebook/discovery workflow can run.

See [Installation](../guide/installation.md) for the core and interface packages, and [VS Code configuration](vscode-configuration.md) for complete settings and environment examples.

## Get a first result

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-10" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-10.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-10-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-10-en.vtt" preload="metadata" alt="Actual native VS Code first PerfChecker TestItem, source oracle and run controls" caption="Start with the Vector reduction TestItem and its explicit expected sum, then run its native measurement. Recorded build: VSIX 75f84f, Core 6f, VS Code 1.141 on Linux." />
```



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

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-02" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-02.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-02-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-02-en.vtt" preload="metadata" alt="Native VS Code TestItem evidence with measured seconds, bytes and item correctness" caption="Read the actual native item's JSON and its measurement boundary. This excerpt uses the same voice and passage as the full tutorial; its recorded build is VSIX 75f84f, Core 6f, VS Code 1.141 on Linux." />
```

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
| Pluto notebook (1.0.1 candidate) | Edit reactive Julia cells and explicitly launch suite checks or investigations |
| PerfChecker terminal | Use a dedicated Julia session in the controller project |

These are VS Code editor tabs and native surfaces. Arrange them with VS Code's editor groups; the activity bar is an entry point, not the available working area.

### Choose an action and its prerequisites

| Action | Prepare first | Guide |
| --- | --- | --- |
| Existing TestItems | Runner, TestItems/TestItemRunner 1.3.2 or newer, package test dependencies | [First result](#Get-a-first-result) |
| Suite selection and comparison | Suite factory, collectors, declared target environments | [Design and compare](#Design-a-suite-and-compare-targets) |
| Visual output | Completed suite reports containing the requested observations | [Saved plots](vscode-workflows.md#Plot-saved-results) |
| Integrated Pluto candidate | Corrected extension/core 1.0.1 and a separate Pluto project | [Notebook workflow](vscode-workflows.md#Pluto-notebooks-in-VS-Code) |
| Julia terminal or debugger | Julia/controller; Julia extension and saved source for debugging | [Julia tools](vscode-workflows.md#Dedicated-Julia-terminal) |
| Advice conversation | Authenticated supported CLI or configured MCP advice tool | [MCP connection](../mcp-advisor.md#Choose-a-connection) |
| Reviewed implementation | Saved files, Git HEAD and a separate implementation tool | [Review and apply](../mcp-advisor.md#Switch-from-advice-to-implementation) |
| Cancel, stop or restore | Wait for cleanup and review repository drift | [Cancellation](#Cancel-a-run-and-wait-for-cleanup) |
| Beautiful Landscape companion | Actual game assets, renderer environment, explicit quality profile and corrected Core 1.0.1 | [Live measurement](vscode-workflows.md#Measure-a-Beautiful-Landscape-scene) |

## Design a suite and compare targets

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-11" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-11.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-11-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-11-en.vtt" preload="metadata" alt="Actual PerfChecker declared suite source and native workload selection in VS Code" caption="Keep the factory, measured operation and required correctness oracle together. Recorded builds: VSIX 75f84f, Core 6f and 975d, VS Code 1.141 on Linux." />
```

The suite editor supports global and per-feature check selection, version ranges, filtering, sorting and ordering. Name targets for a branch, tag, commit, working tree or release, then choose exact or grouped baselines. Grouped references can use median, mean, minimum or maximum aggregation.

Save the selection with **Save configuration** in the suite editor. The default
is `perf/perfchecker-ui.json`; compatible web and documentation interfaces can
read the same configuration. In extension 1.0.0, the separate command-palette
action **PerfChecker: Save shared UI configuration** has a confirmed defect; use
the editor button while its correction is being prepared. Running the selection
shows progress and leaves saved evidence for later review.

The editor separates filtering from selection. Search, package/target filters and release bounds change what is visible without deselecting hidden runs. **Select visible** and **Clear visible** act on the current filter; **Clear selection** affects the entire selection. The counter reports selected runs, visible runs and selected runs outside the filter. **Run N selected** includes those hidden selections, so review the exact identifier preview before execution. **Show more** pages workload groups without restricting bulk selection.

Collector toggles select or deselect matching runs. Unavailable conditions show their reason. Add targets from discovered branches, tags and recent commits or enter a supported ref/URL, then inspect the comparison matrix. Missing or overlapping references are reported before a run; refreshing the plan preserves existing selections when their identifiers still exist.

```@raw html
<DocMedia src="/assets/screenshots/vscode-suite-designer.png" alt="Running PerfChecker V1 suite-designer webview with workload filters, selected check types, target controls and a run-selection summary" caption="Review the exact runs before executing: filtering controls visibility, while selection controls what will run. The screenshot uses demonstration workloads in the extension's real suite designer." />
```

#```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-03" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-03.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-03-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-03-en.vtt" preload="metadata" alt="Actual native PerfChecker suite filtering, visible selection and preview controls" caption="Search for the intended workload, select the visible checks and inspect Preview before running. The close views preserve the actual controls. Recorded build: VSIX 75f84f, Core 975d, VS Code 1.141 on Linux." />
```

## Choose the evidence for your question

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-12" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-12.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-12-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-12-en.vtt" preload="metadata" alt="Actual native PerfChecker check controls for BenchmarkTools, Chairmarks, CPU, wall-time and allocation evidence" caption="Choose the check that answers the question and inspect its prerequisites. The footage shows the real native tutorial workload. Recorded build: VSIX 75f84f, Core 975d, VS Code 1.141 on Linux." />
```

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

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-13" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-13.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-13-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-13-en.vtt" preload="metadata" alt="Actual native PerfChecker comparison package, feature, reference aggregation and target controls" caption="Resolve the intended Git state and review the baseline, candidate and aggregation policy before a comparison. Recorded build: VSIX 75f84f, Core 975d, VS Code 1.141 on Linux." />
```

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

Changing a branch name or editor selection does not manufacture a compatible
baseline. The saved evidence records the actual measured configuration.

The suite tree follows:

```text
package → feature → check type → target
```

Read [Suites and comparisons](../suites-and-comparisons.md) before interpreting a result across environments or machines. Never infer an improvement from a profile weight alone.

## Investigate and verify

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-18" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-18.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-18-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-18-en.vtt" preload="metadata" alt="Actual native PerfChecker investigation benchmark, analyzers and Aqua quality diagnostic" caption="Inspect the benchmark and analyzer outcomes individually. The Aqua diagnostic frame is held for reading: the analyzer completed with correctness not checked and quality failed; this passage does not imply a new execution. Recorded build: VSIX 75f84f, Core 975d, VS Code 1.141 on Linux." />
```

Use **PerfChecker: Open investigations** for shared scenarios. **Discover scenarios from tests** inspects declarations and proposes candidates without executing the target program. Proposed candidates need an explicit factory and correctness oracle before they become measurable cases.

Measure declared cases, diagnose with available analyzers, and choose **Advise from saved evidence**. Missing analyzers appear as unavailable; they are not installed automatically. After a change, rerun the same correctness checks and compare compatible before/after measurements.

**Run bounded investigation** can select declared experiments within count and time budgets. Optional model selection requires structured MCP replies and `advisorInvestigates = true`; it remains separate from implementation chat.

## Cancel a run and wait for cleanup

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-14" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-14.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-14-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-14-en.vtt" preload="metadata" alt="Actual native PerfChecker investigation cancellation, controller cleanup and recovery checklist" caption="Cancel an active investigation and wait for the final controller-cleanup status. The recovery checklist explains subsequent checks; it does not show those checks executing. Recorded build: VSIX 75f84f, Core 975d, VS Code 1.141 on Linux." />
```

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

Cancelling advisor chat or an MCP request stops the local conversation. A remote
server or agent may continue working after the local request closes. Review the
isolated implementation checkout and checkpoint before applying changes; local
cancellation does not prove the remote tool stopped.

## Advice and explicit implementation

Studio → **Talk to your agent** opens **PerfChecker: Chat with performance advisor**. For an authenticated native Codex CLI, choose **Connect Codex CLI**: the extension checks the installation and starts a temporary local MCP connector with separate advice and implementation tools. Follow the [qualified Codex recipe](../mcp-advisor.md#Connect-an-authenticated-Codex-CLI), or configure an external MCP advice tool. Choose saved evidence if useful, then ask a question. Chat also works without evidence for configuration and usage questions; the agent is told no measurements were attached.

Review the answer. You can apply the advice yourself, or explicitly select **Prepare implementation from reviewed advice**. The latter requires the connected Codex implementation tool or a separately configured external tool, and a Git repository with an existing commit.

Before sending implementation, the extension warns that generated changes may be incorrect. It saves a Git checkpoint of the current on-disk state and prepares an isolated temporary checkout. The agent works there; the original working tree receives no proposed changes until you inspect the diff and select **Apply reviewed implementation changes**. **Restore implementation checkpoint** reverses that applied patch when the repository has not drifted.

Read the [MCP guide](../mcp-advisor.md) for configuration, what is transmitted, checkpoint recovery, cancellation and the filesystem-access requirements of the agent tool.

## Julia, notebooks and terminals

**PerfChecker: Open Julia terminal** creates a terminal named for the package and
starts the selected Julia executable with the controller project.

The **1.0.1 candidate** uses **New Pluto notebook** and **Open Pluto notebook**
for editable `.jl` notebooks in an interactive editor tab. Follow the
[Pluto workflow](vscode-workflows.md#Pluto-notebooks-in-VS-Code) for generation,
Launch/Cancel, reactive edits, saved source/reports and Stop/Restart controls.
Public extension **1.0.0** uses **New investigation notebook**, an untitled
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

Core CI includes Linux 32-bit, Linux/Windows 64-bit, Julia LTS and macOS
Intel x64 (`macos-26-intel`). That core matrix is separate from native extension
qualification. The 1.0.1 native editor campaign is still running; physical Mac
testing and Apple Silicon arm64 coverage have not been established here.
The completed report will record editor, Julia/core versions and CPU architecture
for each tested platform.

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

```@raw html
<a id="Run-one-existing-item"></a>
<a id="Read-the-result-before-comparing-it"></a>
<a id="Visual-suite-editor"></a>
<a id="Results"></a>
<a id="Optional-investigations"></a>
```
