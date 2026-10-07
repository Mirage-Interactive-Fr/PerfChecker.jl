# VS Code video walkthroughs

Watch a short passage beside the written steps. Each recording below is
a contiguous passage from the full tutorial with the same English narration,
music and captions. The portrait crop focuses the fields used at that step.
Use the player controls to seek, enable English captions or open full screen.

The videos record real native VS Code interfaces and Julia workers in isolated
qualification workspaces. Their recorded-build captions identify the exact
VSIX and Core source used. These recordings illustrate individual exercised
actions; consult the [qualification notes](vscode.md#Qualification-and-reporting-a-problem)
for the release and platform scope.

The 1.0.1 integration is being qualified. The public 1.0.0 extension and the
candidate Pluto workflow have separate [installation prerequisites](vscode-configuration.md).
The full tutorial and further excerpts will appear here after their footage
and exports have passed review.

| Passage | What to inspect | Written steps |
| --- | --- | --- |
| [02 — native TestItem evidence](#Native-TestItem-evidence) | Item validation, measured units and the report boundary | [Get a first result](vscode.md#Get-a-first-result) |
| [03 — visible suite selection](#Visible-suite-selection) | Search, selection scope and Preview before Run | [Select checks](vscode.md#Design-a-suite-and-compare-targets) |
| [04 — normalized overlays](#Normalized-overlays) | Per-metric minimum, raw values and tooltip units | [Read normalized overlays](vscode-workflows.md#Read-normalized-overlays) |
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
| [18 — investigations and analyzers](#Investigations-and-analyzers) | Benchmark evidence, analyzer status and the real Aqua diagnostic | [Investigate and verify](vscode.md#Investigate-and-verify) |
| [19 — tool discovery and schema](#Tool-discovery-and-schema) | Actual tool name, argument types, required fields and Use | [Configure the advice tool](../mcp-advisor.md#Configure-the-advice-tool) |
| [20 — isolated source review](#Isolated-source-review) | Actual initializer, representative inputs and human decision | [Implementation review](../mcp-advisor.md#Switch-from-advice-to-implementation) |

## Native TestItem evidence

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-02" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-02.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-02-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-02-en.vtt" preload="metadata" alt="Native VS Code TestItem evidence with measured seconds, bytes and item correctness" caption="Read the actual native item's JSON and its measurement boundary. This excerpt uses the same voice and passage as the full tutorial; its recorded build is VSIX 75f84f, Core 6f, VS Code 1.141 on Linux." />
```

## Visible suite selection

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-03" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-03.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-03-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-03-en.vtt" preload="metadata" alt="Actual native PerfChecker suite filtering, visible selection and preview controls" caption="Search for the intended workload, select the visible checks and inspect Preview before running. The close views preserve the actual controls. Recorded build: VSIX 75f84f, Core 975d, VS Code 1.141 on Linux." />
```

## Normalized overlays

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-04" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-04.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-04-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-04-en.vtt" preload="metadata" alt="Actual native PerfChecker minimum-relative chart, raw units and recorded version tooltip" caption="Read each metric against its own minimum, then inspect its raw value. The recorded tooltip is 136 ns with ratio 1.0149; units remain separate. Recorded build: VSIX 75f84f, Core 975d, VS Code 1.141 on Linux." />
```

## Reviewed preparation

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-07" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-07.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-07-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-07-en.vtt" preload="metadata" alt="Actual native PerfChecker preparation action, warning and recovery checkpoint prefix" caption="Review the warning, save editor buffers and explicitly prepare an isolated proposal. The close view preserves the real Prepare implementation button and checkpoint prefix; the full reference continues outside the portrait frame and remains available in the editor. Recorded build: VSIX 75f84f, Core 975d, VS Code 1.141 on Linux, controlled MCP replies." />
```

## Apply, verify and restore

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-08" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-08.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-08-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-08-en.vtt" preload="metadata" alt="Actual native PerfChecker Apply and Restore controls with independently checked Julia results and allocation" caption="Apply the reviewed source change, inspect the independent Julia oracle and restore the previous source exactly. The recorded workload's allocation probe is 8072 B before and 0 B after; compatible timing measurements remain a separate step. Recorded build: VSIX 75f84f, Core 975d, VS Code 1.141 on Linux, controlled MCP replies." />
```

## Julia runtimes and projects

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-09" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-09.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-09-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-09-en.vtt" preload="metadata" alt="Actual native PerfChecker terminal, Julia REPL and debug sessions using two folder-specific controller projects" caption="Inspect VERSION and the actual active project in each surface. This recording uses Julia extension 1.249.2 with Julia 1.12.7 for REPL and debug, and Julia 1.13.1 for PerfChecker workers. Recorded build: VSIX 2e722, Core 4eec, VS Code 1.141 on Linux; the two source debug sessions have independent controller projects." />
```

## First native check

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-10" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-10.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-10-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-10-en.vtt" preload="metadata" alt="Actual native VS Code first PerfChecker TestItem, source oracle and run controls" caption="Start with the Vector reduction TestItem and its explicit expected sum, then run its native measurement. Recorded build: VSIX 75f84f, Core 6f, VS Code 1.141 on Linux." />
```

## Declared suite source

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-11" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-11.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-11-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-11-en.vtt" preload="metadata" alt="Actual PerfChecker declared suite source and native workload selection in VS Code" caption="Keep the factory, measured operation and required correctness oracle together. Recorded builds: VSIX 75f84f, Core 6f and 975d, VS Code 1.141 on Linux." />
```

## Check types

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-12" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-12.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-12-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-12-en.vtt" preload="metadata" alt="Actual native PerfChecker check controls for BenchmarkTools, Chairmarks, CPU, wall-time and allocation evidence" caption="Choose the check that answers the question and inspect its prerequisites. The footage shows the real native tutorial workload. Recorded build: VSIX 75f84f, Core 975d, VS Code 1.141 on Linux." />
```

## Comparison targets

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-13" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-13.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-13-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-13-en.vtt" preload="metadata" alt="Actual native PerfChecker comparison package, feature, reference aggregation and target controls" caption="Resolve the intended Git state and review the baseline, candidate and aggregation policy before a comparison. Recorded build: VSIX 75f84f, Core 975d, VS Code 1.141 on Linux." />
```

## Cancellation and cleanup

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-14" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-14.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-14-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-14-en.vtt" preload="metadata" alt="Actual native PerfChecker investigation cancellation, controller cleanup and recovery checklist" caption="Cancel an active investigation and wait for the final controller-cleanup status. The recovery checklist explains subsequent checks; it does not show those checks executing. Recorded build: VSIX 75f84f, Core 975d, VS Code 1.141 on Linux." />
```

## Saved distributions


```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-15" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-15.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-15-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-15-en.vtt" preload="metadata" alt="Actual PerfChecker saved distribution, allocation median of 48 bytes, raw series and source JSON in native VS Code" caption="Inspect actual worker measurements in their own units. The 48 B median is read from the recorded Example hello report. Recorded build: VSIX 75f84f, Core 975d, VS Code 1.141 on Linux." />
```

## Recorded profile stacks

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-16" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-16.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-16-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-16-en.vtt" preload="metadata" alt="Actual native PerfChecker CPU flame graph with a closer view of sum_squares, materialize and copy" caption="Follow real recorded profile stacks. The closer view preserves the original frame labels; profile weights describe the stated collector. Recorded build: VSIX 75f84f, Core 975d, VS Code 1.141 on Linux." />
```

## Investigations and analyzers

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-18" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-18.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-18-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-18-en.vtt" preload="metadata" alt="Actual native PerfChecker investigation benchmark, analyzers and Aqua quality diagnostic" caption="Inspect the benchmark and analyzer outcomes individually. The Aqua diagnostic frame is held for reading: the analyzer completed with correctness not checked and quality failed; this passage does not imply a new execution. Recorded build: VSIX 75f84f, Core 975d, VS Code 1.141 on Linux." />
```

## Tool discovery and schema

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-19" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-19.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-19-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-19-en.vtt" preload="metadata" alt="Actual native PerfChecker MCP tool inventory, input schema and Use selection confirmation" caption="Discover the server tool, inspect its real properties and required arguments, then select Use. The actual schema frames are held for reading; this local protocol fixture uses ask_fixture, question and context. Recorded build: VSIX 2e722, Core 4eec, VS Code 1.141 on Linux; connection discovery and selection are distinct from answer generation." />
```

## Isolated source review

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-20" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-20.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-20-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-20-en.vtt" preload="metadata" alt="Actual native PerfChecker source diff, initialized sum_squares reduction and explicit human review" caption="Read the actual isolated source diff and its explicit initializer, then validate representative inputs before applying. The recorded Float64 example covers empty, signed and 1,000-element inputs; other types need their own oracle. Recorded build: VSIX 75f84f, Core 975d, VS Code 1.141 on Linux, controlled MCP replies." />
```

Keep the written configuration and saved evidence alongside the video. A
profile, correctness result and performance observation each have their own
boundary; a captioned example should help you inspect those boundaries in
your package.
