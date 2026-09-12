# Architecture

PerfChecker separates the controller, measured programs and presentation. A user
can keep the same test definitions while switching from VS Code to a script or a
web controller. Results cross these boundaries as versioned data, with their
measurement definitions and provenance attached.

## Packages and ownership

| Owner | Responsibilities | Dependency boundary |
| --- | --- | --- |
| `PerfChecker` | Discovery, plans, workers, measurements, comparisons, CLI, text REPL, portable reports | No required web, notebook or plotting framework |
| `PerfCheckerWeb` | Oxygen routes, Studio assets, authentication and jobs | Strong dependencies on PerfChecker and the web stack |
| `PerfCheckerPluto` | Notebook generation, controls and Pluto launch | Strong dependencies on PerfChecker, Pluto and PlutoUI |
| `PerfCheckerMakie` | Figures and dashboards | Strong dependency on Makie; WGLMakie is an optional renderer extension |
| VS Code client | Testing view, commands, source navigation and investigation panels | Separate TypeScript project; calls the Julia controller |
| `PerfCheckerQualification` | Impact planning, shared contracts, matrix receipts and publication checks | Independent stdlib-only package |
| `website/` | This documentation | Its own Documenter and DocumenterVitepress environment |

The Julia satellites live in `packages/` in the same repository. A change to a
shared contract and its consumers can therefore be reviewed together. Each
satellite has its own project, compatibility constraints and tests. Installation
requires the explicit satellite package; loading Oxygen or Makie alone no longer
activates a PerfChecker interface. See [installation and migration](interfaces/packages.md).

This follows the useful part of Makie's organization: a common engine, explicit
backend packages and common qualification. PerfChecker does not need a global
active backend. A notebook, a web job and a VS Code item have their own explicit
controller state and may remain open together.

## Extensions that remain useful

Small interoperability methods stay in Julia extensions. Examples include
BenchmarkTools and Chairmarks measurements, the TestItemRunner bridge,
UnicodePlots rendering and Documenter report blocks. They adapt an existing API
without owning an application or a large dependency tree.

An interface with assets, server lifecycle or notebook generation belongs in a
satellite. A diagnostic tool that must inspect the target environment belongs in
a worker adapter. Adding a new dependency should begin with this ownership choice,
not with another entry in the engine's weak dependency list.

## Diagnostic workers

JET, AllocCheck, SnoopCompile and Aqua adapters live under `providers/`, each with
its tool compatibility declared separately. The diagnostic worker loads the
requested tool in its prepared environment. It does not import PerfChecker.
Unavailable tools return explicit diagnostic evidence rather than making the
controller import fail. The provider source participates in development-source
fingerprints, so edits to an adapter change the recorded source identity.

Native commands follow a separate capability contract. A prepared Valgrind or
system-profiler command is not evidence that the tool ran successfully. See the
[profiling review](native-profiling.md) for platform support and execution limits.

## One collection, several environments

A collection is a set of compatible, tested component versions. It is not one
Manifest containing every optional interface. For example, an Oxygen controller
using HTTP 2 and a Pluto controller using HTTP 1 can exchange saved run bundles
while keeping separate Julia environments. Extracting a package does not by
itself make conflicting dependencies resolvable in one project.

The qualification runner resolves and saves each lane's actual environment.
Core and shared-contract changes select all consumers. A web-only change selects
web tests and its dependent documentation. The full matrix also checks historical
multi-interface integration in a separate environment, where the resolver may
choose older mutually compatible interface dependencies.

The complete [qualification contract](reference/qualification.md) requires the
same candidate revisions, campaign identifier, successful lanes and unmodified
artifacts before publication. A targeted PR result cannot promote a complete
collection. Documentation is built once; deployment checks the hash of that
artifact instead of rebuilding against a different dependency resolution.

## Test items and performance evidence

The TestItemRunner bridge discovers existing declarations and can run one item
in a fresh process. Untagged items are shared. `:perf_only` and `:test_only` allow
separation; the functional runner currently needs an explicit filter. Loading
PerfChecker does not replace upstream methods or silently alter another package's
runner policy. Use the documented filter when running functional tests.

Functional success, completed measurement and a passing regression budget are
separate results. Ordinary test-item timing includes setup and assertions.
Feature workloads provide a narrower measurement region when needed. Saved
bundles retain the metric definition, runtime, source identity, environment and
qualification outcome required to judge comparability.

## Platform and prediction limits

Windows and Linux are recorded separately. macOS is not currently qualified.
The cross-machine estimator is an experimental planning aid: predictions do not
replace actual measurements or qualify a blocking CI decision. A short calibration
battery still needs independent validation on real machines before stronger
claims are justified.

## Register packages from the shared repository


General supports a package in a repository subdirectory. Its registry entry
records the repository and the package's `subdir`; users still install it by
name. [GLMakie's General entry](https://github.com/JuliaRegistries/General/blob/master/G/GLMakie/Package.toml)
already uses this arrangement with the Makie repository.

`packages/PerfCheckerWeb` is therefore a package source root with its own
`Project.toml` and `src/PerfCheckerWeb.jl`. It is not a nested Julia module
loaded through the parent's directory. Its dependency on PerfChecker is declared
by UUID and resolved by Pkg.

The local `[sources.PerfChecker]` path is a development convenience when an
interface project itself is active. Pkg does not propagate that section when
the interface is installed as a dependency in a user's environment.
See [Pkg's sources documentation](https://pkgdocs.julialang.org/v1/toml-files/#The-[sources]-section).

Registration is performed separately for each package, for example with
`@JuliaRegistrator register subdir=packages/PerfCheckerWeb` on a published
release commit. Registrator explicitly supports
[subdirectory packages](https://github.com/JuliaRegistries/Registrator.jl#registering-a-package-in-a-subdirectory).
The engine version required by an interface's compatibility bounds must also
be registered. The current interfaces require PerfChecker 1.x.

## Temporary previews before registration

A published Git revision can supply an unregistered interface without a local
checkout. For example, after a maintainer publishes the V1 preview commit:

```julia
import Pkg
preview_repo = "https://github.com/JuliaConstraints/PerfChecker.jl.git"
preview_rev = "<published V1 commit SHA>"
Pkg.add([
    Pkg.PackageSpec(url=preview_repo, rev=preview_rev),
    Pkg.PackageSpec(url=preview_repo, rev=preview_rev,
        subdir="packages/PerfCheckerWeb"),
])
```

Replace the placeholder with an actual published commit containing both packages.
The current working candidate has not been published at that URL; this is not
an executable installation recipe for it yet. This URL/subdirectory form is
only needed before registration. See [Pkg's subdirectory support](https://pkgdocs.julialang.org/v1/managing-packages/#Adding-a-package-in-a-subdirectory-of-a-repository).
