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

Expected lifecycle for this case: preparation returns `[3, 1, 2]`; the operation returns the same vector sorted as `[1, 2, 3]`; verification returns `true`. These are the example's correctness expectations, not recorded timings.

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

Expected catalogue: one scenario, `sort-values`, with two collector selections. Loading the declaration prepares no input and starts no measurement.

## Run, diagnose and advise

Run the CLI from a controller project containing PerfChecker (`] add PerfChecker` if needed). Prepare `perf/runner` with BenchmarkTools for this sorting case. Prepare `perf/diagnostics` with JET, Aqua, AllocCheck and SnoopCompile for the analyzers requested below; latency is built in.

```sh
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- run --catalog=perf/scenarios.toml --project=perf/runner --samples=20 --reports=reports/run
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- diagnose --catalog=perf/scenarios.toml --project=perf/diagnostics --tools=jet,aqua,alloccheck,snoopcompile,latency --timeout=120 --reports=reports/diagnosis
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- advise --source=reports/diagnosis/diagnosis.json --reports=reports/advice
```

Expected artifacts after successful local execution:

| Command | Result to inspect |
| --- | --- |
| `run` | Saved measurement reports and bundles under `reports/run` |
| `diagnose` | `reports/diagnosis/diagnosis.json`, with an execution status and findings per requested tool |
| `advise` | Advice reports under `reports/advice`; suggestions do not edit the package |

The sorting recipe is not a recorded campaign. Missing analyzers remain `unavailable`; no timing or finding is fabricated here.

- The controller environment holds PerfChecker.
- A measurement environment needs only the target, its dependencies and the chosen collector. Workers never import PerfChecker.
- A diagnostic environment adds the selected analyzers. A missing tool is `unavailable`; nothing is installed.
- `diagnose` runs one isolated process per analyzer and scenario, and Aqua once per package.

For a completed example, follow the [JET before/after investigation](jet.md#Follow-a-finding-through-a-change): inspect six recorded dispatch findings, the typed implementation with no findings, and the separate benchmark of the same calculation. The diagnostic explains the inferred types; the benchmark measures the cost.

```@raw html
<a id="Discover-without-executing"></a>
```


::: details Discovery and state policy

## Discovery

```sh
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- discover --root=/path/to/package --reports=reports/discovery
```

Discovery inspects `Test`/`TestItems` assertions and literal CI matrices. It does not evaluate code or expand macros. Test-derived cases are **proposals** with source locations; you adopt them by writing explicit declarations. Discovery never rewrites test code.

Expected output: discovery reports under `reports/discovery`, containing candidate declarations and their source locations. An empty candidate list means nothing was proposed, not that the package has no performance cost.

```@raw html
<a id="CI-and-comparisons"></a>
```

## Exit codes

Use the same catalog locally and in CI. `compare_scenarios` compares each
scenario, implementation and collector separately; missing configurations remain
`not_tested`. Keep workload and oracle source fixed when comparing a target-code
change. See [comparison configuration](../reference/comparisons.md).

- `discover`/`advise` return zero after writing a report.
- `run --catalog` fails on an empty catalog or unsuccessful execution.
- `diagnose` fails when requested checks are unavailable, fail to execute, or time out. Findings are reported separately from execution status.
- No inferred case creates a performance gate.

```@raw html
<a id="Editor,-web-and-notebook-workflows"></a>
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

:::

::: details External commands and custom collectors

## External commands and custom collectors

## External command provider

`ExternalCommandSpec` is the language-neutral escape hatch. PerfChecker launches
a bounded command that emits one `perfchecker-provider-result/1` JSON document.

This provider fragment assumes an existing Rust program at `/path/to/provider`
that implements PerfChecker's result contract. An arbitrary Cargo application
does not emit that contract automatically.

```julia
using PerfChecker
spec = ExternalCommandSpec(
    :rust_parser,
    "rust",
    ["cargo", "run", "--release", "--", "perfchecker-result.json"];
    directory = "/path/to/provider",
    timeout_seconds = 600,
)

bundle = run_external_command(spec; bundle_root = "perf/provider-runs")
println(bundle.manifest["schema_version"])
```

Expected output after a provider result is normalized:

```text
perfchecker-run-bundle/1
```

The provider result is validated and normalized into the common run-bundle
grammar. The schema alone does not establish success: inspect
`bundle_passed(bundle)`, its observations and diagnostics. Timeouts, nonzero
exits and a missing result file produce failed evidence; malformed results can
raise an error. This Rust fragment is a provider contract, not an executed Rust
benchmark. Declaring a command does not make a setup supported: a provider should
also publish a capability manifest, fixtures, conformance tests, version
provenance, and known measurement limits. New language/tool integrations are
therefore added one at a time and qualified on real workloads.

## Databases and services

For SQL or network services, record server version, configuration, schema/data
fingerprint, locality, connection/TLS setup, cache state, and client pool state.
Separate client latency from server execution and transport waiting. When
possible, launch the complete fixture inside an isolated network namespace so
packet and byte budgets cover the same process tree.

## Add a Julia backend

A backend implements the hook surface for its `Val{:backend}`:

- `initpkgs` loads required packages in the worker;
- `default_options` declares defaults;
- `prep` prepares fixtures;
- `check` performs measurement;
- `post` normalizes evidence;
- optionally `cleanup` and `stop_before_post` manage exit-flushed artifacts.

The backend must define versioned measurement definitions, units, preference,
scope, perturbation, capability checks, deterministic fixtures, and TestItems.
It should return data through the common bundle grammar before gaining UI or CI
claims.

## Add another programming setup

Use `ExternalCommandSpec` and `perfchecker-provider-result/1`. Qualify each
provider independently with a capability manifest and conformance suite. The
shared protocol is deliberately language-neutral, while measurement semantics
remain specific to the actual runtime and tools.

:::
