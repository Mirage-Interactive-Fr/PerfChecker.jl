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

With the updated **1.0.1 extension**, compatible versions share the same
horizontal scale. The metric, unit and measurement definition must agree;
incompatible series keep separate scales. Read the displayed range before
comparing the positions of points.

1. Hover, tap or focus a sample to inspect its value and rank in the full
   sorted sample set.
2. Choose **Zoom +** to explore around that sample, or around the range centre
   when no visible sample is selected. **Zoom −** widens the view.
3. Use **←** (**Pan left**) and **→** (**Pan right**) to move through the
   recorded range. Open **Range** for exact **Minimum** and **Maximum** values or the keyboard-accessible
   sliders. These controls update every compatible version together.
4. Read **visible / total** to see how many samples lie inside the chosen
   range. Points outside this view remain in the saved data; zoom does not
   reject outliers or recompute the global statistics.
5. Choose **Fit** to restore the exact full recorded range, including its
   extremes. Constant or single-point distributions disable controls that
   cannot change the view.

The displayed statistics always use the complete recorded distribution.
Large distributions plot at most 512 sampled points while keeping the extremes
and full-set sorted ranks. A notice states the plotted and total counts; all samples
remain available in JSON. These controls are available in extension 1.0.1.
The native example below shows an earlier recorded source build; see the
[current release qualification](vscode.md#Qualification-and-reporting-a-problem).

::: tabs

== Inspect the central range

```@raw html
<DocMedia src="/assets/screenshots/vscode/v101/oxygen-distributions-central-db8b51b.png" alt="Native VS Code comparing Oxygen 1.10.2 and 1.11.0 plain_http timing distributions on the same zoomed scale, with 26 of 30 and 28 of 30 samples visible" caption="The shared viewport is 8,393–22,000 ns. It shows 26/30 samples for 1.10.2 and 28/30 for 1.11.0; the summaries still use all 30 samples per release. Their recorded medians are 16.39 µs and 9.00 µs." />
```

== Keep the full distribution

```@raw html
<DocMedia src="/assets/screenshots/vscode/v101/oxygen-distributions-full-db8b51b.png" alt="The same native Oxygen comparison restored to its full common timing range, with all 30 samples and slow extremes visible for each release" caption="Fit restores the full common range, approximately 8.393–98.204 µs. Both cards show 30/30 observations, including the slow extremes omitted from the zoomed viewport. No samples were discarded or recollected." />
```

:::

This is a real `plain_http` campaign on Linux x86_64, Julia 1.13.1, two worker
threads, measured on 9 October 2026 (UTC), in bundle
`32d4d39f-6754-47d3-a79f-ef8005cb9f46`. The native capture uses extension source
[`db8b51b`](https://github.com/Mirage-Interactive-Fr/PerfCheckerVSCode/commit/db8b51bced8c04bcf3a667f70aa3bb4239f50fb4)
and Core source
[`52a0d0c`](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/commit/52a0d0cd12472606632645700781d02d650f6694).
The two releases have different dependency stacks: this observation alone
does not attribute the difference to HTTP or establish a CI regression verdict.


### Read normalized overlays

Each metric uses its own reference minimum. A ratio of one describes that
metric's minimum; inspect the raw value and unit in the tooltip before drawing
a conclusion. The example below preserves the actual saved version series.


### Follow a recorded profile

1. Open the completed suite's visual output. Use **Check** to select the CPU,
   wall-time or allocation collector, and **View** to select **Flame graphs**.
   Keep the package, workload and release label beside each card.
2. Click a visible frame, or enter its number in **Inspect frame**. The
   **Frame index** slider reaches the same saved frames, including frames too
   narrow to click at the current scale.
3. Read **Inclusive weight**, **Metric** and **Call path** below the graph.
   Inclusive weight includes child calls; adding parent and child weights
   would count the same activity more than once. A displayed source location
   can be relative to its package or runtime, rather than an absolute filename.
4. Use **Zoom +**, **Zoom −** and the pan arrows to explore a region. **Range**
   exposes explicit viewport bounds, and **Fit** restores the full view.
   These controls change the presentation, not the saved samples.
5. Open the corresponding source from the measured release. Use the profile
   to choose the next experiment, then run correctness checks and ordinary
   timing measurements before claiming an improvement.

The tabs show real **DataStructures 0.19.6**, **heap_2048** profiles recorded on
Linux with Julia **1.13.1**. The same campaign also collected DataStructures
0.18.13; each screenshot below shows the **0.19.6 card only**. These profiles
attribute activity within a capture. They do not establish a before/after
speedup or provide per-operation benchmark timings.

::: tabs

== CPU samples

```@raw html
<DocMedia src="/assets/screenshots/vscode/v101/datastructures-cpu-0196-ad57106.png" alt="Native VS Code CPU flame graph for DataStructures 0.19.6 heap_2048, with Inspect frame 3, zoom and pan controls, the heap-pop branch and its complete recorded call path" caption="Frame 3 attributes 312 retained CPU samples to the selected branch, including child calls. Its 76.66% share is a fraction of this capture's CPU sample weight, not a measured percentage slowdown." />
```

The selected path passes through `pop!`, `heappop!` and `percolate_down!`.
Inspect the matching release's heap implementation before choosing a change.

== Wall-time samples

```@raw html
<DocMedia src="/assets/screenshots/vscode/v101/datastructures-wall-0196-ad57106.png" alt="Native VS Code wall-time flame graph for DataStructures 0.19.6 heap_2048, with frame 3 selected, 56 available frames and the inclusive sample weight below the graph" caption="Frame 3 carries 82 wall-time samples, or 71.30% of this capture's weight. Wall-time sampling can include waiting; these values are neither seconds nor interchangeable with the CPU sample count." />
```

The similar call path does not make the two collectors equivalent. Read the
metric on the card and use its own captured total.

== Allocated bytes

```@raw html
<DocMedia src="/assets/screenshots/vscode/v101/datastructures-alloc-0196-ad57106.png" alt="Native VS Code allocation flame graph for DataStructures 0.19.6 heap_2048, with frame 6 selected along BinaryHeap, heapify, similar and Array and the inclusive byte-weight readout" caption="Frame 6 has a weighted allocation estimate of approximately 98,384 bytes. This sampled attribution includes child calls; it is not retained heap size, resident memory or a direct per-operation allocation total." />
```

Follow the allocation path to distinguish heap construction from heap removal.
An allocation count and a byte estimate answer different questions; choose
the metric explicitly before comparing them.

:::

These native images were captured on 9 October 2026 (UTC) with extension candidate
[`ad57106`](https://github.com/Mirage-Interactive-Fr/PerfCheckerVSCode/commit/ad57106765f741a36e4be00e6ea78ab6c5eff472)
and Core source
[`63f5cc4`](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/commit/63f5cc4bfc2c55de521487f68b0df143107762f3),
from bundle `8f2ffde5-55b9-43de-b35a-08503f9b6639`. They are separate from the
historical profile campaign in the [DataStructures example](../real-packages/datastructures.md).
The saved data was not recollected to take the screenshots. The
[video walkthrough index](vscode-videos.md) links the written chapters while
the new videos await publication.

For custom Julia figures, load [PerfCheckerMakie](visualization.md) with your chosen Makie backend. The core notebook's `display(bundle)` presents a bundle; it does not automatically create every optional graphical backend. Save reports or create figures explicitly when you need reusable plots.

## Ask about a saved suite

Attaching suite measurements requires **PerfChecker for VS Code 1.0.1 or
later** and a controller with **PerfChecker core 1.0.1 or later providing
canonical measurement summaries**. Core **1.0.0** does not provide those
summaries: Send displays
an explicit limitation and sends no measurements to the provider. Updating the
extension alone does not update the selected Julia controller.

1. Open the intended workspace and its completed suite output. Keep the saved
   suite report, version-series report and original run bundle together under
   that folder's configured reports directory.
2. Open Chat and select **01 · Advice**. Configure an optional MCP advice tool
   in text mode, or explicitly connect a local MCP server.
3. In **Attach saved evidence**, choose the **Suite** entry for the intended
   run. The existing Investigation entries remain available separately.
   Opening Chat and choosing the run read its saved metadata without running
   benchmarks, starting a projection worker or sending a provider request.
4. Write a question and choose **Send question**. PerfChecker checks the
   bundle's identity and byte integrity, reads its canonical measurements
   locally through the selected controller, then sends bounded evidence to
   the configured MCP tool. The evidence retains quantities, units,
   measurement definitions, collectors, correctness and execution
   qualifications. Raw source files and artifacts are not attached.
5. Inspect the reply as unverified advice. Use **Cancel** to stop an active
   request and wait for cleanup. A modified or unsupported bundle is refused
   before the provider receives measurements.

Selection identifies that workspace and saved run explicitly; it does not pick
a newer unrelated bundle. No new measurement is requested by Send. A small
sample or an unpaired run remains limited evidence, even when the provider
returns a confident answer. Compare compatible recorded results and verify
correctness before accepting a performance claim.

## Open a saved diagnostic report

Extension **1.0.1** can display a saved `perfchecker-diagnosis/1`
JSON report in Investigations. Importing reads existing evidence; it does not
run a workload or independently verify the file's claims.

1. Run **PerfChecker: Open saved diagnostic report**, or choose **Open saved
   diagnostic report** in Investigations. Select a diagnostic JSON file on the
   extension host. With Remote SSH, select a file on that remote host.
2. Read the **Imported saved report — not measured or independently verified in
   this editor session** notice. Review the source path, read time, reported
   statuses, measurement scope and limitations. A filename is not proof of a
   package release or commit.
3. Choose **Open imported JSON snapshot** to inspect the exact text that was
   loaded. This opens an unsaved editor document; it does not reread or change
   the original file. **Snapshot SHA-256** identifies the original bytes, not
   their author or the correctness of their results.

Files must be regular UTF-8 JSON files no larger than **32 MiB**. Unsupported
schemas, malformed completed records, non-finite values and invalid byte counts
are refused. Cancelling the file picker or selecting an invalid file keeps the
previous view. Wait for an active investigation to finish before importing.

For a completed **latency** record, the cards show **Source loading**, **First
lifecycle** and **Warm lifecycle**, in seconds. Source loading excludes the
Julia process startup. The lifecycle includes preparation, the operation,
correctness verification and cleanup. These diagnostic observations from a
fresh process are not three independent warm benchmark distributions.

For a completed **memory** record, the table shows every recorded sample's
**State before**, **State after** and **State + result**, in bytes. These are
reachable Julia object sizes, not total allocated bytes or process RSS. State
and result are traversed together to avoid counting shared objects twice.
Growth can be an intended result or cache; it does not establish a leak.
Unavailable and failed records keep their reported status without invented
values.

### Try the recorded Oxygen reports

Download a report and open it with **PerfChecker: Open saved diagnostic report**:

```@raw html
<table>
<thead><tr><th>Oxygen checkout</th><th>Latency report</th><th>Reachable-memory report</th></tr></thead>
<tbody>
<tr><td>1.10.2</td><td><a href="../examples/real-packages/oxygen-saved-diagnostics/latency-1.10.2.json">Original JSON</a></td><td><a href="../examples/real-packages/oxygen-saved-diagnostics/memory-1.10.2.json">Original JSON</a></td></tr>
<tr><td>1.11.0</td><td><a href="../examples/real-packages/oxygen-saved-diagnostics/latency-1.11.0.json">Original JSON</a></td><td><a href="../examples/real-packages/oxygen-saved-diagnostics/memory-1.11.0.json">Original JSON</a></td></tr>
</tbody>
</table>
```

These four diagnostic reports were collected on 10 October 2026 with
[PerfChecker source ffbf33f](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/commit/ffbf33f0bda61dfc84adfb8e8e6dfd8a404d0642),
whose package tree matches the registered 1.0.1 release. The two Oxygen
checkouts have separate dependency environments. The reports retain
**Performance: not_compared**: these observations do not establish a performance
regression or improvement between the releases.

The native captures below show those original files in VS Code 1.141.0 with
[extension 48b3821](https://github.com/Mirage-Interactive-Fr/PerfCheckerVSCode/commit/48b382160f9cd3a5befa18c11c425b87793e9750)
(packaged VSIX SHA-256 beginning `fac983a008df`). The selected controller contains
registered PerfChecker 1.0.1; importing starts no Julia process. These captures
are separate from the earlier timing and profile campaigns in this guide.

```@raw html
<PluginTabs>
<PluginTabsTab label="Latency · Oxygen 1.10.2"><DocMedia src="/assets/screenshots/vscode/v101/latency-oxygen-1.10.2-fac983.png" alt="Native PerfChecker Investigations view displaying the original Oxygen 1.10.2 diagnostic JSON, its import notice, SHA-256 and three latency phases in seconds" caption="Source loading, first lifecycle and warm lifecycle remain separate quantities. The import notice and reported not_compared status stay visible." /></PluginTabsTab>
<PluginTabsTab label="Latency · Oxygen 1.11.0"><DocMedia src="/assets/screenshots/vscode/v101/latency-oxygen-1.11.0-fac983.png" alt="Native PerfChecker Investigations view displaying the original Oxygen 1.11.0 diagnostic JSON, its import notice, SHA-256 and three latency phases in seconds" caption="The viewer reads the saved report without rerunning it. A reported correctness pass does not establish a performance comparison." /></PluginTabsTab>
</PluginTabs>
<PluginTabs>
<PluginTabsTab label="Memory · Oxygen 1.10.2"><DocMedia src="/assets/screenshots/vscode/v101/memory-oxygen-1.10.2-fac983.png" alt="Native PerfChecker Investigations view displaying all five recorded Oxygen 1.10.2 reachable-memory rows, with state before, state after and state plus result in bytes" caption="Five fresh-state evaluations retain their exact recorded byte counts. Reachable state growth can be an intended result or cache." /></PluginTabsTab>
<PluginTabsTab label="Memory · Oxygen 1.11.0"><DocMedia src="/assets/screenshots/vscode/v101/memory-oxygen-1.11.0-fac983.png" alt="Native PerfChecker Investigations view displaying all five recorded Oxygen 1.11.0 reachable-memory rows and the original report limitations" caption="These counts cover reachable Julia objects. Native and device memory need their own provider; this table does not measure allocation traffic or process RSS." /></PluginTabsTab>
</PluginTabs>
```

Importing adds no saved-run history and executes no paths from the report.
**Advise from saved evidence** and **Explain with configured model** are disabled
for imports, and imported artifacts and source links are not opened. To request
advice, run an investigation or open evidence measured by the selected
workspace through its normal history workflow.

## Notebook versions

The integrated Pluto workflow below is available in extension **1.0.1** with
Core **1.0.1**. Check the [platform scope and macOS limits](vscode.md#Qualification-and-reporting-a-problem).
Extension **1.0.0** used the earlier notebook workflow described at the end of
this section.

## Pluto notebooks in VS Code

The integrated Pluto workflow requires **PerfChecker for VS Code 1.0.1 or newer**
and **PerfChecker core 1.0.1 or newer**. Its separate notebook environment also
requires **PerfCheckerPluto 1.0.1 or newer within the 1.x series**.
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
   A project with an older companion requires an explicit upgrade confirmation.
   Cancelling leaves that environment unchanged; opening Studio never installs
   or upgrades those packages.
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

This earlier native capture uses VSIX candidate `75f84f631ba3`, Core candidate
`6f6155510aa2` and Julia **1.13.1**. It records only the configured opening
phase, not the current release's complete notebook lifecycle. See the
[current qualification](vscode.md#Qualification-and-reporting-a-problem).
The image opens at full resolution when selected.

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

The integration targets Pluto **1.0.4**, PerfChecker
core, PlutoUI, BenchmarkTools, Chairmarks and **PerfCheckerPluto 1.0.1** from
the root repository tag `v1.0.1`. Core 1.0.1 is registered in General and this
tag is available; the Pluto companion's separate General registration is
pending. The extension's guided setup uses that public tag.
Set the folder configuration explicitly when you use several environments:

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

### Use the corrected suite plot renderer

Companion 1.0.1 generates a separate document for each standalone plot, keeping
its JavaScript module state separate when the selected plot changes. The
release's native canvas and interaction checks passed on Linux and Windows,
with stable VS Code and VS Code 1.96. On Intel macOS the figures and interactions
rendered successfully, but the check failed during process inspection after
**Close notebook view**; its final **Stop session** verified cleanup. See the
[qualification notes](vscode.md#Qualification-and-reporting-a-problem) for that
limit. The earlier notebook screenshots retain their own source provenance.

Updating the companion does not rewrite an existing `.jl` notebook. Suite
notebooks generated with companion 1.0.0 retain their earlier plot-rendering
cell. After explicitly preparing the corrected environment, create a **new
Feature suite notebook** with **PerfChecker: New Pluto notebook**, or regenerate
into a new file. Keep the old notebook, edits and saved reports.

For manual generation, run this from the measured package root with its suite
at `perf/suite.jl`, using the public `v1.0.1` companion tag:

```julia
import Pkg
Pkg.activate("perf/pluto")  # The separately prepared notebook environment.
using PerfChecker, PerfCheckerPluto
@assert v"1.0.1" <= Base.pkgversion(PerfCheckerPluto) < v"2.0.0"
new_notebook = joinpath(pwd(), "perf", "notebooks", "performance-1.0.1.jl")
write_suite_notebook(new_notebook;
    suite_path = joinpath(pwd(), "perf", "suite.jl"),
    project = dirname(Base.active_project()))
```

The generator refuses an existing destination by default. Choose a different
new filename if this one already exists. Open the new source, review the suite
and report paths, then launch checks explicitly; the existing notebook and
completed reports remain unchanged.

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
   renderer environment. Use registered **Core 1.0.1** for the cancellation
   fix. The earlier Core 1.0.0 provider can leave a rendering worker running
   after interruption.
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

An earlier opt-in software check used Core source `11011e1f8999`, the Landscape
v0.1.0 scene, five SDK v0.1.1 modules and Mesa **llvmpipe** on a CPU. It observed
40 submitted frames after warmup, six measurements in milliseconds and two
changing scene buffers. Cancellation stopped the tracked owned processes,
preserved an unrelated `.mem` file and published no completed evidence for the
cancelled run. This historical provider check does not qualify the published
extension's native Landscape controls, hardware GPU timing or physical display
presentation. See the [release scope](vscode.md#Qualification-and-reporting-a-problem).

Before a live graphics comparison, keep the scene, quality, device and workload
configuration comparable. Retain the resulting evidence and its configuration;
a changed scene or quality profile requires a new, explicitly selected run.
