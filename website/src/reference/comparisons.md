# Comparison configuration

Options for adding releases, Git revisions and comparison policies to a suite.

## Candidates

```julia
candidates = [
    SuiteCandidate("before", "6a4cc9027dcc094d21b3681ccff86ca4aec84a23"),
    SuiteCandidate("after", "575ec810042cc791fd47a2c025a80246ccf039b5"),
    SuiteCandidate("tagged-0.4.0", "v0.4.0"),
]

package = PackageSuite("Bibliography"; source, worker_environment,
    versions = [v"0.3.0", v"0.4.0"], candidates, features)
```

Use a full Git revision when a branch can move. `compatibility_version` selects a feature variant; it does not change the candidate's source identity.

## References

Exact policy — one reference:

```julia
ComparisonPolicy("before-vs-0.4";
    package = "Bibliography", comparison_key = "bibliography-export/v1",
    baselines = ["0.4.0"], candidates = ["before"])
```

Grouped policy — summarize several references first:

```julia
ComparisonPolicy("experiments-vs-recent";
    package = "Bibliography", comparison_key = "bibliography-export/v1",
    baselines = ["0.3.0", "0.4.0"], candidates = ["before", "after"],
    aggregation = :median)
```

Aggregations: `:median` (default), `:mean`, `:minimum`, `:maximum`.

## VS Code target picker

The visual suite editor scans the package repository into branches, tags and recent commits. The free-form field also parses:

- plain refs such as `feature/faster-parser`;
- `refs/heads/...` and `refs/tags/...`;
- GitHub/GitLab tree, tag and commit URLs;
- `owner/repository@ref`;
- full commit hashes.

Saved selections go to `perf/perfchecker-ui.json`, which the CLI reads with `--config`.

## CLI targets

```sh
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- plan \
  --suite=perf/suite.jl --profile=ci \
  --candidate='{"package":"Bibliography","label":"after","revision":"575ec81"}'
```

For larger configurations, prefer the shared UI JSON file over shell-escaped JSON.

## Comparability

- Compare only when measurement definitions and `comparison_key` agree.
- Use a new key when inputs, output semantics, warm-up or procedure change.
- Hardware, runtime and source identity stay in the bundle so a confounded comparison is detectable.
- A missing result stays `missing` or `unavailable`; it never becomes an improvement.

## Recorded examples

```@raw html
<DocMedia src="/examples/bibliography/figures/history-delta.svg" alt="Change in median export time for eight Bibliography tags against tag 0.1.0" caption="The reference is 0.1.0. Negative means less time, positive means more. This recorded comparison has no acceptance budget; the bars are not pass or fail labels." />
```


```@raw html
<a id="Define-candidates-in-Julia"></a>
<a id="Exact-and-grouped-references"></a>
<a id="Use-the-VS-Code-target-picker"></a>
<a id="Use-repeated-CLI-targets"></a>
<a id="Comparability-rules"></a>
```
