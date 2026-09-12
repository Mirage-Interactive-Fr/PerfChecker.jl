# VS Code

## Prepare the workspace

Install the PerfChecker editor extension and use a Julia environment containing
PerfChecker V1, TestItemRunner and your package's test dependencies. During the
unpublished V1 preview, install the supplied `.vsix` through **Extensions →
Install from VSIX…**, then reload the window. The extension source is in the
[PerfCheckerVSCode repository](https://github.com/Mirage-Interactive-Fr/PerfCheckerVSCode).

For the recorded example, first run `setup.jl items` from
`examples/bibliography/` in the PerfChecker checkout. Open that directory in
VS Code, and set **PerfChecker: Runner Project** (`perfchecker.runnerProject`)
to the absolute path of its `.controller/items` directory.

## Run one existing item

1. Open the command palette and choose **PerfChecker: Discover existing test items**.
2. In Testing, expand **PerfChecker items** and select **Bibliography export workload**.
3. Run that item. Leave **Bibliography format API** unselected for this first run.
4. Inspect the outcome and measurements. The screenshot below shows this selection.

For your own package, open its root and select its prepared test environment in
the same setting. You can use the [downloadable item](../guide/first-check.md)
instead of the pinned Bibliography example.

To measure existing `@testitem` declarations directly, use **PerfChecker: Discover
existing test items** and the **PerfChecker items** controller in the Testing view.
Select an individual item or a subset. See [existing test items](../test-items.md)
for environment setup, tags and the distinction between correctness and budgets.

```@raw html
<DocMedia src="/examples/bibliography/vscode/native-items.png" alt="Bibliography export workload passed in VS Code while its format API item remains unrun" caption="One selected Bibliography item executed through PerfChecker's native Testing controller. Follow the Bibliography walkthrough to prepare the same workspace." />
```

The VS Code extension is PerfChecker's central graphical workspace. It reads the
same plan and UI configuration as the CLI, Oxygen, Pluto, and documentation
adapters; it does not invent a second suite format.

## Read the result before comparing it

The Testing view shows whether the selected item completed successfully. Its
overall run duration can include starting the worker and arranging the run.
The item measurement has its own boundary, including the code and assertions
inside that item. A prepared `export_bibtex` benchmark excludes preparation
outside the timed operation, so these durations answer different questions.

In a result panel, read the collector, unit and scope alongside the value.
Allocated bytes describe allocation activity, while a flame graph attributes
sampled work to call paths. A green functional test does not establish a
performance budget. The [measurement tutorial](../guide/understanding-measurements.md)
explains these distinctions with recorded Bibliography results.

## Workspace model

The Explorer and Testing views present:

```text
package → business feature → check type → target
```

From any relevant node you can run the selection, open its visual output, view
worker logs, or jump to the exact workload script. Check types remain selectable
options of a business feature, so `import_bibtex` is not duplicated into fake
features such as `import_bibtex_profile`.

## Visual suite editor

This part requires a software suite file. For Bibliography, prepare with
`setup.jl`, select `.controller/core` as the runner project and choose `suite.jl`.
The native-item environment above and the suite controller have different jobs.
Open **PerfChecker: Open visual suite editor** from the command palette. The
editor supports:

- global and per-feature check-type selection;
- version ranges, search, sorting, colour labels, and drag-and-drop ordering;
- named comparison targets for a branch, tag, commit, working tree, or release;
- exact or grouped baselines with median, mean, minimum, or maximum aggregation;
- direct execution and progress updates;
- persistent selection and documentation blocks in
  `perf/perfchecker-ui.json`, a reusable JSON configuration file.

The comparison-target picker scans the selected package repository for local and
remote branches, tags, and recent commits. It also parses a plain ref, a full
SHA, GitHub/GitLab tree/tag/commit URLs, and `owner/repository@ref` shorthand.
Set a compatibility version when an older or experimental target needs a
specific workload variant.

## Results

The output action discovers the latest result matching the selected suite,
package, feature, check, or target. Available views include BenchmarkTools and
Chairmarks distributions, version trajectories, deltas, allocation pie/file/
line/heatmap views, and allocation/CPU/wall-time flame graphs.

Standalone HTML views provide point inspection for timing distributions and
version series, and hover or keyboard focus for SVG flame cells. Other Makie
inspector callbacks require a live Julia session. Flame tooltips expose the full call path and source
location; colour semantics identify allocation, garbage collection, runtime
dispatch, and unstable inference evidence when the collector supplied it.

Use the [Bibliography walkthrough](../tutorials/bibliography.md) to try a complete
suite and two native items that reuse its upstream tests and export workload.

## Optional investigations

For the shared-scenario workflow, **PerfChecker: Open investigations** adds
discovery from tests, explicit adoption, measurements, source-linked diagnostics,
saved advice and before/after comparison. Julia CodeLens and the Testing view
select the same declared scenarios. See [Shared scenarios](../shared-scenarios.md)
for the lifecycle contract, prepared environments and qualification limits.

The panel also exposes the searchable tool catalogue, CI synchronization,
filterable CPU/allocation stacks, bounded investigations and explanations from
an optional configured model. **Model settings** selects an endpoint/protocol or
an advisor JSON file; **Explain with configured model** consumes saved advice.
`advisorInvestigates` remains disabled by default. See
[Optional models](../advisors.md) for provider settings and evidence boundaries.
