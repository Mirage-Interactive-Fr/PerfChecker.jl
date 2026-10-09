# Public API

These entries are generated from the docstrings of PerfChecker's exported Julia
bindings. The [Full API](api.md) is the canonical reference and also includes
documented internal hooks. Julia's help mode uses these same source docstrings:
type `?run_scenarios` or `?AdvisorConfig` after loading `PerfChecker`.

Use a workflow guide when setting up your first experiment:

| Task | Entry points | Guide |
| --- | --- | --- |
| Measure an existing test | `discover_testitems`, `run_testitems` | [First check](../guide/first-check.md) |
| Define and compare workloads | `FeatureSpec`, `PackageSuite`, `SoftwareSuite`, `plan_suite`, `run_suite` | [Software suites](../software-suites.md) |
| Share a correctness protocol across collectors | `ScenarioSpec`, `run_scenarios`, `diagnose`, `compare_scenarios` | [Shared scenarios](../shared-scenarios.md) |
| Read portable evidence | `read_run_bundle`, `verify_run_bundle`, `query_bundle` | [Run bundles](run-bundles.md) |
| Discuss evidence and review an implementation | `AdvisorConfig`, `chat_advice`, `implement_advice` | [MCP guide](../mcp-advisor.md) |
| Use a notebook, web view or custom figure | Interface-package entry points | [Interface ownership](api.md#Interface-packages) |
| Select suite runs in a terminal UI | `PerfCheckerTachikoma.tui_model`, `tui`, `refresh!`, `close!` | [Optional package APIs](api.md#Tachikoma-terminal-API) |
| Collect optional hardware counters | Companion-owned `measure_counters`, `counter_executor`, `run_counter_suite` | [Counter APIs](api.md#Hardware-counter-APIs) |

Optional interface methods require their documented package to be installed and
loaded. An exported generic function can exist before its optional methods are
available. Loading an interface and constructing a configuration are separate
from starting a measurement.

The generated entries below cover **Core exports only**. The six
[companion Public and Full APIs](optional-api.md) render their actual Julia
docstrings in isolated projects and share this site's navigation and search.
Companion bindings and methods retain their owning modules and pinned source
links; they are not silently imported into the Core documentation environment.
The [ownership index and Julia help examples](api.md#Interface-packages) explain
how to load the selected owner.

## Exported docstrings

```@autodocs; canonical=false
Modules = [PerfChecker]
Public = true
Private = false
Order = [:module, :constant, :type, :macro, :function]
```
