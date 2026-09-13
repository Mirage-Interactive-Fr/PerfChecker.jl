# Compare versions and revisions

The version history in the [operation benchmark](quick-tour.md) shows how
Bibliography export changed across releases. A release can also update its
dependencies, so that history does not isolate a particular source change.
For that, we will compare two commits while keeping the dependencies fixed.

The *baseline* is the revision we compare against. The *candidate* is the
revision we want to evaluate. Here the candidate changes BibTeX export from
concatenating per-entry strings to writing entries into one buffer.

## Run the two-revision example

Use the `examples/bibliography/` directory and controller environment prepared
in the [operation benchmark](quick-tour.md). Inspect the selected revisions,
then run the comparison:

```sh
julia --project=.controller/core compare-exports.jl plan
julia --project=.controller/core compare-exports.jl run
```

The script selects `export_bibtex` with BenchmarkTools. It compares parent
`6a4cc90` with the [streaming-export commit `575ec81`](https://github.com/JuliaBibliographies/Bibliography.jl/commit/575ec810042cc791fd47a2c025a80246ccf039b5),
using the BibInternal and BibParser revisions in `sources.toml` for both.
Each revision gets 100 samples, one evaluation per sample and one worker thread.

The terminal prints a new `results/export-comparison-*` directory. Its report
contains the measurements and the exact revisions used.

## Read the result

The recorded run used Windows and Julia 1.13.0 on 12 September 2026:

| Median measurement | Parent `6a4cc90` | Streaming export `575ec81` | Change |
| --- | ---: | ---: | ---: |
| Allocated bytes | 3,904 B | 2,976 B | −23.77% |
| Allocation count | 27 | 23 | −14.81% |
| Elapsed time | 7,600 ns | 6,800 ns | −10.53% |
| Garbage collection time | 0 ns | 0 ns | No relative change defined |

```@raw html
<DocMedia src="/examples/bibliography/figures/streaming-comparison.svg" alt="Before and after a Bibliography streaming export change: bytes 3904 to 2976, allocations 27 to 23, median time 7.6 to 6.8 microseconds" caption="100 samples per revision, with fixed dependency versions. The timing distributions overlap." />
```

The candidate allocates 928 fewer bytes and creates four fewer allocations
per export. Its median time is also lower, but the timing samples overlap.
Repeating this pair with larger bibliographies would help determine how the
change behaves on more demanding inputs.

The report is `inconclusive` because the example has no acceptance limits.
Both GC values are zero, so a relative GC change is undefined. The benchmark
also has no correctness oracle: check the exported documents separately before
accepting the optimization. An *oracle* is the check that an operation produced
the expected result, such as retaining the citation keys and titles.

```@raw html
<p><a href="../examples/bibliography/streaming-comparison.json" download>Download the comparison measurements</a></p>
```

## Compare your own change

Keep the input and measurement settings fixed, choose a baseline commit and
add the candidate revision to your suite. Save full commit hashes when a branch
may move. Use the same dependency versions for a source-code comparison; let
Pkg resolve each release's dependencies when comparing complete released stacks.

The [comparison reference](../reference/comparisons.md) describes the Julia
constructors, grouped baselines and command-line options. For a graphical
selection, use the [VS Code target picker](../reference/comparisons.md#Use-the-VS-Code-target-picker).

## Investigate the difference

Timings locate a change between revisions. A profile helps locate the calls
responsible for it. Continue with [investigating a performance change](../guide/investigate.md)
to read Bibliography's allocation and CPU profiles. Once you have a useful
comparison, [CI checks](ci.md) can apply limits to future changes.

```@raw html
<details class="reference-details"><summary>Configuration reference</summary>
<p id="Define-candidates-in-Julia"><a href="../reference/comparisons#Define-candidates-in-Julia">Define candidates in Julia</a></p>
<p id="Exact-and-grouped-references"><a href="../reference/comparisons#Exact-and-grouped-references">Exact and grouped references</a></p>
<p id="Use-the-VS-Code-target-picker"><a href="../reference/comparisons#Use-the-VS-Code-target-picker">VS Code target picker</a></p>
<p id="Use-repeated-CLI-targets"><a href="../reference/comparisons#Use-repeated-CLI-targets">Command-line targets</a></p>
<p id="Comparability-rules"><a href="../reference/comparisons#Comparability-rules">Comparability rules</a></p>
</details>
```
