# Investigate a change

A lower cost suggests where to investigate. Compare one source change with fixed dependencies, then profile the operation to locate work.

```@raw html
<a id="Compare-versions-and-revisions"></a><a id="Run-the-two-revision-example"></a>
```

## Controlled comparison

This separate fixture differs from the first chapter’s one-entry release comparison. The saved BibTeX study compares parent `6a4cc90` with streaming-export commit `575ec81`, holding BibInternal and BibParser fixed. It records 100 BenchmarkTools samples per revision:

| Measurement | Parent | Streaming |
| --- | ---: | ---: |
| Median elapsed time | 7.6 µs | 6.8 µs |
| Median allocated bytes | 3,904 B | 2,976 B |
| Median allocation count | 27 | 23 |

The recorded verdict is `inconclusive`: timing ranges overlap, and correctness was not checked. The JSON contains summaries, not individual samples.

```@raw html
<a href="../examples/bibliography/streaming-comparison.json" download>Download the comparison summary (JSON)</a>
```

From the [Bibliography example source](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/tree/2cf431eb5a84f05e0af1098b7f6e5db84d479288/examples/bibliography), reproduce this study:

```sh
cd examples/bibliography
julia --startup-file=no setup.jl core
julia --startup-file=no --project=.controller/core compare-exports.jl plan
julia --startup-file=no --project=.controller/core compare-exports.jl run
```

```@raw html
<a id="Investigate-the-difference"></a>
```

## CPU profile

```@raw html
<InteractiveRecordedPlot source="/examples/bibliography/profiles/cpu.json" html="/examples/bibliography/profiles/cpu.html" title="Bibliography streaming export · CPU samples" kind="cpu_flamegraph" />
```

Revision `575ec81` · Windows · Julia 1.13.0 · 159 CPU samples. Inspect `_write_bibtex` at `bibtex.jl:162`: 100 samples (62.9%), including 90 in `print` at `strings/io.jl:48`. Inclusive stack weights overlap; do not add them. Without a parent profile, these stacks do not explain the measured difference. [Capture details](bibliography.md#Locate-the-remaining-cost).

## Allocation profile

```@raw html
<InteractiveRecordedPlot source="/examples/bibliography/profiles/allocation-pie.json" html="/examples/bibliography/profiles/allocation-pie.html" title="Bibliography streaming export · sampled allocation share" kind="allocation_pie" />
```

This separate warmed capture uses fresh inputs at `575ec81`: Linux, Julia 1.13.1, one worker thread. The pie scales sampled site weights to the independently measured 2,976 B / 23-allocation total; sampled weights are not that total. Capacity reservation at `bibtex.jl:143` accounts for 41.9% of estimated bytes, writing at line 162 for 27.5%. Without a parent profile, neither attributes a reduction; correctness was not checked. [Full capture details](bibliography.md#Locate-the-remaining-cost) retain the sampled-event counts and weights.

## Check the change

Keep the input, procedure and dependency versions fixed; rerun correctness checks and compatible measurements after editing. Use explicit acceptance limits when gating CI. A missing result remains missing. [Comparison configuration](../reference/comparisons.md) covers candidate revisions, grouped references and limits; [collector reference](../reference/checks.md) covers profile settings. Continue with [suites and CI](../software-suites.md).

```@raw html
<details class="reference-details"><summary>Configuration reference</summary>
<p id="Define-candidates-in-Julia"><a href="../reference/comparisons.html#Define-candidates-in-Julia">Define candidates in Julia</a></p>
<p id="Use-the-VS-Code-target-picker"><a href="../reference/comparisons.html#Use-the-VS-Code-target-picker">VS Code target picker</a></p>
<p id="Use-repeated-CLI-targets"><a href="../reference/comparisons.html#Use-repeated-CLI-targets">Command-line targets</a></p>
<p id="Comparability-rules"><a href="../reference/comparisons.html#Comparability-rules">Comparability rules</a></p>
</details>
```

```@raw html
<a id="Compare-two-versions"></a><a id="compare-two-versions"></a><a id="Run-the-example"></a><a id="run-the-example"></a><a id="Read-the-result"></a><a id="read-the-result"></a><a id="Compare-your-own-change"></a><a id="compare-your-own-change"></a><a id="Exact-and-grouped-references"></a><a id="exact-and-grouped-references"></a><a id="Comparability"></a><a id="comparability"></a><a id="Gate-CI"></a><a id="gate-ci"></a><a id="Recorded-examples"></a><a id="recorded-examples"></a>
```
