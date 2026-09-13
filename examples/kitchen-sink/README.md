# Real package experiments

Two runnable examples share a deterministic event stream:

- `suite.jl`: DataStructures heaps, counters, circular buffers and a vector baseline;
- `oxygen/suite.jl`: the same event processing behind three Oxygen HTTP routes.

Run commands from this directory. Julia 1.12 or newer is required for the example
controller; this is independent of PerfChecker's minimum Julia version.

```sh
julia setup.jl core
julia --project=. test/runtests.jl
julia --project=. measure.jl plan
julia --project=. measure.jl quick
julia --project=. measure.jl history
julia --project=. oxygen/measure.jl history
```

`plan` executes nothing. `quick` measures the latest selected tag. `history`
measures several tags. `profiles` collects diagnostic profiles on the latest tag.
`all` requests the complete matrix (1,080 DataStructures or 180 Oxygen checks).
It is intentionally opt-in, never part of the documentation build.

Each run creates a new `results/` directory containing reports, correctness
outcomes and a verifiable bundle. Reuse that directory for plotting. A green
correctness result does not establish a performance budget.

Prepare only the optional interface you want with `setup.jl plots`, `web`,
`pluto`, `oxygen`, `extras` or `analyzers`; each has its own `.controller/` project.
For example:

```sh
julia setup.jl plots
julia --project=.controller/plots export.jl results/ACTUAL-RUN exports/history
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
