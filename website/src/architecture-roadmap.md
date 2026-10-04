# Architecture

PerfChecker separates the controller, the measured programs and presentation. The same test definitions work from VS Code, a script or a web controller; results cross those boundaries as versioned data with measurement definitions and provenance attached.

## Packages and ownership

- `PerfChecker` — discovery, plans, workers, measurements, comparisons, CLI, REPL, reports. No required web, notebook or plotting framework.
- `PerfCheckerWeb` — Oxygen routes, studio assets, auth, jobs. Depends on the web stack.
- `PerfCheckerPluto` — notebook generation, controls, Pluto launch. Depends on Pluto and PlutoUI.
- `PerfCheckerMakie` — figures and dashboards. Depends on Makie; WGLMakie is an optional renderer.
- **VS Code client** — testing view, commands, source navigation. Separate TypeScript project that calls the Julia controller.
- `PerfCheckerQualification` — impact planning, contracts, matrix receipts. Independent stdlib-only package.
- `website/` — this documentation. Its own Documenter/Vitepress environment.

The Julia satellites live in `packages/` in the same repository, so a shared-contract change and its consumers can be reviewed together. Each satellite has its own project, compat bounds and tests. Installation requires the explicit satellite package; loading Oxygen or Makie alone no longer activates an interface.

PerfChecker does not need a global active backend. A notebook, a web job and a VS Code item have their own controller state and may stay open together.

## Extensions that stay useful

Small interoperability methods stay in Julia extensions: BenchmarkTools and Chairmarks measurements, the TestItemRunner bridge, UnicodePlots rendering and Documenter report blocks. They adapt an existing API without owning an application or a large dependency tree.

- An interface with assets, server lifecycle or notebook generation belongs in a satellite.
- A diagnostic tool that must inspect the target environment belongs in a worker adapter.
- Adding a new dependency should begin with this ownership choice, not another entry in the engine's weak-dependency list.

## Diagnostic workers

JET, AllocCheck, SnoopCompile and Aqua adapters live under `providers/`, each declaring its tool compatibility separately.

- The worker loads the requested tool in its prepared environment.
- It does not import PerfChecker.
- An unavailable tool returns explicit diagnostic evidence. It does not fail the controller import.
- Provider source participates in development-source fingerprints, so editing an adapter changes the recorded source identity.

## One collection, several environments

A collection is a set of compatible, tested component versions — not one Manifest containing every optional interface. An Oxygen controller using HTTP 2 and a Pluto controller using HTTP 1 can exchange saved bundles while keeping separate environments.

- The qualification runner resolves and saves each lane's actual environment.
- Core and shared-contract changes select all consumers; a web-only change selects web tests and its dependent documentation.
- The full matrix also checks historical multi-interface integration in a separate environment.

The [qualification contract](reference/qualification.md) requires the same candidate revisions, campaign ID, successful lanes and unmodified artifacts before publication. A targeted PR result cannot promote a complete collection.

<a id="Register-packages-from-the-shared-repository"></a>

## Registering from the shared repository

General supports a package in a repository subdirectory. Its registry entry records the repository and the package's `subdir`; users still install it by name.

- `packages/PerfCheckerWeb` is a package source root with its own `Project.toml` and `src/`.
- It is not a nested module loaded through the parent's directory.
- Its dependency on PerfChecker is declared by UUID and resolved by Pkg.

The local `[sources.PerfChecker]` path is a development convenience when an interface project is active; Pkg does not propagate it when the interface is installed as a dependency.

Registration is separate per package, for example `@JuliaRegistrator register subdir=packages/PerfCheckerWeb` on a published release commit. The engine version required by an interface's compat bounds must also be registered.

## Test items and performance evidence

- The TestItemRunner bridge discovers existing declarations and can run one item in a fresh process.
- Untagged items are shared. `:perf_only` and `:test_only` separate the two modes.
- Functional success, a completed measurement and a passing regression budget are three separate results.
- Ordinary test-item timing includes setup and assertions; feature workloads give a narrower measurement region.

Saved bundles retain the metric definition, runtime, source identity, environment and qualification outcome needed to judge comparability.

## Platform limits

- Windows and Linux are recorded separately.
- macOS is not currently qualified.
- The cross-machine estimator is an experimental planning aid; predictions never replace measurements or qualify a blocking CI decision.

```@raw html
<a id="Extensions-that-remain-useful"></a>
<a id="Platform-and-prediction-limits"></a>
<a id="Temporary-previews-before-registration"></a>
```
