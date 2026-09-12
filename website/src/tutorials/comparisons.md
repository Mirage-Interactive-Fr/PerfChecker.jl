# Compare versions and revisions

PerfChecker can compare released package versions, the current checkout, and
multiple Git branches, tags or commits in one plan. Keep the workload fixed,
choose a reference and inspect both the measured change and its variation.


```@raw html
<DocMedia src="/examples/bibliography/figures/history-time.svg" alt="Bibliography export medians across nine tagged versions on a linear microsecond axis" caption="One hundred samples per tag, Windows, Julia 1.13.0, one worker thread. Inputs match; the dependency stack evolves with the tags. Lower means less elapsed time." />
```

Start with the runnable [Bibliography history](bibliography.md#Compare-the-package-history)
or the [short tutorial](quick-tour.md). The history compares nine versioned
dependency stacks; the [streaming experiment](bibliography.md#Extend-to-historical-comparisons)
holds dependency pins fixed to examine one source change.

## Define candidates in Julia

The following is a configuration fragment for an existing package suite, not a
standalone script. `features`, `source` and `worker_environment` come from that
suite: workload definitions, the package repository and its prepared measurement
project. Run `compare-exports.jl plan` then `compare-exports.jl run` from the
prepared Bibliography core environment for the complete version of this example.

```julia
using PerfChecker
candidates = [
    SuiteCandidate("before-streaming", "6a4cc9027dcc094d21b3681ccff86ca4aec84a23"),
    SuiteCandidate("after-streaming", "575ec810042cc791fd47a2c025a80246ccf039b5"),
    SuiteCandidate("tagged-0.4.0", "v0.4.0"),
]

package = PackageSuite(
    "Bibliography";
    source,
    worker_environment,
    versions = [v"0.3.0", v"0.4.0"],
    candidates,
    features,
)
```

The snippet assumes `features` and a prepared worker environment from your
suite. The complete runnable example is `examples/bibliography/compare-exports.jl`.
It additionally pins BibInternal and BibParser to prevent dependency changes from
confounding the two-revision comparison. Use a full Git revision when a moving
branch would make reruns ambiguous.

`compatibility_version` can select a feature variant when a candidate revision's
declared package version does not describe its API. This changes feature
selection, not the candidate's source identity.

## Exact and grouped references

An exact policy compares a candidate to one reference:

```julia
ComparisonPolicy(
    "before-streaming-vs-0.4";
    package = "Bibliography",
    comparison_key = "bibliography-export/v1",
    baselines = ["0.4.0"],
    candidates = ["before-streaming"],
)
```

A grouped policy summarizes several references before comparing candidates:

```julia
ComparisonPolicy(
    "experiments-vs-recent";
    package = "Bibliography",
    comparison_key = "bibliography-export/v1",
    baselines = ["0.3.0", "0.4.0"],
    candidates = ["before-streaming", "after-streaming"],
    aggregation = :median,
)
```

Available aggregations are `:median`, `:mean`, `:minimum`, and `:maximum`.
Median is the usual default; minimum is useful only when “best observed
reference” is an intentional policy.

Attach policies to `SoftwareSuite(...; comparisons)` or provide them when
planning.


```@raw html
<DocMedia src="/examples/bibliography/figures/history-delta.svg" alt="Change in median export time for eight Bibliography tags against tag 0.1.0" caption="The reference is 0.1.0. Negative means less time, positive means more. This recorded comparison has no acceptance budget; the bars are not pass or fail labels." />
```

## Use the VS Code target picker

The visual suite editor scans the selected package repository and fills a native
drop-down grouped into branches, tags and recent commits. Selecting an entry
fills its revision and label. The free-form field also parses:

- plain Git references such as `feature/faster-parser`;
- `refs/heads/...`, `refs/tags/...`, and remote references;
- full GitHub or GitLab tree, tag and commit URLs;
- `owner/repository@reference` shorthand;
- full commit hashes.

After adding targets, the comparison matrix presents them beside release and
working-tree targets. Select one or several references, one or several
candidates, and the aggregation rule. Saving produces
a JSON configuration file, which the CLI can consume with `--config`.

## Use repeated CLI targets

These commands extend an existing `perf/suite.jl`; they run from its prepared
controller project. The multiline syntax below is for a POSIX shell. In
PowerShell, put the command on one line. For the ready-to-run Bibliography
experiment, prefer `compare-exports.jl` above.

```sh
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- plan --suite=perf/suite.jl --profile=ci \
  --candidate='{"package":"Bibliography","label":"before-streaming","revision":"6a4cc9027dcc094d21b3681ccff86ca4aec84a23"}' \
  --candidate='{"package":"Bibliography","label":"after-streaming","revision":"575ec810042cc791fd47a2c025a80246ccf039b5"}'
```

For substantial configurations, prefer the shared UI configuration file over
shell-escaped JSON:

```sh
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- run --suite=perf/suite.jl --profile=ci \
  --config=perf/perfchecker-ui.json --reports=perf/results/experiments
```

## Comparability rules

PerfChecker compares observations only when their measurement definitions and
`comparison_key` agree. Hardware, runtime, dependency and source identity remain
in the bundle so consumers can detect a confounded comparison.

Use a new comparison key when inputs, output semantics, warm-up policy or
measurement procedure changes. A missing result should remain `missing` or
`unavailable`; it must never be silently converted into an improvement.
