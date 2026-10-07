# VS Code video walkthroughs

Watch a short passage beside the written steps. Each recording below is
a contiguous passage from the full tutorial with the same English narration,
music and captions. The portrait crop focuses the fields used at that step.
Use the player controls to seek, enable English captions or open full screen.

The videos record real native VS Code interfaces and Julia workers in isolated
qualification workspaces. Their recorded-build captions identify the exact
VSIX and Core source used. These recordings illustrate individual exercised
actions; consult the [qualification notes](vscode.md#qualification-and-reporting-a-problem)
for the release and platform scope.

The 1.0.1 integration is being qualified. The public 1.0.0 extension and the
candidate Pluto workflow have separate [installation prerequisites](vscode-configuration.md).
The full tutorial and further excerpts will appear here after their footage
and exports have passed review.

| Passage | What to inspect | Written steps |
| --- | --- | --- |
| [02 — native TestItem evidence](#native-testitem-evidence) | Item validation, measured units and the report boundary | [Get a first result](vscode.md#get-a-first-result) |
| [03 — visible suite selection](#visible-suite-selection) | Search, selection scope and Preview before Run | [Select checks](vscode.md#design-a-suite-and-compare-targets) |
| [04 — normalized overlays](#normalized-overlays) | Per-metric minimum, raw values and tooltip units | [Read normalized overlays](vscode-workflows.md#read-normalized-overlays) |
| [10 — first native check](#first-native-check) | The Vector reduction item, correctness oracle and Run | [Get a first result](vscode.md#get-a-first-result) |
| [11 — declared suite source](#declared-suite-source) | Factory, measured operation and correctness oracle | [Design a suite](vscode.md#design-a-suite-and-compare-targets) |
| [12 — check types](#check-types) | Collector scope and required dependencies | [Choose the evidence](vscode.md#choose-the-evidence-for-your-question) |
| [13 — comparison targets](#comparison-targets) | Git state, baseline and aggregation policy | [Compare a working change](vscode.md#compare-a-working-change-with-a-known-revision) |
| [15 — saved distributions](#saved-distributions) | Real sample spread, allocation unit and raw data | [Read a distribution](vscode-workflows.md#read-a-distribution) |
| [16 — recorded profile stacks](#recorded-profile-stacks) | Actual frame names and the collector's sampling scope | [Follow a recorded profile](vscode-workflows.md#follow-a-recorded-profile) |

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

## Saved distributions


```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-15" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-15.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-15-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-15-en.vtt" preload="metadata" alt="Actual PerfChecker saved distribution, allocation median of 48 bytes, raw series and source JSON in native VS Code" caption="Inspect actual worker measurements in their own units. The 48 B median is read from the recorded Example hello report. Recorded build: VSIX 75f84f, Core 975d, VS Code 1.141 on Linux." />
```

## Recorded profile stacks

```@raw html
<DocMedia video short recording="perfchecker-vscode-v101-short-16" src="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-16.mp4" poster="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-16-poster.jpg" subtitles="/assets/videos/vscode/v101/perfchecker-vscode-1.0.1-short-16-en.vtt" preload="metadata" alt="Actual native PerfChecker CPU flame graph with a closer view of sum_squares, materialize and copy" caption="Follow real recorded profile stacks. The closer view preserves the original frame labels; profile weights describe the stated collector. Recorded build: VSIX 75f84f, Core 975d, VS Code 1.141 on Linux." />
```

Keep the written configuration and saved evidence alongside the video. A
profile, correctness result and performance observation each have their own
boundary; a captioned example should help you inspect those boundaries in
your package.
