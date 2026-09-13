# Bibliography walkthrough

All commands below run from this directory (`examples/bibliography/` in the
PerfChecker checkout). Use Julia 1.12+ and Git. Preparation downloads dependencies
and pinned example sources; it is specific to this example, not PerfChecker installation.

## Start with one existing test item

```sh
julia --startup-file=no setup.jl items
julia --startup-file=no --project=.controller/items items.jl list
julia --startup-file=no --project=.controller/items items.jl performance "Bibliography export workload"
```

The last command runs only the named item, once, in a fresh process. It prints
a new `results/items-*` directory containing `testitems.json`. Assertions must
pass; no performance budget is implied. Omit the name to measure both items,
or use `items.jl functional` to exclude the `perf_only` item.

For a self-contained item to adapt to your own package, download
`website/src/public/examples/bibliography/bibliography-testitems.jl` from the
first-result documentation page. It uses Bibliography's public API and its own
fixture instead of the pinned upstream test files.

## Measure the operation separately

Prepare the suite controller, inspect the plan, then measure just export:

```sh
julia --startup-file=no setup.jl
julia --project=.controller/core run.jl plan
julia --project=.controller/core run.jl benchmark Bibliography export_bibtex
```

The complete plan contains seven workloads and five collectors. Run one leaf
with `run.jl benchmark Bibliography export_bibtex`; select all collectors with
`run.jl all`. Available collectors are `benchmark`, `chairmark`, `profile_alloc`,
`profile` and `wall_profile` (Julia 1.12+). Package and feature selectors accept
comma-separated names. Every execution writes a new directory below `results/`.

Sampling profiles use a continuous loop with `state_policy=:reuse`, because
these seven workloads read their prepared inputs. Timing and allocation checks
keep fresh state. Verify the reuse assumption with
`julia --project=.controller/items verify-reuse.jl` after `setup.jl items`.
Do not apply that policy to workloads that mutate their inputs.

The source commits are recorded in `sources.toml`. Preparation creates separate
checkouts below `.sources/` and does not modify existing development packages.
The controller owns UI dependencies; measured packages remain in isolated workers.

## Open an interface

```sh
julia --project=.controller/core repl.jl
julia setup.jl web
julia --project=.controller/web web.jl
julia setup.jl pluto
julia --project=.controller/pluto pluto.jl
julia setup.jl items
julia --project=.controller/items items.jl functional
julia --project=.controller/items items.jl performance
```

Open the web interface at <http://127.0.0.1:8871/perfchecker/v1/>. For VS Code, open
this directory, set `perfchecker.runnerProject` to the absolute path of
`.controller/core`, and choose `suite.jl` in the suite editor.
For native items in the Testing view, use `.controller/items` instead. The two
declarations reuse upstream `test/api.jl` and `perf/features/export_bibtex.jl`.
The pinned Bibliography source itself has no native `@testitem` declarations.

Set `JULIA_NUM_THREADS`, `JULIA_NUM_GC_THREADS`, `JULIA_NUM_PRECOMPILE_TASKS`,
`OPENBLAS_NUM_THREADS`, `OMP_NUM_THREADS` and `MKL_NUM_THREADS` to `1` before
launching Julia, and run one command at a time for a bounded machine session.

These upstream performance workloads have no correctness oracle. A successful
collector means execution succeeded; it does not replace functional TestItems
or prove an improvement without a measured baseline.

See `website/src/tutorials/bibliography.md` for the detailed walkthrough.

For a two-revision experiment, run `compare-exports.jl plan`, then
`compare-exports.jl run` in the core controller. It compares the streaming export
change with its parent while holding the two dependency revisions fixed. The
default report is diagnostic: no CI acceptance limits are configured.

## Reproduce interface captures

To reproduce the browser walkthrough, start `web.jl` and, from the repository
root, run:

```sh
npm ci --prefix qualification
npm exec --prefix qualification -- playwright install chromium
node qualification/shared/bibliography-web.mjs http://127.0.0.1:8871/perfchecker/v1/ .qualification/bibliography-web
```

This is an opt-in live test: it launches one real export benchmark, records the
browser, checks completion, reopens the saved distribution, and selects a
measured point. It saves screenshots, an uncut WebM and `capture.json` locally.
Review captures before copying them into the website; publishing is separate.
