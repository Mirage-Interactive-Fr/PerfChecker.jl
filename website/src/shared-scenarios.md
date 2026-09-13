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
- `cleanup(state)` releases resources; it runs after success, oracle failure or an exception.
- Each sample gets fresh state and exactly one evaluation.
- The oracle sees the actual operation result. A missing or false oracle is not a qualified result.

The factory does not import PerfChecker; the worker loads it.

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

## Discovery

```sh
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- discover --root=/path/to/package --reports=reports/discovery
```

Discovery inspects `Test`/`TestItems` assertions and literal CI matrices. It does not evaluate code or expand macros. Test-derived cases are **proposals** with source locations; you adopt them by writing explicit declarations. Discovery never rewrites test code.

## Exit codes

- `discover`/`advise` return zero after writing a report.
- `run --catalog` fails on an empty catalog or unsuccessful execution.
- `diagnose` fails when requested checks are unavailable, fail to execute, or time out. Findings are reported separately from execution status.
- No inferred case creates a performance gate.

## Interfaces

```julia
using PerfChecker, PerfCheckerWeb, Oxygen
catalog = load_scenario_catalog("perf/scenarios.toml")
serve_suite(catalog; project = "perf", port = 8080)
```

VS Code, the scenario studio, Pluto and the CLI all use `select_scenarios`, `launch_investigation`, `investigation_status`, `cancel!` and `write_investigation_report`.

## State policy

`FeatureSpec` defaults to `state_policy = :fresh`. Use `:reuse` only when repeated mutation on one state is the workload you intend. Fresh timing cases require `evals = 1`. Profile measurements may differ after this correction: each operation now sees the intended input.

```@raw html
<a id="Shared-scenarios,-discovery-and-advice"></a>
<a id="Declare-the-catalog"></a>
<a id="Discover-without-executing"></a>
<a id="CI-and-comparisons"></a>
<a id="Migration-of-FeatureSpec-suites"></a>
<a id="Editor,-web-and-notebook-workflows"></a>
<a id="Open-http://127.0.0.1:8080/perfchecker/scenarios/"></a>
<a id="API-reference"></a>
<a id="Legacy-worker-environment-copies"></a>
<a id="Memory-and-contention-diagnostics"></a>
```
