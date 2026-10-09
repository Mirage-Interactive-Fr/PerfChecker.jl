```@raw html
<a id="Investigate-a-performance-change"></a>
```

# Investigate a change

Find which calls account for a cost change.

## Collect a profile

From `examples/bibliography/`, with the controller prepared:

```sh
julia --startup-file=no --project=.controller/core run.jl profile_alloc Bibliography export_bibtex
julia --startup-file=no --project=.controller/core run.jl profile       Bibliography export_bibtex
julia --startup-file=no --project=.controller/core run.jl wall_profile  Bibliography export_bibtex
```

Keep the printed report directory. Each command collects a separate profile of the same operation.

## Use the same investigation in your interface

Start from one named workload and an explicit check. Keep the input, source
revision and correctness check beside the result. Selecting a profile is a
configuration action; launch it deliberately and wait for its saved report.

```@raw html
<PluginTabs>
<PluginTabsTab label="VS Code">
<p>Open <strong>PerfChecker Studio</strong> in the package workspace. Select the
workload and its profile check, inspect the planned rows, then launch. Open the
completed run from results and choose its CPU, task or allocation view. For
shared scenarios, the selected catalog must declare the collector you want;
changing an interface cannot add an undeclared measurement.</p>
<p><a href="../interfaces/vscode.html">VS Code workflow</a> ·
<a href="../interfaces/vscode-configuration.html">Controller and worker setup</a></p>
<DocMedia src="/assets/screenshots/vscode-studio.png"
alt="Recorded VS Code Studio workload and check selection"
caption="Recorded Studio selection. Review the workload and planned check before launching a new run." />
</PluginTabsTab>
<PluginTabsTab label="Pluto">
<p>Open the <a href="../interfaces/repl-pluto.html">runnable Bibliography
notebook</a> in its prepared environment. Choose the profile check in the plan,
then press <strong>Launch selected checks</strong>. Refresh its status and save
completed reports before opening the profile. Reactive selector edits do not
launch measurements.</p>
<DocMedia src="/examples/bibliography/pluto/selection.png"
alt="Recorded Pluto notebook with Bibliography plan selectors"
caption="The notebook exposes the plan and explicit launch controls. Download its Julia source to reproduce the workflow." />
</PluginTabsTab>
<PluginTabsTab label="REPL">
<p>Use the three commands above for separate allocation, CPU and task profiles,
or start <code>repl.jl</code> in <code>.controller/core</code> and configure the
suite interactively. Keep the printed report path; reopen it to inspect the
existing profile without rerunning the workload.</p>
<p><a href="../interfaces/repl-pluto.html#REPL">REPL configuration and results</a></p>
</PluginTabsTab>
<PluginTabsTab label="Web (Oxygen)">
<p>Start the <a href="../interfaces/web-studio.html">Web controller</a>. Select
Bibliography, <code>export_bibtex</code> and the intended profile check. Inspect
the plan, launch, then open the completed run and its artifacts. The browser
displays the result; the controller or explicitly selected remote worker runs
the experiment.</p>
<DocMedia src="/examples/bibliography/web/selection.png"
alt="Recorded Oxygen Studio showing Bibliography workload and check selectors"
caption="Recorded benchmark selection in Web Studio. Choose the profile check for a profiling experiment, rather than interpreting this benchmark as a profile." />
</PluginTabsTab>
</PluginTabs>
```

These recorded selections illustrate each interface. Read the actual check
label and result status in your own run; they do not establish that a new profile
has been collected.

If the allocation site table is empty, read its allocation-profile status before
changing code. `zero_allocations`, `no_samples`, `outside_target_scope` and
`unattributed_samples` describe different evidence. The measured byte/count
totals are retained even when a location could not be sampled or attributed.
Repeat with a suitable sampling rate and inspect the selected source scope;
do not interpret missing stacks as zero cost. The [collector reference](../reference/checks.md#Profiles)
explains the fields and the difference between raw scenario weights and the
legacy allocation-stack estimates.

## Read a flame graph

- Width is the selected weight: CPU samples, task samples or allocation bytes.
- Depth is nesting. Horizontal position is not a timeline.
- A wide parent includes its descendants. Do not add parent and child percentages.
- Follow a wide branch into the relevant function, then inspect its source line and full call path.
- The same function can appear under different callers.

In the recorded CPU capture, `export_bibtex` accounts for about 98% of retained samples. Its `_write_bibtex` child is part of that share, not additional cost.

## Check the effect of a change

1. Pick a call path that accounts for a large share.
2. Change the code (for export, avoid intermediate strings).
3. Rerun the original benchmark with the same input and verify the output.
4. Repeat when the difference is small relative to sample variation.

Profiling adds overhead, so confirm the change with BenchmarkTools or Chairmarks, not with the profile timings.

## Other costs

- [Process memory](../process-memory.md) — retained RAM.
- [Network measurement](../network-measurement.md) — traffic and packets.
- [Native profiling](../native-profiling.md) — Julia runtime and external libraries.


```@raw html
<a id="Inspect-three-recorded-Bibliography-profiles"></a>
```

## Recorded examples

```@raw html
<MeasuredProfiles />
```

## Next

[Run checks in CI](../tutorials/ci.md).
