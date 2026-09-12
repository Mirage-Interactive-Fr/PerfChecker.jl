# Extensions and providers

PerfChecker separates interface packages, small API extensions and diagnostic worker
providers. See [interface packages](../interfaces/packages.md) for installation.

| Extension | Activated by | Capability |
| --- | --- | --- |
| BenchmarkToolsExt | BenchmarkTools | `:benchmark` collector |
| ChairmarksExt | Chairmarks | `:chairmark` collector |
| DrWatsonExt | DrWatson | parameter naming, cached production, suite runs |
| DocumenterExt | Documenter | generated performance pages and docs builds |
| DocumenterVitepressExt | Documenter + DocumenterVitepress | VitePress-aware docs build |
| UnicodePlotsExt | UnicodePlots | terminal plots |
| PProfExt | FlameGraphs + PProf | pprof/folded/speedscope profile artifacts |
| PropCheckExt | PropCheck | reproducible property corpus freezing |
| SuppositionExt | Supposition | reproducible property corpus freezing |
| TestItemRunnerExt | TestItemRunner >= 1.3.2 | native item discovery and whole-item measurement |
| HTTPAdvisorExt | HTTP | optional advisor transport |

Add optional packages to the **controller** environment that needs them. A
renderer does not become a measured-worker dependency. Collector packages are
loaded in the target worker only when that backend requires them.

## Version compatibility

Interface and analyzer compatibility belongs to the component that uses the
package. The core no longer declares Oxygen, Pluto, Makie, WGLMakie, Bonito,
JET, AllocCheck or SnoopCompile as optional dependencies. Aqua remains a core
quality-test dependency, not a diagnostic extension.

`PerfCheckerMakie` owns the optional WGLMakie/Bonito rendering extension. Tool
adapters and their Project.toml files live under `providers/`. Their availability
is checked in the diagnostic worker, without importing the controller there.

The following upstream releases were inspected on 12 September 2026. These are
compatibility facts, not a claim that all combinations passed collection tests.
The publication inventory records actual versions for each qualified environment.

| Stack | Current releases | Constraint |
| --- | --- | --- |
| Web and interactive plots | Oxygen 1.11.0, HTTP 2.6.7, Bonito 5.2.0, Makie 0.24.14, WGLMakie 0.13.14 | Julia >= 1.11; no Pluto 1.0.3 in this environment |
| Notebook | Pluto 1.0.3 | HTTP 1; use a separate environment from the latest web stack |
| Julia 1.10 web | Oxygen 1.10.2, HTTP 1.11.0 | Compatible fallback for the minimum Julia version |
| Inference analysis | JET 0.12.1 | Julia >= 1.12; older JET lines remain admitted |

The HTTP.jl 2 migration is already in the tagged
[Oxygen 1.11.0 release](https://github.com/OxygenFramework/Oxygen.jl/releases/tag/v1.11.0),
published 28 August 2026. The checked master revision is identical to that tag.
Its [Project.toml](https://github.com/OxygenFramework/Oxygen.jl/blob/v1.11.0/Project.toml)
requires HTTP >= 2.4 and Julia >= 1.11. There is no pending master-only correction
to adopt. [Pluto's HTTP 1 constraint](https://github.com/fonsp/Pluto.jl/blob/v1.0.3/Project.toml)
still prevents combining the latest notebook and web stacks.

HTTP.jl package versions 1 and 2 are dependency generations; they are distinct
from the HTTP/1.1 and HTTP/2 wire protocols. PerfChecker tests its two dependency
stacks separately. A resolved environment proves dependency compatibility;
execution, rendering and correctness checks provide the integration evidence.

## DrWatson

This example uses the `plan` built in the [software-suite tutorial](../software-suites.md).
Add DrWatson to that controller environment before loading the extension.

```julia
using PerfChecker, DrWatson

params = drwatson_parameters(plan)
name = drwatson_savename(params)
result = drwatson_produce_or_load(plan, "perf/results")
```

`drwatson_run_suite` combines structured experiment parameters, resumable output,
and the normal PerfChecker runner. Cache reuse remains explicit in run evidence.

## Property-based workloads

PropCheck and Supposition adapters freeze minimized/counterexample inputs into a
portable corpus. This makes a stochastic discovery reproducible before it
becomes a performance fixture. Corpus generation is not mixed into benchmark
sampling; measure the frozen examples in a separate deterministic run.

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
