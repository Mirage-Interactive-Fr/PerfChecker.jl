# Optional API rendering prototype

This builder renders real Julia docstrings through Documenter 1.19.0 and
DocumenterVitepress 0.3.5. It does not copy docstrings into another module, measure
hardware counters, start a frontend, install native libraries or publish a site.
It is not yet integrated into `website/make.jl` or the Documentation workflow.

LinuxPerf and LIKWID must use **separate projects and private writable depots**.
The current pinned backends require PrettyTables 2 and 3 respectively. Use Julia
1.10 or newer. Develop this exact checkout's Core and selected companion explicitly
in each project; Julia 1.10 must not depend on a `[sources]` table being honored.
The builder checks loaded package paths, versions, environment configuration and
PrettyTables before rendering. It never resolves or installs dependencies itself.

From the checkout root, create temporary projects and a separate writable depot
for each companion. The following POSIX shell recipe prepares and renders them
sequentially. Set thread limits through the environment and inherit CPU affinity
from the launcher when needed; the builder does not change CPU affinity.

```sh
set -eu
export PERFCHECKER_SOURCE="$(pwd)"
export JULIA_NUM_THREADS="${JULIA_NUM_THREADS:-1}"
export JULIA_NUM_PRECOMPILE_TASKS="${JULIA_NUM_PRECOMPILE_TASKS:-1}"
export OPENBLAS_NUM_THREADS="${OPENBLAS_NUM_THREADS:-1}"
export OMP_NUM_THREADS="${OMP_NUM_THREADS:-1}"
DOCS_WORKSPACE="$(mktemp -d)"
for companion in linuxperf likwid; do
    project="$DOCS_WORKSPACE/$companion-project"
    mkdir -p "$project"
    cp "website/optional-api/$companion/Project.toml" "$project/Project.toml"
    if [ "$companion" = linuxperf ]; then
        export PERFCHECKER_COMPANION=PerfCheckerLinuxPerf
    else
        export PERFCHECKER_COMPANION=PerfCheckerLIKWID
    fi
    export JULIA_DEPOT_PATH="$DOCS_WORKSPACE/$companion-depot"
    julia --startup-file=no --project="$project" -e '
        using Pkg
        root = ENV["PERFCHECKER_SOURCE"]
        owner = ENV["PERFCHECKER_COMPANION"]
        Pkg.develop([Pkg.PackageSpec(path=root), Pkg.PackageSpec(path=joinpath(root,"packages",owner))])
        Pkg.instantiate()'
    julia --startup-file=no --project="$project" website/optional-api/make.jl "$companion"
done
```

Preserve both resolved Project/Manifest pairs with the output receipts when sharing
a qualification. Remove the temporary projects and depots after they are no longer
needed. No sysctl, capability or native-library configuration change is part of
this prototype. Windows users can perform the same two preparations with temporary
directories and environment variables in PowerShell.

Each output lives under `website/build/optional-api/<companion>/`:

- `.documenter/<companion>/public-api.md` and `full-api.md` contain Documenter's
  rendered bodies, signatures, canonical/noncanonical anchors and pinned source links.
- `.documenter/public/objects.inv` is the renderer's real inventory.
- `api-provenance.toml` records owner/binding/signature metadata, versions, the
  runtime revision, Project/Manifest hashes and documentation input/output hashes.

The source paths are namespaced by companion. Full API is canonical; Public API
uses `canonical=false`. Both render the module docstring and real `@autodocs`.
The module is explicitly rendered by `@docs` and excluded from the `@autodocs`
category order, preventing duplicate canonical module documentation.
Full includes documented private bindings, not undocumented internal functions.
These new companions are part of development 1.0.1 and are absent from the stable
1.0.0 source. The prototype refuses to render them as stable 1.0.0 documentation.

## Binding and reference contract

Both owners export the seven bindings below. Each signature comes from that
owner's actual Julia Docs metadata, not a shared counter-interface placeholder.

| Binding | Public API | Full API | Existing docstring references |
| --- | --- | --- | --- |
| `CounterRecord` | Yes | Canonical | LIKWID refers to its own `CounterResult` |
| `CounterResult` | Yes | Canonical | Refers to its own `CounterRecord` |
| `measure_counters` | Yes | Canonical | No external `@ref` |
| `counter_bundle` | Yes | Canonical | No external `@ref` |
| `counter_command` | Yes | Canonical | No external `@ref` |
| `counter_executor` | Yes | Canonical | Refers to its own `run_counter_suite` |
| `run_counter_suite` | Yes | Canonical | No external `@ref` |

The builder verifies the public binding set and actual docstring ownership.
Documenter's `warnonly=false` makes unresolved references or missing docstrings
fail the render. Source links use the selected checkout's full revision. Runtime
source must be clean; uncommitted prototype documentation inputs are separately
hashed, so a local preview is not misrepresented as a committed publication.

## Qualification still required

Before integration, resolve and render both environments for real. Check every
public entry in both pages, recorded signatures against Julia help, all intra-module
references and inventory targets, unique anchors and correct source revisions.
Then build each emitted `.documenter` tree with the existing website VitePress
toolchain and check desktop/mobile navigation, visible docstring bodies and links.
No Node installation is run by this Julia builder. Cross-companion references,
the other four companion environments and final site assembly remain subsequent
work; no API or browser qualification is claimed by this source-only prototype.
