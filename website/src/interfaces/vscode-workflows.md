# Plots, notebooks and Julia tools

Use saved evidence in full VS Code tabs, and run exploratory Julia code in an explicit notebook, terminal or debugger session. Studio links these surfaces without starting them on opening.

## Plot saved results

Select a completed suite run in PerfChecker, then choose **PerfChecker: Open visual output**. The extension reads the saved suite report and opens available plots in an editor panel. Keep it beside the workload or use editor groups to compare reports. Native TestItems retain their separate JSON evidence in the **PerfChecker test items** output channel.

In the visual output, select **Version series** to compare recorded targets. Use
the package, feature and check filters to narrow the evidence. Hover a point or
focus its accessible button to inspect the value and unit. **JSON** and
**Series JSON** open the underlying saved data when you need its provenance.

```@raw html
<DocMedia src="/assets/screenshots/vscode-results.png" alt="PerfChecker V1 output webview rendered in Chromium, displaying version filters, a normalized overlay and timing points with nanosecond units" caption="Read units and raw values before comparing: the overlay sets each metric's minimum to 1, while the version series retains the recorded unit. These are demonstration results in the real extension UI, not measurements of a published package." />
```

The normalized overlay makes different metrics readable together; a ratio of
two for bytes and a ratio of two for time do not describe the same quantity.
Select the corresponding raw series and compatible collector before drawing a
conclusion. The screenshot's version labels belong to the demonstration package,
not to PerfChecker's release version.

| Visual | Evidence needed | Interpretation |
| --- | --- | --- |
| Distribution | Timing/allocation samples | Spread, outliers and sample count for the recorded configuration |
| Allocation view | Allocation samples or sites | Allocation activity, with units and sampling limits |
| Flame graph | Recorded profile stacks | Sampled call-path weights; not independent timing observations |
| Version comparison | Compatible target observations | Differences against the selected baseline and aggregation policy |
| Overlay | Comparable saved series | Contrast recorded configurations without inventing missing samples |

A report without profile stacks cannot produce a measured flame graph. A missing configuration remains unmeasured. Open worker output or source from the same run if a result is incomplete.

### Read a distribution

Open the **Distributions** view for a completed check. Keep its unit, sample
count and collector beside the chart. A narrow distribution still describes
only that recorded configuration; it does not establish a general property
of the function.

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-15" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-15.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-15-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-15-en.vtt" walkthrough="/interfaces/vscode-videos.html#Full-tutorial" chapter="06 · Read the saved plots" preload="none" alt="Actual PerfChecker saved distribution, allocation median of 48 bytes, raw series and source JSON in native VS Code" caption="Inspect actual worker measurements in their own units. The 48 B median is read from the recorded Example hello report. Recorded build: VSIX 75f84f, Core 975d, VS Code 1.141 on Linux." />
```

### Read normalized overlays

Each metric uses its own reference minimum. A ratio of one describes that
metric's minimum; inspect the raw value and unit in the tooltip before drawing
a conclusion. The example below preserves the actual saved version series.

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-04" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-04.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-04-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-04-en.vtt" walkthrough="/interfaces/vscode-videos.html#Full-tutorial" chapter="06 · Read the saved plots" preload="none" alt="Actual native PerfChecker minimum-relative chart, raw units and recorded version tooltip" caption="Read each metric against its own minimum, then inspect its raw value. The recorded tooltip is 136 ns with ratio 1.0149; units remain separate. Recorded build: VSIX 75f84f, Core 975d, VS Code 1.141 on Linux." />
```

### Follow a recorded profile

Select **Flame graphs** for a check containing real profile stacks. Follow the
frame names and source locations, then inspect the collector's sampling
boundary. Use a profile to choose a workload and a correctness protocol for
the next experiment.

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-16" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-16.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-16-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-16-en.vtt" walkthrough="/interfaces/vscode-videos.html#Full-tutorial" chapter="07 · Inspect a real flame graph" preload="none" alt="Actual native PerfChecker CPU flame graph with a closer view of sum_squares, materialize and copy" caption="Follow real recorded profile stacks. The closer view preserves the original frame labels; profile weights describe the stated collector. Recorded build: VSIX 75f84f, Core 975d, VS Code 1.141 on Linux." />
```

These are passages from the full tutorial, with English captions and the
original narration. The [video walkthrough index](vscode-videos.md) groups
them by action.

For custom Julia figures, load [PerfCheckerMakie](visualization.md) with your chosen Makie backend. The core notebook's `display(bundle)` presents a bundle; it does not automatically create every optional graphical backend. Save reports or create figures explicitly when you need reusable plots.

## Notebook versions

The integrated Pluto workflow below is a **1.0.1 candidate**. Its native editor
qualification and General installation check are still in progress. Public
extension **1.0.0** uses the earlier notebook workflow described at the end of
this section. Install the corrected releases before using the candidate steps.

## Pluto notebooks in VS Code

The integrated Pluto workflow requires **PerfChecker for VS Code 1.0.1 or newer**
and the corrected **PerfChecker core 1.0.1 or newer**. Both releases must be
available before following this workflow.
Use **PerfChecker: New Pluto notebook** to create a native `.jl` notebook, or
**PerfChecker: Open Pluto notebook** to reopen one in an interactive editor tab.
The extension starts a Julia-backed Pluto session and displays its actual
notebook interface inside VS Code.

### Create a dashboard

1. Open the intended trusted package folder and check its suite or scenario
   configuration in Studio.
2. Choose **New Pluto notebook**, then save a new `.jl` file inside that folder.
   The suggested location is `perf/notebooks/performance.jl`.
3. Select **Feature suite** for suite checks and saved reports, or
   **Investigation** for discovery, scenarios, diagnosis and advice.
4. If the separate Pluto environment is missing or incompatible, review the
   installation prompt. **Install Pluto environment** downloads the listed
   packages into `perfchecker.plutoProject`, whose default is `perf/pluto`.
   Cancelling leaves the installation unrequested; opening Studio never installs
   those packages.
5. Wait for the notebook tab to become ready. In **Feature suite**, select the
   workload, collector and target, inspect the printed plan, then choose
   **Launch selected checks**.
6. Use **Refresh status** to inspect the job and **Cancel active job** to
   interrupt active work. After completion, refresh and choose **Save completed
   reports**, then open their visual output from PerfChecker.

An **Investigation** notebook instead offers **Launch selected action**, **Cancel
active investigation** and **Refresh status and evidence**. Review its chosen
action and declared scenarios before launch. If no suite file exists, a feature
notebook opens as a saved-report reader; create or configure the suite before
expecting executable checks.

```@raw html
<DocMedia src="/assets/screenshots/vscode/v101/pluto-macos-intel.png" alt="Native VS Code 1.141.0 on a macOS Intel CI host displaying the generated PerfChecker Pluto suite notebook, its package, workload, collector and target selectors, and Open source, Stop session and Restart session controls" caption="Review the package, workload, collector and target selectors inside the VS Code editor tab. This capture records only an idle notebook opening in the 1.0.1 candidate, with a demonstration package." />
```

This native capture uses VSIX candidate `75f84f631ba3`, Core candidate
`6f6155510aa2` and Julia **1.13.1**. Its configured opening phase passed;
the complete notebook lifecycle and final release qualification remain in
progress. The image opens at full resolution when selected.

The integration uses the official notebook generators supplied by PerfChecker
and its PerfCheckerPluto companion. The generated notebook is editable Julia source. Opening it or changing a selector does not request
a new measurement. Pluto still executes reactive Julia cells: inspect an
unfamiliar notebook before trusting and opening it.

For an investigation, `scenarioCatalog` selects the declared scenarios and
`scenarioProject` selects their target environment. Prepare the measured
package, scenario dependencies and requested analyzers there. The notebook's own
environment contains the interface packages; it is separate from the target
workers. A missing analyzer is unavailable rather than a passing diagnosis.

### Keep the Pluto environment separate

The candidate integration targets Pluto **1.0.4**, the corrected PerfChecker
core, PlutoUI, BenchmarkTools, Chairmarks and its official PerfCheckerPluto companion.
Use the companion tag recorded by the qualified extension release. Set the folder configuration explicitly
when you use several environments:

```json
{
  "perfchecker.runnerProject": "perf/controller",
  "perfchecker.scenarioProject": ".",
  "perfchecker.plutoProject": "perf/pluto"
}
```

Pluto 1.0.4's published dependency range uses HTTP 1.x, while the qualified MCP
controller uses HTTP 2.x. A separate Pluto environment keeps these resolved
dependencies independent. This is a constraint of the qualified Pluto release:
later Pluto releases may support both ranges. Do not install this stable Pluto
setup into the measurement/MCP controller; the guided installer refuses that
overlap. See [optional interface installation](../guide/installation.md) if you
prefer to prepare the environment manually.

### Edit, save and reopen

1. Expand the source of a notebook cell and edit its Julia code. Submit the cell
   with **Ctrl+Enter** (**Cmd+Enter** on macOS) to update its reactive output.
2. Wait for Pluto to save the cell to the `.jl` file. These saved cell edits are
   separate from **Save completed reports**, which writes completed suite
   evidence.
3. Reopen the file with **PerfChecker: Open Pluto notebook**. An active notebook
   reuses its existing tab and server; a stopped session starts from the saved
   source. Changing selectors or reopening retains saved evidence without
   launching the checks again.

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-05" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-05.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-05-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-05-en.vtt" walkthrough="/interfaces/vscode-videos.html#Full-tutorial" chapter="08 · Pluto notebooks inside VS Code" preload="none" alt="Actual native PerfChecker Pluto cell editing, reactive output, source autosave, Save completed reports and notebook reopening" caption="Submit a cell edit, inspect its reactive output and retain the saved notebook source separately from completed reports. Then reopen the actual notebook. The source interaction is slowed and frames are held for reading. Recorded candidate: VSIX 7add564, Core 4eec7f3, VS Code 1.141.0 on Linux." />
```

### Manage the session and saved source

| Control | Effect |
| --- | --- |
| **Open source** | Open the saved `.jl` notebook in the Julia source editor |
| **Stop session** | Shut down this notebook's Julia/Pluto process; retain the saved notebook and reports |
| **Restart session** | Stop the current process and start the saved notebook again |
| **PerfChecker: Stop Pluto notebook sessions** | Stop the sessions belonging to the selected workspace folder |
| Pluto homepage session button | Confirm shutdown of that notebook and its owned jobs; the Pluto server remains available |

Pluto saves cell edits to the notebook file. Reopening the same active notebook
reveals its existing tab; closing that tab stops its process. Removing its
workspace folder also shuts down its session. Stop a session before editing its
source externally, then restart to load the saved changes. Unsaved Julia editor
buffers are separate from Pluto's own saved cells.

After shutting down a notebook from Pluto's homepage, use **Restart session**
in the PerfChecker header to reopen its saved source. Stop and restart request
cancellation of owned PerfChecker jobs and wait for their cleanup before closing
the notebook worker. Wait for the final status and inspect diagnostics when a
shutdown reports an error.

The Pluto homepage's **Shutdown** action opens a confirmation dialog inside
the notebook, where VS Code can display it. **Cancel** or **Escape** keeps the
notebook worker running. **Confirm** accepts that notebook's original shutdown
question; the other notebook sessions and the shared server remain available.

Pluto's Julia/HTML exports and actions that open another browsing context use
your default browser. Normal **New**, **Open** and **Recent** navigation stays
inside the VS Code editor. See the [qualification notes](vscode.md#Qualification-and-reporting-a-problem)
for the established platform scope of these browser interactions.

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-17" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-17.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-17-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-17-en.vtt" walkthrough="/interfaces/vscode-videos.html#Full-tutorial" chapter="08 · Pluto notebooks inside VS Code" preload="none" alt="Actual native PerfChecker Pluto evaluated cell, Shutdown confirmation Cancel and Confirm, and final session state" caption="Inspect the evaluated result 9, cancel the notebook's shutdown question, then confirm it and inspect the final session state. Actions are slowed and frames held for reading. Recorded candidate: VSIX b899ea751d7b, Core 59578c840d94, VS Code 1.141.0 on Linux. Owned workers, private files and allocation journals were checked before test teardown; the shared listener remained available. This passage does not establish every platform or arbitrary callback completion after a forced stop." />
```

Core cleans its owned worker environments, allocation journals and `.mem`
files separately. A workload's `cleanup(state)` callback runs during normal
Julia unwinding; terminating its isolated process cannot guarantee that an
arbitrary user callback runs. Keep files created by the workload recoverable,
and inspect a forced-stop diagnostic before restarting.

Use **View → Output → PerfChecker Pluto** for setup, startup and session errors.
The notebook server binds to loopback and the extension handles its session URL;
do not share that URL or include it in a bug report. Remote workspace forwarding
depends on VS Code's extension-host port support. Report an unavailable forwarded
session with the editor, extension and Julia versions and redacted diagnostics.

```@raw html
<a id="Investigation-notebooks"></a>
```


### Public extension 1.0.0 notebooks

The earlier **New investigation notebook** and **Open Julia notebook** actions
use `.ipynb` and require a Julia kernel provider. Existing notebooks remain
separate from Pluto's `.jl` format; PerfChecker does not convert them. Retain
their saved source and consult the [archived 1.0.0 notebook instructions](https://perfchecker.mirageinteractive.fr/v1.0.0/interfaces/vscode-workflows.html#Investigation-notebooks)
when maintaining that workflow. For a new investigation with the corrected
1.0.1 releases, follow the Pluto steps above.

## Dedicated Julia terminal

**PerfChecker: Open Julia terminal** starts a terminal named **PerfChecker · package-name** with:

```text
julia --startup-file=no --project=<resolved-controller-project> -i
```

Its working directory is the selected package. The executable comes from `perfchecker.juliaExecutable`. A compatible existing PerfChecker terminal is reused; changing the project/executable creates a separately configured session.

Use it to inspect the public API or deliberately rerun a check. Interactive terminal state is independent from fresh measurement workers. Use saved bundle provenance for reproducibility rather than assuming the terminal matches a previous run.

## Julia debugging

Install the Julia VS Code extension (`julialang.language-julia`) and open a saved Julia source file belonging to the selected package. Choose **PerfChecker: Debug current Julia file**. PerfChecker delegates to the Julia debug adapter, requests the selected scenario project in its launch configuration and stops on entry. Inspect the actual runtime project before relying on that environment.

!!! note "Qualified runtime and project selection"
    Native VS Code **1.141.0** on Linux and Windows, the Julia extension **1.249.2** and Julia **1.12.7** passed the REPL and debugger checks with the 1.0.1 extension build. Both debug sessions executed the target source, checked `VERSION`, `Base.active_project()` and the correctness oracle, and used the intended controller in two distinct workspace folders. PerfChecker's measurement runner used Julia **1.13.1** separately. This proof covers the selected target source; full PerfChecker startup under the debugger's interpreter was not exercised. Check the same runtime and project fields in your stopped session.

1. Use deterministic advice to identify a workload or correctness failure.
2. Open its source and set a breakpoint.
3. Debug the file and inspect state, inputs and the oracle.
4. Finish debugging; rerun isolated correctness and performance checks.
5. Compare saved compatible results before adopting a change.

Debugger overhead and stepping change execution. Use debugging for correctness investigation, then collect performance evidence separately. Studio's **Julia extension REPL** action delegates to the Julia extension's own REPL, which keeps the environment selected in Julia's status bar; check it before running code. The dedicated PerfChecker terminal uses the selected controller project and remains a separate action.

### Julia extension compatibility

Native editor qualification found a language-server startup failure with the
official Julia extension **1.174.2** and Julia **1.13.1**: SymbolServer reports
`KeyError: _apply`. This is a concrete failure of that language-server
combination. PerfChecker's controller and measurement workers have separate
executable and project checks.

The native Linux and Windows checks passed with VS Code **1.141.0**, Julia extension
**1.249.2** and Julia **1.12.7**, including controller selection in a second
workspace folder. The recorded build was VSIX `2e722b2d575a`, using Core
1.0.1 source tree `4fbc3c25543aa4f9b1154c227e5432f0cd62df91` before
General registration. This result does not establish the same combination on
other operating systems. The release report records each platform actually
exercised. Configure `perfchecker.juliaExecutable` for the
PerfChecker controller and `julia.executablePath` for the official Julia extension
separately when those workflows need different runtimes. Select the real Julia
binary in the corresponding folder settings, then inspect `VERSION` and
`Base.active_project()` in that surface's terminal before executing code.

If you encounter the observed error, retain the
version tuple and redacted Julia output, and consult the
[Julia extension issue tracker](https://github.com/julia-vscode/julia-vscode/issues).

## Tasks and runners

Studio's tasks action opens VS Code's existing task runner. Opening Studio does not create `tasks.json`. Use established package tasks or the [CLI](../reference/cli.md) for a repeatable invocation.

Suite target environments, scenario workers, native TestItems, notebooks and debug sessions serve different purposes. Select their environments explicitly. A system profiler also needs its platform/provider dependencies; see [native profiling](../native-profiling.md) and [native dependencies](../reference/native-external.md).

## Etendu and live 3D companions

PerfChecker's public companion commands accept an explicit folder URI:

| Command | Contract |
| --- | --- |
| `perfchecker.openStudioForWorkspace(uri)` | Open Studio for an existing workspace folder |
| `perfchecker.openDesignerForWorkspace(uri)` | Open the suite designer for that folder |
| `perfchecker.runLandscapeLiveForWorkspace(uri, quality)` | Run the existing live-landscape measurement workflow |

These command IDs are available to Etendu/Beautiful Landscape and other extensions. The URI must identify the intended folder in VS Code. The companion owns rendering, scene lifetime and its quality setting; PerfChecker owns the configured measurement invocation and saved evidence.

### Measure a Beautiful Landscape scene

1. Open and trust the actual Beautiful Landscape game folder. Prepare its Julia
   rendering environment and download its required scene assets according to the
   companion's installation instructions. Its `EtenduGame.toml` must declare
   `id = "etendu.beautifullandscape"` and `entrypoint = "scripts/play.jl"`.
2. Check the folder's PerfChecker controller environment separately from the
   renderer environment. The cancellation fix belongs to the **Core 1.0.1
   candidate**; use its corrected registered release once available. The public
   Core 1.0.0 provider can leave a rendering worker running after interruption.
3. In the companion, select this folder and a quality profile declared in
   `config/quality.toml`, such as `mobile-leger`. That file uses the
   `beautiful-landscape-quality/1` schema. The game must supply its actual
   `perf/live_provider.jl`; PerfChecker validates these files before execution.
4. Start the companion's live measurement action. It passes the explicit folder
   URI and quality slug to `perfchecker.runLandscapeLiveForWorkspace`. Both
   arguments are required; the palette entry alone cannot select them.
5. Read **View → Output → PerfChecker Live** while the progress notification is
   active. Use its cancellation control to interrupt the run, then wait for
   worker cleanup before starting another measurement or closing the scene.
6. After a successful run, PerfChecker opens the saved `manifest.json` under
   `perf/results/live/run-<run-id>/`. Retain the complete bundle, including its
   integrity document, observations and recorded environment.

The current provider records `landscape.cpu.{median,p95,p99}` and
`landscape.submit_interval.{median,p95,p99}` in milliseconds. Its submission
boundary is `SDL_SubmitGPUCommandBuffer`. Read the saved warmup, measured
submission count, scene digest, quality profile, effective resolution and device
identity before comparing runs. The manifest explicitly records GPU timing and
physical presentation as `unavailable`; these observations do not measure
displayed frame rate.

Software qualification has exercised the real compiled provider bridge with
the Landscape v0.1.0 scene, five SDK v0.1.1 modules, Mesa **llvmpipe** on a CPU,
40 submitted frames after warmup and six real observations in milliseconds.
Two changing rendered scene buffers were observed before cancellation. The
corrected candidate stopped all tracked owned processes before the test display
closed, preserved an unrelated `.mem` file and published no completed evidence
for the cancelled run.

This opt-in test passed against Core candidate `11011e1f8999`. The package source
and tests are byte-identical in candidate `975d9351250a` (tree
`7efea7f007cbdd78141fbebef63eeefcebc0f54e`); only the spelling configuration
changed. Registration and the extension's final release qualification remain
separate prerequisites for the public 1.0.1 workflow.
The native VS Code companion button, hardware GPU timing and physical display
presentation have not been qualified by this software test.

Before a live graphics comparison, keep the scene, quality, device and workload
configuration comparable. Retain the resulting evidence and its configuration;
a changed scene or quality profile requires a new, explicitly selected run.
