# Suites and CI

A suite keeps the workload, collector, package versions and settings together. This example measures the first chapter's Bibliography export on two releases, locally and in GitHub Actions.

## Define and run

In your repository, prepare a controller and a separate worker seed once:

```sh
julia --project=perf -e 'using Pkg; Pkg.add(["PerfChecker", "BenchmarkTools"])'
julia --project=perf/workers -e 'using Pkg; Pkg.add("BenchmarkTools")'
```

Save the operation as `perf/export.jl`:

```julia
using Bibliography
perf_setup() = Bibliography.import_bibtex(
    "@article{example, title={A small example}, author={Ada Lovelace}, " *
    "journal={Julia Studies}, year={2026}}\n")
perf_workload(entries) = Bibliography.export_bibtex(entries)
```

Save its suite as `perf/suite.jl`:

```julia
using PerfChecker
function build_suite()
    feature = FeatureSpec(:export_bibtex;
        backend = :benchmark, entrypoint = joinpath(@__DIR__, "export.jl"),
        comparison_key = "bibliography/one-entry-export/v1",
        options = Dict(:samples => 50, :evals => 1, :seconds => 1.0, :threads => 1))
    package = PackageSuite("Bibliography";
        versions = [v"0.3.1", v"0.4.0"], include_dev = false,
        worker_environment = joinpath(@__DIR__, "workers"), features = [feature])
    SoftwareSuite(:bibliography_export, [package])
end
```

`FeatureSpec` defines the operation and collector; `PackageSuite` selects releases and the worker seed; `SoftwareSuite` groups them. PerfChecker stays in the controller while the isolated workers resolve each release. Preparation is outside the timed operation, and each sample has one evaluation.

Inspect the plan, then execute that same suite:

```sh
julia --project=perf -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- plan --suite=perf/suite.jl --profile=release
julia --project=perf -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- run --suite=perf/suite.jl --profile=release --reports=perf/results/local
```

The plan contains two version targets. Successful collection alone is `not_checked` for correctness: add a `perf_oracle(state, result)` and `oracle = OracleSpec()` to validate the result. [Workload contracts](reference/checks.md) explain verification, cleanup and asynchronous synchronization.

## CI

Save this as `.github/workflows/performance.yml`. It runs the suite above on every push and pull request, then retains the reports even when collection fails:

```yaml
name: Performance
on: [push, pull_request]
jobs:
  measure:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: julia-actions/setup-julia@v2
        with:
          version: '1.13'
      - name: Prepare controller and worker seed
        run: |
          julia --project=perf -e 'using Pkg; Pkg.instantiate()'
          julia --project=perf/workers -e 'using Pkg; Pkg.instantiate()'
      - name: Run the suite
        run: julia --project=perf -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- run --suite=perf/suite.jl --profile=release --reports=perf/results/ci
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: performance-results
          path: perf/results/ci
```

Commit the two projects, workload, suite and workflow. Review `suite-report.md` and retain the bundle with its source and runtime provenance. Shared CI runners vary: this workflow collects evidence and fails on unsuccessful collection; a regression gate additionally needs a comparable baseline and explicit [acceptance limits](reference/comparisons.md#Regression-limits).

For existing test items, see [TestItems](test-items.md); for installed-package qualification, see [qualification](reference/qualification.md). [The Bibliography example](tutorials/bibliography.md) extends this pattern to more collectors and versions.

```@raw html
<a id="Software-suites"></a><a id="software-suites"></a><a id="Define-a-suite"></a><a id="define-a-suite"></a><a id="Three-objects"></a><a id="three-objects"></a><a id="Open-the-supplied-suite"></a><a id="open-the-supplied-suite"></a><a id="Load-and-inspect"></a><a id="load-and-inspect"></a><a id="Select-one-workload-and-one-collector"></a><a id="select-one-workload-and-one-collector"></a><a id="Run-and-save"></a><a id="run-and-save"></a><a id="Select-and-run"></a><a id="select-and-run"></a><a id="Understand-its-workload-definition"></a><a id="understand-its-workload-definition"></a><a id="Adapt-the-suite-to-your-package"></a><a id="adapt-the-suite-to-your-package"></a><a id="Workload-lifecycle"></a><a id="workload-lifecycle"></a><a id="Why-the-worker-has-its-own-environment"></a><a id="why-the-worker-has-its-own-environment"></a><a id="Add-versions-and-comparisons"></a><a id="add-versions-and-comparisons"></a><a id="Profiles"></a><a id="profiles"></a><a id="Recorded-examples"></a><a id="recorded-examples"></a><a id="Continue-with-the-same-experiment"></a><a id="continue-with-the-same-experiment"></a><a id="Next"></a><a id="next"></a>
```
