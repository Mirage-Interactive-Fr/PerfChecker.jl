# Tool catalogue

Use this catalogue to find a tool for a question, then check whether its
integration and platform support match your experiment. The Julia call below
returns the inventory without running tools or installing them.

The authoritative inventory is `data/tool-catalog.json`. Its entries distinguish
implemented collectors, existing extensions, scenario integrations and candidate
or external tools. A listing does not establish availability on your machine or
qualification of its results.

Start with [Understand performance measurements](guide/understanding-measurements.md)
for timing, GC, allocations and flame graphs. The [check catalog](reference/checks.md)
explains each implemented collector before its options; the native review below
explains the complementary tools and their measurement units.

```julia
using PerfChecker
catalog = tool_catalog()
for tool in catalog["tools"]
    tool["id"] in ("benchmark", "jet", "packagecompiler", "heaptrack") || continue
    println(tool["id"], " | ", tool["integration"], " | ", tool["qualification"])
end
```

Excerpt from the versioned inventory:

```text
benchmark | implemented | not_checked
jet | implemented | not_checked
packagecompiler | candidate | not_checked
heaptrack | external | not_checked
```

`implemented` describes an adapter; `not_checked` is deliberately not a local
availability verdict. The separate `catalog["analyzers"]` field reports analyzer
capabilities for the active controller.

```sh
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- tools --category=measurement
```

Relevant JSON fields in the CLI output (other fields omitted):

```json
{
  "schema_version": "perfchecker-tool-catalog/1",
  "authority": "inventory_not_qualification",
  "tools": [
    {"id": "benchmark", "integration": "implemented", "qualification": "not_checked"},
    {"id": "chairmark", "integration": "implemented", "qualification": "not_checked"}
  ]
}
```

VS Code and Oxygen consume this same inventory. For an assessment of Julia
profilers, native dependencies, Valgrind, hardware counters and platform limits,
read the [Julia and native profiling review](native-profiling.md).

## Reuse the workload

Measure [existing test items](test-items.md) directly when whole-item timing is
appropriate. Use [shared scenarios](shared-scenarios.md) for explicit preparation,
operation, correctness, synchronization and cleanup boundaries.

`scenario_sync(root)` relates declared scenarios to literal CI matrix entries.
These are proposed combinations, not proof that a job executes the scenario.
Dynamic expressions and external reusable workflows remain unresolved. Input
fingerprints expose drift without rewriting manually adapted scenarios.

```julia
sync = scenario_sync(pwd())
println(sync["authority"])
println("Adoption required: ", sync["adoption_required"])
```

Expected output:

```text
proposal_only
Adoption required: true
```

Review `sync["coverage"]` before adopting a combination; its rows are labelled
`qualification = "not_tested"`, even when a workflow mentions that platform.

`write_scenario_workflow(path; catalog="perf/scenarios.toml", project="perf",
implementations=["cpu"])` writes a new workflow and refuses to overwrite a file.
Its generated matrix includes Windows, Linux and macOS; generation does not
qualify those platforms. The gate checks correctness and availability, not a
performance threshold. The controller must contain the selected collectors.

```julia
path = write_scenario_workflow(".github/workflows/performance-scenarios.yml";
    catalog = "perf/scenarios.toml", project = "perf", implementations = ["cpu"])
println(isfile(path))
```

Expected output when that path did not already exist:

```text
true
```

This means the workflow file was written, not that its jobs passed. Existing
files are refused so manually adapted CI is preserved.

Static warnings and short samples may suggest irrelevant fixes. Keep diagnosis
separate from timing, retain unavailable configurations and validate proposed
changes against correctness oracles and unchanged measurement boundaries.
