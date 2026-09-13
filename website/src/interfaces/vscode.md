# VS Code

The extension adds performance items to VS Code's Testing view.

## Prepare the workspace

1. Install the PerfChecker extension (during the preview, from the supplied `.vsix` via **Extensions → Install from VSIX…**).
2. Use a Julia environment with PerfChecker, TestItemRunner and your package's test dependencies.
3. Set **PerfChecker: Runner Project** (`perfchecker.runnerProject`) to that environment's absolute path.

## Run one item

1. Command palette → **PerfChecker: Discover existing test items**.
2. Testing view → expand **PerfChecker items**.
3. Select one item and run it.
4. Read the collector, unit and scope beside the value.

## Read the result

- The Testing summary duration can include starting the worker; the item measurement has its own boundary.
- A green functional test does not establish a performance budget.
- Allocated bytes are allocation activity; a flame graph attributes sampled work to call paths.

## Workspace model

```text
package → feature → check type → target
```

Run a selection, open its plots, read worker logs, or jump to the workload script.

## Suite editor

Open **PerfChecker: Open visual suite editor** (needs a suite file). It supports:

- global and per-feature check selection;
- version ranges, search, sorting and ordering;
- named targets for a branch, tag, commit, working tree or release;
- exact or grouped baselines with median/mean/minimum/maximum aggregation;
- direct execution with progress;
- a saved selection in `perf/perfchecker-ui.json`.


## Recorded examples

```@raw html
<DocMedia src="/examples/bibliography/vscode/native-items.png" alt="Bibliography export workload passed in VS Code while its format API item remains unrun" caption="One selected Bibliography item executed through PerfChecker's native Testing controller. Follow the Bibliography walkthrough to prepare the same workspace." />
```

## Next

[Existing TestItems](../test-items.md) covers tags and environments. [Shared scenarios](../shared-scenarios.md) covers the investigation panel.

```@raw html
<a id="Run-one-existing-item"></a>
<a id="Read-the-result-before-comparing-it"></a>
<a id="Visual-suite-editor"></a>
<a id="Results"></a>
<a id="Optional-investigations"></a>
```
