# Run checks in CI

Start with the exact item or suite command that works locally. CI prepares its
dependencies, executes it and retains its output. A functional failure and a
performance regression need different acceptance rules.

These examples use the V1 APIs. Check [release availability](../guide/installation.md)
first: the currently registered older PerfChecker release does not supply this
complete workflow. Use a published V1 version or your explicitly pinned preview.

## Existing test items

Use your package's prepared test environment containing PerfChecker,
TestItemRunner, the target package and its test dependencies. In the following
commands that environment is `test/`, and the current directory is the package
root. Change the project path if you use another environment.

List first, then measure only the `small` items:

```sh
julia --startup-file=no --project=test -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- testitems --root=. --list
julia --startup-file=no --project=test -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- testitems --root=. --tags=small --samples=1 --threads=1 --reports=results/items
```

The [downloadable Bibliography item](../guide/first-check.md) has that tag.
For your own package, select its tags or pass repeated `--item-id` arguments from
the listing. Do not reuse an existing `testitems.json` destination.

The second command returns a nonzero exit if an item does not validate. Its
`testitems.json` preserves the measurements, assertions and environment context.
`performance="not_compared"` means it has **not** applied a regression budget.
Do not gate latency on a single first-call item duration.

For ordinary functional TestItemRunner jobs that should exclude `:perf_only`,
use `@run_package_tests filter=testitem_filter(:test)` after loading PerfChecker
and TestItemRunner. Loading PerfChecker alone does not change the upstream runner.

## GitHub Actions example

This workflow assumes your maintained `test/Project.toml` already declares the
example's test dependencies, PerfChecker and TestItemRunner. The preparation step
connects the checked-out package to that environment and resolves it before the
measurement. Save this as `.github/workflows/performance.yml` in your package:

```yaml
name: Performance items
on: [push, pull_request]
permissions:
  contents: read
jobs:
  items:
    runs-on: ubuntu-latest
    env:
      JULIA_NUM_THREADS: '1'
      JULIA_NUM_GC_THREADS: '1'
      JULIA_NUM_PRECOMPILE_TASKS: '1'
      OPENBLAS_NUM_THREADS: '1'
      OMP_NUM_THREADS: '1'
      MKL_NUM_THREADS: '1'
    steps:
      - uses: actions/checkout@v7
      - uses: julia-actions/setup-julia@v3
        with:
          version: '1'
      - name: Prepare test environment
        run: julia --startup-file=no --project=test -e 'using Pkg; Pkg.develop(path=pwd()); Pkg.instantiate()'
      - name: Measure selected items
        run: julia --startup-file=no --project=test -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- testitems --root=. --tags=small --samples=1 --threads=1 --reports=results/items
      - uses: actions/upload-artifact@v7
        if: always()
        with:
          name: performance-items
          path: results/items
```

The same two preparation/execution steps work in other CI systems; use their
artifact mechanism to retain the report even when execution fails.

## Software suites and regression gates

For an existing `perf/suite.jl`, run it through the public command entry point
from a controller environment containing its collectors. `--project=.` below
means that environment is the current project; it is unrelated to the `--suite`
path. The suite itself declares its isolated worker environment.

```sh
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- run --suite=perf/suite.jl --profile=ci --reports=results/ci --progress=jsonl
```

For a performance gate, use two saved, comparable bundle directories and explicit
limits. In this example `results/baseline` and `results/candidate` stand for those
existing bundle directories, each containing `manifest.json`:

```sh
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- check --baseline=results/baseline --candidate=results/candidate --limit=julia.wall.time=0.05 --limit=julia.alloc.bytes=0.02 --min-samples=10 --reports=results/comparison
```

Here 0.05 allows a five-percent timing increase, and 0.02 a two-percent allocation
increase. They are illustrative acceptance limits, not recommended universal
thresholds. `check` fails unless its comparison passes; `compare` writes diagnostic
results without using a numeric regression as a failing exit status.
See [comparisons](comparisons.md) for references, statistics and comparability.

Keep runners, thread settings and fixtures comparable, and inspect distributions
before choosing a timing threshold. The
[fixed-dependency Bibliography experiment](bibliography.md#Extend-to-historical-comparisons)
shows a reproducible pair; its diagnostic report does not configure an acceptance limit.

## Retain the right artifacts

For native items, keep `testitems.json`. For suite runs, keep the report directory,
including `suite-result.json`, JUnit output, version comparisons, compatibility
evidence and `bundles/`. These are different report formats.

For testing compatible releases of PerfChecker and its interfaces together,
use [collection qualification](../reference/qualification.md). It tests integration
compatibility; it is separate from your package's performance acceptance policy.
