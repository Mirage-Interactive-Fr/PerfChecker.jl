# Shared scenarios, discovery and advice

Use this advanced workflow when you need to separate preparation, the measured
operation and correctness verification, or compare multiple implementations of
the same operation. Ordinary `@testitem` measurement is simpler when timing the
whole test is sufficient; see [your first result](guide/first-check.md).

The examples below define a contract file, a catalogue selecting its cases and
a prepared target environment. They are API examples to adapt to your package.
For a complete export benchmark with files already supplied, use the
[Bibliography walkthrough](tutorials/bibliography.md).

PerfChecker can reuse the same operation and correctness oracle as ordinary Julia
tests. The shared case is plain Julia; it does not import PerfChecker. Measurement
collectors and implementation variants are separate dimensions.

## Define a case once

A factory accepts a TOML-compatible parameter dictionary and returns a named tuple:

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

An ordinary test calls `prepare`, `operation`, and `verify`. Optional
`synchronize(state, result)` waits for asynchronous completion; optional
`cleanup(state)` releases resources. Synchronization is inside the measured
operation. Preparation, verification, and cleanup are outside it. Cleanup runs
after success, an oracle failure, or an operation/synchronization exception.
If preparation itself fails, the preparation function owns its partial cleanup.
A forcibly stopped process cannot execute Julia cleanup; do not use external
resources that require in-process cleanup without an external owner.

Each sample has a fresh state and exactly one evaluation. The oracle sees the
actual operation result. The factory and parameters are loaded in the worker,
not serialized as closures by the controller. Return type inference prepares a
typed result holder outside measurement; the wrapper and synchronization costs
are part of the operation protocol. BenchmarkTools' trial-level allocation
estimate is repeated alongside its timing samples, not independently measured
for each time sample. Chairmarks keeps its per-sample allocation values.

## Declare the catalog

Save the factory above as `test/cases.jl` and the following catalogue as
`perf/scenarios.toml`. All source/fixture paths and `root` are relative to
that file. Only explicitly declared scenarios are executable catalog members.

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

`prepare`, `operation`, and `verify` are required. A missing/false oracle is not a
qualified result. `repeatable` is recorded as a declaration but does not enable
state reuse in the shared-catalog runner: that runner always uses fresh states.
For deliberately repeated state, the existing `FeatureSpec` interface has the
explicit `state_policy=:reuse` protocol described below.

The complete example under `examples/shared-scenarios` contains two implementations
of sorting and one asynchronous case, plus ordinary tests using the same factories.

## Discover without executing

```sh
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- discover --root=/path/to/package --reports=reports/discovery
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- discover --root=/path/to/package --previous=reports/discovery/discovery.json
```

Discovery uses JuliaSyntax to inspect `Test`/`TestItems` assertions and reads
literal GitHub Actions matrices. It does not include files into Julia, expand
macros, resolve remote workflows, or evaluate CI expressions. Dynamic constructs
produce warnings. Test-derived cases remain proposals with source locations,
candidate operations/oracles and missing lifecycle information. Proposals are
adopted by writing explicit declarations; discovery never rewrites test code.

Literal file references and declared fixtures are fingerprinted. Re-running
against an earlier discovery report lists added, changed and removed inputs and
affected cases. Dynamic fixture paths cannot be inferred reliably and must be
declared. Discovery skips symlink directories and warns about catalog references
outside its root. Candidate IDs are file-relative test ordinals; explicit catalog
IDs are the durable identities and must be retained during refactoring.

## Run, diagnose and advise

These command examples assume you saved the factory/catalogue above and prepared
`perf/runner` and `perf/diagnostics` with the dependencies described below. Run
them from the package root with PerfChecker installed in the active controller
project. `RUN_ID` in the final command is a placeholder for a saved bundle ID;
inspect the report output before supplying it.

```sh
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- run --catalog=perf/scenarios.toml --project=perf/runner --samples=20 --reports=reports/run
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- diagnose --catalog=perf/scenarios.toml --project=perf/diagnostics --tools=jet,aqua,alloccheck,snoopcompile,latency --timeout=120 --reports=reports/diagnosis
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- advise --source=reports/diagnosis/diagnosis.json --reports=reports/advice
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- advise --bundle=reports/run/RUN_ID
```

The controller environment contains PerfChecker. A measurement environment needs
only the target package, workload dependencies and its chosen collector; workers
include a small standalone runtime and never import PerfChecker. A diagnostic
environment contains the target and selected analyzers. The diagnostic worker
loads a small standalone runtime and its tool adapter without importing PerfChecker. No command
installs packages. Dependencies are prepared explicitly before execution.

`diagnose` runs one isolated process per analyzer and scenario, and Aqua once per
package. It records analyzer/runtime versions, environment fingerprints and
separate availability, correctness, quality and performance fields. Missing or
incompatible tools are unavailable. Timeout and cancellation stop the worker.
The Julia API accepts a `CancellationToken`; call `cancel!` from another task.

JET and AllocCheck analyze the operation specialized for the prepared state type;
they do not prove correctness or inspect every possible input. SnoopCompile
records first-lifecycle inference. The latency probe measures source loading,
first full lifecycle, and one warm lifecycle; its results are exploratory and
include preparation/verification. They must not be compared to operation-only
timings. Aqua uses the recorded version's default checks unless explicit boolean
overrides are supplied with `diagnose(...; options=Dict("aqua"=>...))`.

`advise` only consumes saved evidence. Recommendations cite their observations,
preserve alternative explanations, propose a next experiment, and provide
post-correction checks. They never predict an unmeasured gain. No recommendation
is not evidence that code is optimal. `agent_evidence` exposes bounded advice for
both bundles and diagnosis reports.

## CI and comparisons

Use the same catalog locally and in CI. `compare_scenarios` compares each
scenario/implementation/collector independently and preserves missing
configurations as `not_tested`. Source and fixture changes invalidate the
measurement-definition identity conservatively. To compare a target-code change,
keep the shared workload/oracle source fixed and change the package implementation.
Runtime, dependency, platform and hardware evidence accompany each bundle.

Discovery/advise return zero after successful report generation. `run --catalog`
returns nonzero for an empty catalog or unsuccessful execution. `diagnose`
returns nonzero when requested checks are unavailable, fail to execute, or time
out; diagnostic findings are reported separately from this execution status.
No inferred case creates a performance gate. Adopt baseline and budget policies
explicitly using the existing comparison APIs/CLI.

The collection qualification workflow covers Windows and Linux and records
artifacts. No macOS execution qualification is claimed. The
[optional model advisor](advisors.md) and [tool catalogue](tool-catalog.md) extend
this workflow. `examples/backend-scenarios` shares an oracle across CPU, threads
and CUDA and includes a distributed case; unavailable hardware remains explicit.
Specialized GPU/NPU profilers remain separately identified integration candidates.

## Migration of FeatureSpec suites

For BenchmarkTools, Chairmarks, CPU/wall profiles and allocation profiles,
`FeatureSpec` now defaults to `state_policy=:fresh`. Each operation gets a new
`perf_setup()` state. Define `perf_synchronize(state, result)` and
`perf_cleanup(state)` when required. Prefer `perf_oracle(state, result)` so the
oracle verifies the actual measured result. State-only and zero-argument legacy
oracles remain accepted, with their narrower interpretation.

Use `state_policy=:reuse` explicitly when repeated mutation is the intended
workload. Fresh timing cases require `evals=1`. Existing raw `@check` blocks keep
their explicit preparation/workload semantics. Legacy line-allocation and network
collectors retain their specialized protocols.

Fresh-state bundles carry a new measurement-definition suffix; they cannot be
silently compared to old measurements made by reusing state. Existing bundles
remain readable. Profile measurements may differ after this correction because
each operation now sees the intended input.

## Editor, web and notebook workflows

VS Code is the primary interactive client. The companion PerfCheckerVSCode
extension exposes a scenario sidebar, Testing items, Julia CodeLens, an
investigation panel, source-linked Problems and evidence actions. Discovery,
explicit adoption, selected measurements, analyzers, saved advice and before/after
comparison all use the public CLI. Configure its `runnerProject` and
`scenarioProject` to prepared environments; it never installs dependencies.
Existing suite editors and bundle readers remain available.

PerfCheckerWeb also accepts a catalog:

```julia
using PerfChecker, PerfCheckerWeb, Oxygen
catalog = load_scenario_catalog("perf/scenarios.toml")
serve_suite(catalog; project="perf", port=8080)
# Open http://127.0.0.1:8080/perfchecker/scenarios/
```

This local studio offers explicit discovery/measurement/diagnosis, selection by
implementation, tool availability, cancellation, saved evidence, JSON/Markdown,
deterministic advice and before/after comparison. It binds to loopback. Provide
`catalog_path="perf/scenarios.toml"` to reload manual declarations. The existing
bundle studio exposes saved advice alongside its plots.

For Pluto, add PlutoUI to the controller environment and generate a notebook:

```julia
using PerfChecker, PerfCheckerPluto
write_investigation_notebook("investigate.jl";
    root=pwd(), project="perf", catalog="perf/scenarios.toml")
```

Opening the notebook does not execute target callbacks. Choose declared scenarios,
tools and limits, then click Launch. Cancel and Refresh operate on the same
asynchronous job. `investigation_view(report)` renders saved evidence in Pluto,
HTML or the REPL, and the notebook can compare saved bundle folders.

All UI clients use `select_scenarios`, `launch_investigation`,
`investigation_status`, `wait_investigation`, `cancel!`, and
`write_investigation_report`. A completed job means its requested work finished;
individual unavailable or invalid analyzer results remain distinct.

CLI selection accepts `--selection=selection.json`, containing an array of
`{"id":"case-id","implementation":"cpu"}` records. Compare stored groups with
`compare --scenarios --baseline=before/bundles --candidate=after/bundles`.
`advise --source=after/bundles` consumes stored measurements without target execution.

## API reference

### Legacy worker environment copies

Legacy `PerfConfig` workers copy their environment directory. Keep that directory
small, or explicitly exclude generated top-level entries:

```julia
config = PerfConfig(:benchmark; path=pwd(), environment_excludes=[".lab"])
```

The default still copies all entries. Exclusions are literal top-level names,
not glob patterns; Project, Manifest and preference files cannot be excluded.
Required fixtures must remain included. This option applies to legacy worker
copies; shared-scenario workers already use the selected prepared environment
directly. The exclusion list is retained in the configuration identity.

### Memory and contention diagnostics

`diagnostic_capabilities()` provides the analyzer list used by the CLI, VS Code,
Oxygen and generated Pluto controls. Installation metadata describes the
controller; each launched worker checks its own selected environment.

```julia
report = diagnose(catalog; project="perf", tools=[:gc, :memory, :locks, :heap],
    reports="perf/results/diagnosis", options=Dict("diagnostic_samples" => 5))
```

`gc` records collection time and allocation counters around operation plus
synchronization. `locks` reports observed Julia lock conflicts when supported by
the runtime. `memory` records reachable state/result sizes and process memory
observations. Growth can reflect intended output or a cache; it does not prove a
leak. Process observations are not peaks. `heap` captures a redacted snapshot
after verification, requires a report directory and reports unavailable when the
runtime cannot redact snapshots. It covers GC-managed memory of the whole worker,
not native/device memory. These intrusive diagnostics remain separate from timing
baselines. The deterministic advisor proposes verification experiments for GC
pressure, retained-state growth and observed lock contention without promising a
speedup.

Worker provenance includes fingerprints of development dependencies' Project,
preferences, `src`, `ext` and `deps` files. An observed change during execution
invalidates the run. Skipped links and capture limits remain explicitly incomplete;
additional data files must be declared as fixtures. This detects local source edits
even when the Manifest itself did not change.

See the [Julia API index](reference/api.md) for the scenario, discovery,
measurement, diagnosis, advice, cancellation and comparison functions.
