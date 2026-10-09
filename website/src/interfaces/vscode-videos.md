# VS Code video walkthroughs

The written guides provide the complete setup and workflow. Start with
[VS Code configuration](vscode-configuration.md),
[get a first result](vscode.md#Get-a-first-result), or
[read the saved evidence](vscode-workflows.md#Read-a-distribution).
You can follow those steps without a video.

## New series

The new series starts with a concrete comparison and a readable plot, then
explains one question or action at a time. It uses a short introduction,
autonomous episodes within five thematic chapters, and individual Shorts
composed for portrait viewing. A Short explains one meaningful backend or
feature; there is no fixed clip count.

The introduction is complete as a local production file, about four minutes
long. It shows a Bibliography comparison, timing and allocation examples,
an Oxygen router example, two genuine read-only agent exchanges through MCP,
and the Studio home page. The first BenchmarkTools Short is also complete
locally, with a separately composed portrait declaration and graph. The
remaining episodes are in production. The new series has not been published
on YouTube; links will be added after publication.

| Part | What it teaches | Production status | Written guide |
| --- | --- | --- | --- |
| Introduction | Start from a result, identify the question and choose the next step | Completed locally; not published | [Investigate a workload](../guide/investigate.md) |
| 1 — Installation and a first result | Prepare projects, run a TestItem, then save and plot a feature-suite result | Scripts and example evidence prepared; filming remains | [Setup](vscode-configuration.md) and [first result](vscode.md#Get-a-first-result) |
| 2 — Configuration and comparisons | Select checks, backends, targets and compatible measurement settings | In preparation | [Design a suite](vscode.md#Design-a-suite-and-compare-targets) and [comparisons](../tutorials/comparisons.md) |
| 3 — Reading measurements | Interpret distributions, allocations and profiles in their own units | In preparation | [Understand measurements](../guide/understanding-measurements.md) |
| 4 — Choosing an interface | Use REPL, downloadable Pluto notebooks, Oxygen Web and VS Code for the task | In preparation | [REPL and Pluto](repl-pluto.md), [Web](web-studio.md) and [VS Code workflows](vscode-workflows.md) |
| 5 — MCP and a reviewed change | Discuss saved evidence, review a proposal, apply, measure and restore | Read-only introduction recorded; the implementation sequence remains to film | [MCP advisor](../mcp-advisor.md) |

Each chapter can contain several independent episodes. The videos supplement
the documentation; installation prerequisites, example sources, saved evidence
and recovery steps remain in the guides. Check the
[installation prerequisites](vscode-configuration.md) and
[qualification notes](vscode.md#Qualification-and-reporting-a-problem) for
release availability and platform scope.

## Earlier recordings

The recordings below preserve earlier candidate builds and exercised actions.
Their dense pacing and portrait crops are being replaced by the new series.
They remain available as historical reference, with their existing captions,
source identities and section links. They are not the current introduction or
the new portrait Shorts. Captions identify passages whose MCP replies come
from controlled protocol fixtures.

Use the player controls to seek, enable English captions or open full screen.
Playback stays explicit; the written steps above remain usable on their own.

### Full tutorial

The earlier 29-minute recording combines environment selection, measurements,
plots, Pluto notebooks and a controlled implementation example. Its chapter
timings and English captions are retained to identify those earlier scenes.
The captions record the candidate builds, exercised actions and platform scope.

```@raw html
<DocMedia video external recording="perfchecker-vscode-v101-master" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-master.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-master-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-en.vtt" preload="none" alt="PerfChecker VS Code performance workflow tutorial with real native editor footage and English captions" caption="Earlier 29-minute recording retained for reference, in thirteen chapters, with English narration, captions and background music. Recorded candidate builds and controlled MCP replies are identified in their passages. The long MP4 streams from its separate public asset." />
```

| Time | Chapter |
| --- | --- |
| 00:00 | A performance workflow inside the editor |
| 02:06 | Prepare Julia and the selected workspace |
| 04:54 | A first check with TestItemRunner |
| 07:46 | Design a suite and select the experiment |
| 10:42 | Targets, comparison policy and cancellation |
| 12:48 | Read the saved plots |
| 14:38 | Inspect a real flame graph |
| 16:23 | Pluto notebooks inside VS Code |
| 19:18 | Scenarios and available analyzers |
| 20:22 | MCP configuration and a follow-up conversation |
| 23:02 | A checkpoint and an isolated implementation |
| 24:53 | Apply, validate, remeasure and restore |
| 27:55 | Finish with reproducibility and useful limits |

### Short passages

| Passage | What to inspect | Written steps |
| --- | --- | --- |
| [01 — existing controller setup](#Existing-controller-setup) | Explicit controller selection, resolved project and Studio readiness | [Guided setup](vscode-configuration.md#Guided-setup-from-Studio) |
| [02 — native TestItem evidence](#Native-TestItem-evidence) | Item validation, measured units and the report boundary | [Get a first result](vscode.md#Get-a-first-result) |
| [03 — visible suite selection](#Visible-suite-selection) | Search, selection scope and Preview before Run | [Select checks](vscode.md#Design-a-suite-and-compare-targets) |
| [04 — normalized overlays](#Normalized-overlays) | Per-metric minimum, raw values and tooltip units | [Read normalized overlays](vscode-workflows.md#Read-normalized-overlays) |
| [05 — reactive source and saved reports](#Reactive-source-and-saved-reports) | Cell submission, source autosave, completed evidence and reopening | [Edit, save and reopen](vscode-workflows.md#Edit,-save-and-reopen) |
| [06 — measured conversation](#Measured-conversation) | Actual selected report, follow-up questions and validation before edits | [Talk to the advisor](../mcp-advisor.md#Talk-to-the-advisor) |
| [07 — reviewed preparation](#Reviewed-preparation) | Actual warning, explicit Prepare action and recovery reference | [Prepare implementation](../mcp-advisor.md#Switch-from-advice-to-implementation) |
| [08 — apply, verify and restore](#Apply,-verify-and-restore) | Independent oracle, recorded allocation and exact recovery | [Checkpoints and recovery](../mcp-advisor.md#Checkpoints-and-recovery) |
| [09 — Julia runtimes and projects](#Julia-runtimes-and-projects) | Runtime version, active project and two folder-specific debug contexts | [Choose Julia environments](vscode-configuration.md#Choose-Julia-environments) |
| [10 — first native check](#First-native-check) | The Vector reduction item, correctness oracle and Run | [Get a first result](vscode.md#Get-a-first-result) |
| [11 — declared suite source](#Declared-suite-source) | Factory, measured operation and correctness oracle | [Design a suite](vscode.md#Design-a-suite-and-compare-targets) |
| [12 — check types](#Check-types) | Collector scope and required dependencies | [Choose the evidence](vscode.md#Choose-the-evidence-for-your-question) |
| [13 — comparison targets](#Comparison-targets) | Git state, baseline and aggregation policy | [Compare a working change](vscode.md#Compare-a-working-change-with-a-known-revision) |
| [14 — cancellation and cleanup](#Cancellation-and-cleanup) | Final controller status and explicit recovery checks | [Cancel a run](vscode.md#Cancel-a-run-and-wait-for-cleanup) |
| [15 — saved distributions](#Saved-distributions) | Real sample spread, allocation unit and raw data | [Read a distribution](vscode-workflows.md#Read-a-distribution) |
| [16 — recorded profile stacks](#Recorded-profile-stacks) | Actual frame names and the collector's sampling scope | [Follow a recorded profile](vscode-workflows.md#Follow-a-recorded-profile) |
| [17 — Pluto session shutdown](#Pluto-session-shutdown) | Evaluated cell, Cancel, Confirm and the final session state | [Manage the session](vscode-workflows.md#Manage-the-session-and-saved-source) |
| [18 — investigations and analyzers](#Investigations-and-analyzers) | Benchmark evidence, analyzer status and the real Aqua diagnostic | [Investigate and verify](vscode.md#Investigate-and-verify) |
| [19 — tool discovery and schema](#Tool-discovery-and-schema) | Actual tool name, argument types, required fields and Use | [Configure the advice tool](../mcp-advisor.md#Configure-the-advice-tool) |
| [20 — isolated source review](#Isolated-source-review) | Actual initializer, representative inputs and human decision | [Implementation review](../mcp-advisor.md#Switch-from-advice-to-implementation) |

### Existing controller setup

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-01" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-01-r2.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-01-r2-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-01-r2-en.vtt" walkthrough="/interfaces/vscode-videos.html#Full-tutorial" chapter="02 · Prepare Julia and the selected workspace" preload="none" alt="Actual native PerfChecker existing controller selection, resolved project and Studio Ready status" caption="Choose Use an existing controller, select the prepared project and wait for Studio Ready. The closing Reading guide summarizes the environment checks to make after setup. Recorded candidate: VSIX 7add564, Core 4eec7f3, VS Code 1.141.0 on Linux. The controller was prepared from Core source before recording; registered installation has separate qualification." />
```

### Native TestItem evidence

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-02" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-02.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-02-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-02-en.vtt" walkthrough="/interfaces/vscode-videos.html#Full-tutorial" chapter="03 · A first check with TestItemRunner" preload="none" alt="Native VS Code TestItem evidence with measured seconds, bytes and item correctness" caption="Read the actual native item's JSON and its measurement boundary. This excerpt uses the same voice and passage as the full tutorial; its recorded build is VSIX 75f84f, Core 6f, VS Code 1.141 on Linux." />
```

### Visible suite selection

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-03" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-03.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-03-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-03-en.vtt" walkthrough="/interfaces/vscode-videos.html#Full-tutorial" chapter="04 · Design a suite and select the experiment" preload="none" alt="Actual native PerfChecker suite filtering, visible selection and preview controls" caption="Search for the intended workload, select the visible checks and inspect Preview before running. The close views preserve the actual controls. Recorded build: VSIX 75f84f, Core 975d, VS Code 1.141 on Linux." />
```

### Normalized overlays

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-04" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-04.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-04-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-04-en.vtt" walkthrough="/interfaces/vscode-videos.html#Full-tutorial" chapter="06 · Read the saved plots" preload="none" alt="Actual native PerfChecker minimum-relative chart, raw units and recorded version tooltip" caption="Read each metric against its own minimum, then inspect its raw value. The recorded tooltip is 136 ns with ratio 1.0149; units remain separate. Recorded build: VSIX 75f84f, Core 975d, VS Code 1.141 on Linux." />
```

### Reactive source and saved reports

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-05" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-05.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-05-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-05-en.vtt" walkthrough="/interfaces/vscode-videos.html#Full-tutorial" chapter="08 · Pluto notebooks inside VS Code" preload="none" alt="Actual native PerfChecker Pluto cell editing, reactive output, source autosave, Save completed reports and notebook reopening" caption="Submit a cell edit, inspect its reactive output and retain the saved notebook source separately from completed reports. Then reopen the actual notebook. The source interaction is slowed and frames are held for reading. Recorded candidate: VSIX 7add564, Core 4eec7f3, VS Code 1.141.0 on Linux." />
```

### Measured conversation

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-06" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-06.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-06-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-06-en.vtt" walkthrough="/interfaces/vscode-videos.html#Full-tutorial" chapter="10 · MCP configuration and a follow-up conversation" preload="none" alt="Native PerfChecker conversation with a saved measured run, two contextual questions and controlled MCP replies" caption="Attach the actual measured run, ask a follow-up and agree on validation before requesting an edit. The recorded report shows 8072 B median over two samples with correctness passed; measured evidence IDs and bounded context were checked. The local MCP protocol fixture supplies controlled replies, with frames held for reading. Recorded build: VSIX 2e722, Core 4eec, VS Code 1.141 on Linux. Source is unchanged during advice; cancellation is outside this passage." />
```

### Reviewed preparation

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-07" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-07.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-07-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-07-en.vtt" walkthrough="/interfaces/vscode-videos.html#Full-tutorial" chapter="11 · A checkpoint and an isolated implementation" preload="none" alt="Actual native PerfChecker preparation action, warning and recovery checkpoint prefix" caption="Review the warning, save editor buffers and explicitly prepare an isolated proposal. The close view preserves the real Prepare implementation button and checkpoint prefix; the full reference continues outside the portrait frame and remains available in the editor. Recorded build: VSIX 75f84f, Core 975d, VS Code 1.141 on Linux, controlled MCP replies." />
```

### Apply, verify and restore

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-08" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-08.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-08-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-08-en.vtt" walkthrough="/interfaces/vscode-videos.html#Full-tutorial" chapter="12 · Apply, validate, remeasure and restore" preload="none" alt="Actual native PerfChecker Apply and Restore controls with independently checked Julia results and allocation" caption="Apply the reviewed source change, inspect the independent Julia oracle and restore the previous source exactly. The recorded workload's allocation probe is 8072 B before and 0 B after; compatible timing measurements remain a separate step. Recorded build: VSIX 75f84f, Core 975d, VS Code 1.141 on Linux, controlled MCP replies." />
```

### Julia runtimes and projects

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-09" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-09.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-09-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-09-en.vtt" walkthrough="/interfaces/vscode-videos.html#Full-tutorial" chapter="02 · Prepare Julia and the selected workspace" preload="none" alt="Actual native PerfChecker terminal, Julia REPL and debug sessions using two folder-specific controller projects" caption="Inspect VERSION and the actual active project in each surface. This recording uses Julia extension 1.249.2 with Julia 1.12.7 for REPL and debug, and Julia 1.13.1 for PerfChecker workers. Recorded build: VSIX 2e722, Core 4eec, VS Code 1.141 on Linux; the two source debug sessions have independent controller projects." />
```

### First native check

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-10" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-10.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-10-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-10-en.vtt" walkthrough="/interfaces/vscode-videos.html#Full-tutorial" chapter="03 · A first check with TestItemRunner" preload="none" alt="Actual native VS Code first PerfChecker TestItem, source oracle and run controls" caption="Start with the Vector reduction TestItem and its explicit expected sum, then run its native measurement. Recorded build: VSIX 75f84f, Core 6f, VS Code 1.141 on Linux." />
```

### Declared suite source

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-11" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-11.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-11-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-11-en.vtt" walkthrough="/interfaces/vscode-videos.html#Full-tutorial" chapter="04 · Design a suite and select the experiment" preload="none" alt="Actual PerfChecker declared suite source and native workload selection in VS Code" caption="Keep the factory, measured operation and required correctness oracle together. Recorded builds: VSIX 75f84f, Core 6f and 975d, VS Code 1.141 on Linux." />
```

### Check types

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-12" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-12.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-12-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-12-en.vtt" walkthrough="/interfaces/vscode-videos.html#Full-tutorial" chapter="04 · Design a suite and select the experiment" preload="none" alt="Actual native PerfChecker check controls for BenchmarkTools, Chairmarks, CPU, wall-time and allocation evidence" caption="Choose the check that answers the question and inspect its prerequisites. The footage shows the real native tutorial workload. Recorded build: VSIX 75f84f, Core 975d, VS Code 1.141 on Linux." />
```

### Comparison targets

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-13" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-13.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-13-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-13-en.vtt" walkthrough="/interfaces/vscode-videos.html#Full-tutorial" chapter="05 · Targets, comparison policy and cancellation" preload="none" alt="Actual native PerfChecker comparison package, feature, reference aggregation and target controls" caption="Resolve the intended Git state and review the baseline, candidate and aggregation policy before a comparison. Recorded build: VSIX 75f84f, Core 975d, VS Code 1.141 on Linux." />
```

### Cancellation and cleanup

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-14" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-14.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-14-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-14-en.vtt" walkthrough="/interfaces/vscode-videos.html#Full-tutorial" chapter="05 · Targets, comparison policy and cancellation" preload="none" alt="Actual native PerfChecker investigation cancellation, controller cleanup and recovery checklist" caption="Cancel an active investigation and wait for the final controller-cleanup status. The recovery checklist explains subsequent checks; it does not show those checks executing. Recorded build: VSIX 75f84f, Core 975d, VS Code 1.141 on Linux." />
```

### Saved distributions


```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-15" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-15.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-15-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-15-en.vtt" walkthrough="/interfaces/vscode-videos.html#Full-tutorial" chapter="06 · Read the saved plots" preload="none" alt="Actual PerfChecker saved distribution, allocation median of 48 bytes, raw series and source JSON in native VS Code" caption="Inspect actual worker measurements in their own units. The 48 B median is read from the recorded Example hello report. Recorded build: VSIX 75f84f, Core 975d, VS Code 1.141 on Linux." />
```

### Recorded profile stacks

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-16" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-16.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-16-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-16-en.vtt" walkthrough="/interfaces/vscode-videos.html#Full-tutorial" chapter="07 · Inspect a real flame graph" preload="none" alt="Actual native PerfChecker CPU flame graph with a closer view of sum_squares, materialize and copy" caption="Follow real recorded profile stacks. The closer view preserves the original frame labels; profile weights describe the stated collector. Recorded build: VSIX 75f84f, Core 975d, VS Code 1.141 on Linux." />
```

### Pluto session shutdown

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-17" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-17.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-17-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-17-en.vtt" walkthrough="/interfaces/vscode-videos.html#Full-tutorial" chapter="08 · Pluto notebooks inside VS Code" preload="none" alt="Actual native PerfChecker Pluto evaluated cell, Shutdown confirmation Cancel and Confirm, and final session state" caption="Inspect the evaluated result 9, cancel the notebook's shutdown question, then confirm it and inspect the final session state. Actions are slowed and frames held for reading. Recorded candidate: VSIX b899ea751d7b, Core 59578c840d94, VS Code 1.141.0 on Linux. Owned workers, private files and allocation journals were checked before test teardown; the shared listener remained available. This passage does not establish every platform or arbitrary callback completion after a forced stop." />
```

### Investigations and analyzers

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-18" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-18.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-18-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-18-en.vtt" walkthrough="/interfaces/vscode-videos.html#Full-tutorial" chapter="09 · Scenarios and available analyzers" preload="none" alt="Actual native PerfChecker investigation benchmark, analyzers and Aqua quality diagnostic" caption="Inspect the benchmark and analyzer outcomes individually. The Aqua diagnostic frame is held for reading: the analyzer completed with correctness not checked and quality failed; this passage does not imply a new execution. Recorded build: VSIX 75f84f, Core 975d, VS Code 1.141 on Linux." />
```

### Tool discovery and schema

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-19" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-19.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-19-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-19-en.vtt" walkthrough="/interfaces/vscode-videos.html#Full-tutorial" chapter="10 · MCP configuration and a follow-up conversation" preload="none" alt="Actual native PerfChecker MCP tool inventory, input schema and Use selection confirmation" caption="Discover the server tool, inspect its real properties and required arguments, then select Use. The actual schema frames are held for reading; this local protocol fixture uses ask_fixture, question and context. Recorded build: VSIX 2e722, Core 4eec, VS Code 1.141 on Linux; connection discovery and selection are distinct from answer generation." />
```

### Isolated source review

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-20" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-20.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-20-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-20-en.vtt" walkthrough="/interfaces/vscode-videos.html#Full-tutorial" chapter="11 · A checkpoint and an isolated implementation" preload="none" alt="Actual native PerfChecker source diff, initialized sum_squares reduction and explicit human review" caption="Read the actual isolated source diff and its explicit initializer, then validate representative inputs before applying. The recorded Float64 example covers empty, signed and 1,000-element inputs; other types need their own oracle. Recorded build: VSIX 75f84f, Core 975d, VS Code 1.141 on Linux, controlled MCP replies." />
```

Keep the written configuration and saved evidence alongside the video. A
profile, correctness result and performance observation each have their own
boundary; a captioned example should help you inspect those boundaries in
your package.
