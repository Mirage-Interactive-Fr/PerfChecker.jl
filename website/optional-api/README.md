# Optional API rendering

Render real Julia docstrings with Documenter 1.19.0 and DocumenterVitepress 0.3.5.
The builder does not reconstruct docstrings, measure workloads, open a frontend,
install native libraries or publish a site. The documentation workflow exports
all six owners once per source revision and assembles their rendered Markdown
into the canonical site's theme, navigation and search.

Use one isolated project and private writable depot per companion. LinuxPerf
0.4.2 requires PrettyTables 2; LIKWID 0.4.6 requires PrettyTables 3. Julia 1.10 or
newer is required. Develop this exact checkout's Core and companions explicitly;
Julia 1.10 must not rely on a `[sources]` table.

| Argument | Owner version | Public bindings | Additional coverage |
| --- | --- | ---: | --- |
| `linuxperf` | PerfCheckerLinuxPerf 1.0.1 | 7 | Explicit Julia counter executor |
| `likwid` | PerfCheckerLIKWID 1.0.1 | 7 | Explicit Julia counter executor |
| `makie` | PerfCheckerMakie 1.0.1 | 8 | Real WGLMakie/Bonito HTML extension |
| `web` | PerfCheckerWeb 1.0.0 | 5 | Web methods of Core bindings |
| `pluto` | PerfCheckerPluto 1.0.1 | 4 | Pluto methods of Core bindings |
| `tachikoma` | PerfCheckerTachikoma 1.0.1 | 6 | Real optional Makie pixel method |

These pages describe the selected Core 1.x source, version 1.0.1 or later.
Each receipt records its exact Core version and source revision, separately
from the companion version. Web remains version 1.0.0. Do not
insert these pages into stable Core 1.0.0 documentation: that source does not
include the new counter and terminal APIs.

## Prepare and render sequentially

From the checkout root, use temporary projects and separate writable depots.
Thread limits and CPU affinity come from the caller's launcher. The builder
never resolves dependencies or changes affinity itself.

```sh
set -eu
export PERFCHECKER_SOURCE="$(pwd)"
export JULIA_NUM_THREADS="${JULIA_NUM_THREADS:-1}"
export JULIA_NUM_PRECOMPILE_TASKS="${JULIA_NUM_PRECOMPILE_TASKS:-1}"
export OPENBLAS_NUM_THREADS="${OPENBLAS_NUM_THREADS:-1}"
export OMP_NUM_THREADS="${OMP_NUM_THREADS:-1}"
DOCS_WORKSPACE="$(mktemp -d)"
for companion in linuxperf likwid makie web pluto tachikoma; do
    project="$DOCS_WORKSPACE/$companion-project"
    mkdir -p "$project"
    cp "website/optional-api/$companion/Project.toml" "$project/Project.toml"
    case "$companion" in
        linuxperf) export PERFCHECKER_COMPANION=PerfCheckerLinuxPerf ;;
        likwid) export PERFCHECKER_COMPANION=PerfCheckerLIKWID ;;
        makie) export PERFCHECKER_COMPANION=PerfCheckerMakie ;;
        web) export PERFCHECKER_COMPANION=PerfCheckerWeb ;;
        pluto) export PERFCHECKER_COMPANION=PerfCheckerPluto ;;
        tachikoma) export PERFCHECKER_COMPANION=PerfCheckerTachikoma ;;
    esac
    export JULIA_DEPOT_PATH="$DOCS_WORKSPACE/$companion-depot"
    julia --startup-file=no --project="$project" -e '
        using Pkg
        root = ENV["PERFCHECKER_SOURCE"]
        owner = ENV["PERFCHECKER_COMPANION"]
        specs = [Pkg.PackageSpec(path=root),
            Pkg.PackageSpec(path=joinpath(root,"packages",owner))]
        if owner == "PerfCheckerTachikoma"
            push!(specs, Pkg.PackageSpec(path=joinpath(root,"packages","PerfCheckerMakie")))
        end
        Pkg.develop(specs)
        Pkg.instantiate()'
    julia --startup-file=no --project="$project" website/optional-api/make.jl "$companion"
done
```

Preserve resolved Project/Manifest pairs with the receipts. Remove temporary
projects and depots when no longer needed. No kernel, capability or native-library
configuration is part of rendering. No counter window, terminal, notebook or HTTP
server is started.

## Node theme and HTML

The API theme uses dependencies from the official `website/package-lock.json`:
VitePress, tabs, footnotes and `markdown-it-mathjax3`. It does not import the
renderer's default MathJax 4, Nolebase or version-picker plugins. The pinned
renderer supplies its docstring stylesheet. Use that official lock in this
development checkout, then build each emitted tree sequentially:

```sh
npm ci --prefix website
revision="$(git rev-parse HEAD)"
for companion in linuxperf likwid makie web pluto tachikoma; do
    node website/node_modules/vitepress/bin/vitepress.js build \
        "website/optional-api/build/$revision/$companion/.documenter" \
        --outDir "website/optional-api/build/$revision/$companion/site"
done
```

HTML and browser behavior require independent qualification after Markdown export.
No Node installation is run by the Julia builder.

## Binding and reference contract

Outputs live under `website/optional-api/build/<source-revision>/<companion>/`,
preserving earlier builds and failed attempts.

- `.documenter/<companion>/public-api.md` renders exported bindings noncanonically.
- `.documenter/<companion>/full-api.md` is the canonical reference, including
  documented private bindings. Undocumented functions are not advertised as docs.
- `.documenter/public/objects.inv` is the real renderer inventory.
- `api-provenance.toml` records Docs signatures, binding modules, docstring modules
  and source hashes; separately it records actual local method signatures,
  defining modules and source locations. Versions, Project/Manifest hashes,
  builder/pages/theme inputs and the official Node lock hashes are retained.

The receipt's `channel = "source"` identifies a reusable source export, not a
deployment channel. The same revision's export can enter development, versioned
and stable builds; their canonical `build-info.json` identifies the actual
deployment channel. Earlier prototype receipts and builds remain unchanged.

A Core binding can have methods and docstrings defined by a companion:
`PerfChecker.serve_suite` belongs to Core, while its Web methods and their
docstrings come from PerfCheckerWeb. The receipt preserves those identities.
It does not substitute Core's generic docs for missing companion descriptions.

The builder verifies 37 exported bindings against explicit owner lists. Makie's
WGL extension contributes the explicitly rendered `performance_plot_html`
docstring even though the extension does not export that Core binding.
Tachikoma's Makie extension is loaded for its actual `plot_pixels` method inventory.
No graphics backend is needed to inspect those methods.

Strict Documenter checks reject unresolved references and missing docstrings.
Source links use the full checkout revision. Runtime/package source must be clean;
uncommitted documentation inputs are separately hashed.

## Qualification and assembly

Check public entries and overloads against Julia help, all references, unique
anchors, source revisions and inventory targets. Build real HTML, then inspect
visible docstring bodies, local search and desktop/mobile navigation. Keep each
owner's inventory during assembly; common Core bindings must not overwrite one
another silently.

The main Documenter pass renders only `Modules = [PerfChecker]`. Its assembly
step consumes already rendered companion Markdown after that pass; it does not
copy docstrings into another Julia module or claim Core owns companion methods.
Assembly rejects missing exports, mixed revisions, changed source/input/output
hashes and incomplete page sets before copying any pages. The canonical build
preserves each receipt and inventory under `optional-api/<owner>.toml` and
`optional-api/<owner>.inv`. Each inventory's relative `<owner>/full-api.html`
targets resolve under the shared `optional-api/` namespace. Core's inventory
remains separate, so shared binding names do not overwrite companion overloads.
Generated pages disable the edit link; their actual Julia source links remain.

Core 1.x canonical builds from version 1.0.1 require the complete matching export
set. For an explicit documentation-only stable refresh, the workflow prepares and renders
all six owners from the selected immutable `stable-doc-source` checkout, tests
assembly there and retains its exports and environment pairs. Ordinary builds
use the workflow checkout. Both paths render once and reuse the matching set;
they never substitute a different source revision's companion docs.

Stable 1.0.0's explicit documentation-only refresh retains its own source and
builder; it does not acquire these 1.0.1 APIs. Reference rendering neither qualifies physical
counters nor wires them into native CLI, VS Code, Pluto or MCP selectors.
