# Compare two versions

A **baseline** is the revision you compare against; a **candidate** is the revision you evaluate. Hold dependencies fixed to isolate one source change.

## Run the example

```sh
julia --project=.controller/core compare-exports.jl plan
julia --project=.controller/core compare-exports.jl run
```

The script compares `export_bibtex` with BenchmarkTools between parent `6a4cc90` and streaming-export commit `575ec81`, with BibInternal and BibParser pinned for both.

## Read the result

Median parent → streaming:

- Allocated bytes 3,904 B → 2,976 B (−23.77%)
- Allocation count 27 → 23 (−14.81%)
- Elapsed time 7,600 ns → 6,800 ns (−10.53%)
- GC time 0 ns → 0 ns (undefined change)

The candidate allocates less and its median time is lower, but the timing distributions overlap. The report is `inconclusive` because no acceptance limits were configured. Both GC values are zero, so a relative GC change is undefined.

## Compare your own change

- Fix the input and measurement settings.
- Pick a baseline commit; add the candidate revision to the suite.
- Use full commit hashes when a branch can move.
- Keep the same dependency versions for a source comparison; let Pkg resolve each release when comparing whole stacks.

## Exact and grouped references

```julia
ComparisonPolicy(
    "before-streaming-vs-0.4";
    package = "Bibliography",
    comparison_key = "bibliography-export/v1",
    baselines = ["0.4.0"],
    candidates = ["before-streaming"],
)
```

Use `aggregation = :median | :mean | :minimum | :maximum` to summarize several references before comparing.

## Comparability

- PerfChecker compares observations only when their measurement definitions and `comparison_key` agree.
- Use a new comparison key when inputs, output semantics, warm-up or procedure change.
- A missing result stays missing; it is never an improvement.

## Gate CI

Use `check` with explicit limits:

```sh
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- check \
  --baseline=results/baseline --candidate=results/candidate \
  --limit=julia.wall.time=0.05 --limit=julia.alloc.bytes=0.02 \
  --min-samples=10 --reports=results/comparison
```

Limits are relative fractions; `check` fails when a limit fails. `compare` writes the same diagnostics without a failing exit status. See [Run checks in CI](ci.md).

## Recorded examples

```@raw html
<DocMedia src="/examples/bibliography/figures/streaming-comparison.svg" alt="Before and after a Bibliography streaming export change: bytes 3904 to 2976, allocations 27 to 23, median time 7.6 to 6.8 microseconds" caption="100 samples per revision, with fixed dependency versions. The timing distributions overlap." />
```

```@raw html
<p><a href="../examples/bibliography/streaming-comparison.json" download>Download the comparison measurements</a></p>
```

```@raw html
<details class="reference-details"><summary>Configuration reference</summary>
<p id="Define-candidates-in-Julia"><a href="../reference/comparisons#Define-candidates-in-Julia">Define candidates in Julia</a></p>
<p id="Exact-and-grouped-references"><a href="../reference/comparisons#Exact-and-grouped-references">Exact and grouped references</a></p>
<p id="Use-the-VS-Code-target-picker"><a href="../reference/comparisons#Use-the-VS-Code-target-picker">VS Code target picker</a></p>
<p id="Use-repeated-CLI-targets"><a href="../reference/comparisons#Use-repeated-CLI-targets">Command-line targets</a></p>
<p id="Comparability-rules"><a href="../reference/comparisons#Comparability-rules">Comparability rules</a></p>
</details>
```


```@raw html
<a id="Compare-versions-and-revisions"></a>
<a id="Run-the-two-revision-example"></a>
<a id="Investigate-the-difference"></a>
```
