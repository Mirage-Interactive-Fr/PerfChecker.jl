# Real package experiments

Two complete investigations use independently checked inputs:

- `suite.jl`: DataStructures heaps, counters, circular buffers and a vector baseline;
- `oxygen/suite.jl`: the same event processing behind three Oxygen HTTP routes.
- `containers-suite.jl`: 35 containers, construction and use separately, all seven 0.19 patches;
- `oxygen/features-suite.jl`: seven HTTP features across 14 releases, including every 1.10/1.11 patch.

Run commands from this directory. Julia 1.12 or newer is required for the example
controller; this is independent of PerfChecker's minimum Julia version.

```sh
julia setup.jl core
julia --project=. test/runtests.jl
julia --project=. measure.jl plan
julia --project=. measure.jl quick
julia --project=. measure.jl history
julia --project=. containers.jl check
julia --project=. containers.jl history
julia --project=. containers.jl chairmarks
julia setup.jl oxygen
julia --project=.controller/oxygen oxygen/features.jl history
julia --project=.controller/oxygen oxygen/measure.jl history
```

`plan` executes nothing. `quick` measures the latest selected tag. `history`
measures several tags. `profiles` collects diagnostic profiles on the latest tag.
`all` requests all collectors and parameters in the selected suite.
It is intentionally opt-in, never part of the documentation build.

Each run creates a new `results/` directory containing reports, correctness
outcomes and a verifiable bundle. Reuse that directory for plotting. A green
correctness result does not establish a performance budget.

The container history has 490 checks; the HTTP feature history has 98. Timing
checks collect 30 warmed samples with one evaluation each. An optional exact
case name narrows `containers.jl`; a from/to version pair narrows the HTTP history.
History runners save an independently readable report after each version.
Only locally produced, matching checkpoints may be resumed; their `.jls` files
are trusted implementation caches, not formats to accept from other people.

`datastructures-notebook.jl` and `oxygen-notebook.jl` open the published data
without starting a campaign. Prepare them with `julia +1.12 setup.jl pluto`.
The `items.jl` runner exposes the same operations as individually tagged TestItems.

For real packet counters, use Linux/WSL, `setup-linux.jl` and
`oxygen/network-history.jl`. For native profiling, run `setup-native.jl` in the
Linux controller environment, then `native-run.jl datastructures` or `oxygen`.
Native tools are bounded individually and report unavailable tools or timeouts.
Raw profiles and heap snapshots remain in the ignored local results directory.

Prepare only the optional interface you want with `setup.jl plots`, `web`,
`pluto`, `oxygen`, `extras` or `analyzers`; each has its own `.controller/` project.
For example:

```sh
julia setup.jl plots
julia --project=.controller/plots export.jl results/ACTUAL-RUN exports/history
julia --project=.controller/plots collector-export.jl results/CONTAINER-HISTORY results/CHAIRMARKS-RUN exports/collectors
julia --project=. replay.jl results/ACTUAL-RUN
julia setup.jl oxygen
julia --project=.controller/oxygen oxygen/test.jl
julia --project=.controller/oxygen oxygen/loopback.jl
```

Replace `ACTUAL-RUN` by the directory printed by the runner. Do not copy that
placeholder literally. Setup prepares a checkout example; users installing
PerfChecker do not need this template or these extra dependencies.

Set Julia, GC, BLAS and precompilation to one thread/task each. Run campaigns
sequentially. The reference run used a Windows process affinity limited to two
logical CPUs for the initial campaign and four for the extended history;
keep the whole machine workload within your own resource budget.

See the documentation's **Real package examples** section for measurement
boundaries, the recorded results, interface recipes and extension coverage.
