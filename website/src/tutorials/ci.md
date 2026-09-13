# Run checks in CI

CI repeats an experiment you can already run locally. Decide which result should fail the job, and keep the reports.

!!! warning "Release candidate"
    Check [release availability](../guide/installation.md) first. The registered stable release does not supply this complete workflow.

## Measure existing test items

```sh
julia --startup-file=no --project=test -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- testitems --root=. --list
julia --startup-file=no --project=test -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- testitems --root=. --tags=small --samples=1 --threads=1 --reports=results/items
```

- The second command exits nonzero if an item does not validate.
- `performance="not_compared"` means no regression budget was applied.
- Do not gate on a single first-call item duration.

For functional jobs that must exclude `:perf_only`, load PerfChecker and TestItemRunner, then:

```julia
@run_package_tests filter=testitem_filter(:test)
```

## GitHub Actions

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
      OPENBLAS_NUM_THREADS: '1'
    steps:
      - uses: actions/checkout@v4
      - uses: julia-actions/setup-julia@v2
        with:
          version: '1'
      - name: Prepare test environment
        run: julia --startup-file=no --project=test -e 'using Pkg; Pkg.develop(path=pwd()); Pkg.instantiate()'
      - name: Measure selected items
        run: julia --startup-file=no --project=test -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- testitems --root=. --tags=small --samples=1 --threads=1 --reports=results/items
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: performance-items
          path: results/items
```

## Regression gates

Run a suite, then compare two saved bundles:

```sh
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- run --suite=perf/suite.jl --profile=ci --reports=results/ci --progress=jsonl

julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- check --baseline=results/baseline --candidate=results/candidate --limit=julia.wall.time=0.05 --limit=julia.alloc.bytes=0.02 --min-samples=10 --reports=results/comparison
```

- Limits are relative fractions: `0.05` allows a 5% increase for a lower-is-better metric.
- They are illustrative, not universal thresholds. Inspect distributions before choosing one.
- `check` fails when a limit fails; `compare` does not.

## Keep the right artifacts

- Native items: `testitems.json`.
- Suite runs: the whole report directory, including `bundles/`.
- Keep runners, thread settings and fixtures comparable between baseline and candidate.

```@raw html
<a id="Existing-test-items"></a>
<a id="GitHub-Actions-example"></a>
<a id="Software-suites-and-regression-gates"></a>
<a id="Retain-the-right-artifacts"></a>
```
