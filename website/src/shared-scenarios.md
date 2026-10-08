```@raw html
<a id="Shared-scenarios,-discovery-and-advice"></a>
```

# Shared scenarios

Use this when preparation, the measured operation and correctness verification must be separate steps, or when comparing several implementations of the same operation. The same contract can serve both ordinary tests and a benchmark.

`@testitem` measurement is simpler when timing the whole test is enough.

## Define a case once

A factory takes a TOML-compatible parameter dictionary and returns a named tuple:

```julia
module Cases
function sorting(parameters)
    input = [3, 1, 2]
    return (
        prepare = () -> copy(input),
        operation = sort!,
        verify = (state, result) -> result === state && result == [1, 2, 3],
    )
end
end
```

- `prepare`, `operation`, `verify` are required.
- `synchronize(state, result)` waits for async completion, **inside** the measurement.
- `cleanup(state)` releases resources when Julia unwinds the operation normally, including success, oracle failure or an exception. Cancelling an isolated scenario stops its worker process; forced termination cannot run arbitrary user cleanup callbacks. Keep externally owned temporary resources recoverable independently.
- Each sample gets fresh state and exactly one evaluation.
- The oracle sees the actual operation result. A missing or false oracle is not a qualified result.

The factory does not import PerfChecker; the worker loads it.

```@raw html
<a id="Declare-the-catalog"></a>
```

## Declare a catalog

Save the factory as `test/cases.jl` and this catalog as `perf/scenarios.toml`. Paths are relative to the catalog.

```toml
schema_version = "perfchecker-scenario-catalog/1"
root = ".."

[[scenarios]]
id = "sort-values"
source = "../test/cases.jl"
factory = "Cases.sorting"
implementation = "cpu"
collectors = ["benchmark", "profile_alloc"]
```

## Run, diagnose and advise

```sh
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- run --catalog=perf/scenarios.toml --project=perf/runner --samples=20 --reports=reports/run
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- diagnose --catalog=perf/scenarios.toml --project=perf/diagnostics --tools=jet,aqua,alloccheck,snoopcompile,latency --timeout=120 --reports=reports/diagnosis
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- advise --source=reports/diagnosis/diagnosis.json --reports=reports/advice
```

- The controller environment holds PerfChecker.
- A measurement environment needs only the target, its dependencies and the chosen collector. Workers never import PerfChecker.
- A diagnostic environment adds the selected analyzers. A missing tool is `unavailable`; nothing is installed.
- `diagnose` runs one isolated process per analyzer and scenario, and Aqua once per package.

```@raw html
<a id="Discover-without-executing"></a>
```

## Discovery

```sh
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- discover --root=/path/to/package --reports=reports/discovery
```

Discovery inspects `Test`/`TestItems` assertions and literal CI matrices. It does not evaluate code or expand macros. Test-derived cases are **proposals** with source locations; you adopt them by writing explicit declarations. Discovery never rewrites test code.

```@raw html
<a id="CI-and-comparisons"></a>
```

## Exit codes

Use the same catalog locally and in CI. `compare_scenarios` compares each
scenario, implementation and collector separately; missing configurations remain
`not_tested`. Keep workload and oracle source fixed when comparing a target-code
change. See [comparison configuration](reference/comparisons.md).

- `discover`/`advise` return zero after writing a report.
- `run --catalog` fails on an empty catalog or unsuccessful execution.
- `diagnose` fails when requested checks are unavailable, fail to execute, or time out. Findings are reported separately from execution status.
- No inferred case creates a performance gate.

```@raw html
<a id="Editor,-web-and-notebook-workflows"></a>
```

## Interfaces

```julia
using PerfChecker, PerfCheckerWeb, Oxygen
catalog = load_scenario_catalog("perf/scenarios.toml")
serve_suite(catalog; project = "perf", port = 8080)
```

```@raw html
<a id="Open-http://127.0.0.1:8080/perfchecker/scenarios/"></a>
```

After `serve_suite` starts, open `http://127.0.0.1:8080/perfchecker/scenarios/`
on the same machine. This local address is available only while that Julia
server is running.

VS Code, the scenario studio, Pluto and the CLI all use `select_scenarios`, `launch_investigation`, `investigation_status`, `cancel!` and `write_investigation_report`.

```@raw html
<a id="API-reference"></a>
```

See the [public API](reference/public-api.md) for their contracts.

```@raw html
<a id="Memory-and-contention-diagnostics"></a>
```

## Additional diagnostics

`diagnose(catalog; project = "perf", tools = [:gc, :memory, :locks, :heap],
reports = "perf/results/diagnosis")` collects GC, reachable-memory, lock and heap
evidence in the selected diagnostic environment. These intrusive diagnostics
remain separate from operation timing. Memory growth can reflect intended output
or a cache; it does not prove a leak. See [process memory](process-memory.md) for
the distinction between Julia-managed and external memory.

```@raw html
<a id="Legacy-worker-environment-copies"></a>
```

## Legacy worker copies

Legacy `PerfConfig` workers copy their environment directory. Keep it small or
set `environment_excludes = [".lab"]` to omit explicitly named top-level entries.
Required fixtures, Project, Manifest and preference files must remain included.
Shared-scenario workers use their selected prepared environment directly.

```@raw html
<a id="Migration-of-FeatureSpec-suites"></a>
```

## State policy

`FeatureSpec` defaults to `state_policy = :fresh`. Use `:reuse` only when repeated mutation on one state is the workload you intend. Fresh timing cases require `evals = 1`. Profile measurements may differ after this correction: each operation now sees the intended input.
