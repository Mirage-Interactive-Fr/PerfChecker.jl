# Existing TestItemRunner items

For the overall workflow and the difference between a workload, suite, run and
comparison, start with [suites and comparisons](suites-and-comparisons.md).

PerfChecker measures existing `@testitem` declarations directly. No generated
performance catalogue or duplicated workload is needed. Load both packages:

```julia
using PerfChecker, TestItemRunner
# Run from your package root in its prepared test environment.
items = discover_testitems(pwd())
result = run_testitems(pwd(); ids=[first(items["items"])["id"]])
```

If there are no items yet, use the [complete downloadable Bibliography item](guide/first-check.md).
It shows the fixture, assertions, selection and saved output.

The optional extension requires TestItemRunner 1.3.2 or later in the 1.x series.
It uses its public `filter` and custom `testset` interfaces; it does not redefine
the runner's methods. Discovery honors `JuliaTestItems.toml` and never evaluates
item bodies or setups. See the [TestItemRunner source and documentation](https://github.com/julia-testitems/TestItemRunner.jl).

## One definition, two uses

| Tags on the existing item | Functional mode | Performance mode |
| --- | --- | --- |
| No special tag | Included | Included |
| `:perf_only` | Excluded | Included |
| `:test_only` | Included | Excluded |
| Both special tags | Configuration error | Configuration error |

Ordinary tags remain available through `tags` (match any) and `exclude_tags`.
There is no required `:perf` tag: shared items work by default.

Until an upstream policy extension is adopted, functional CI applies:

```julia
using TestItemRunner, PerfChecker
@run_package_tests filter=testitem_filter(:test)
```

Simply loading PerfChecker does **not** yet change plain TestItemRunner or the
Julia extension's functional runs. Automatic `:perf_only` exclusion needs an
upstream selection hook and equivalent support in the IDE's runner.

## Interfaces

In VS Code, run **PerfChecker: Discover existing test items**, then use the
**PerfChecker items** controller in the Testing view. Each workspace folder gets
its own controller. Select one item or any subset; exclusions and cancellation
are honored. Configure `runnerProject` to an environment containing both packages.
The normal Julia Testing controller remains available for functional execution.

For a local Oxygen page with selection, cancellation and saved results, first
add PerfCheckerWeb, Oxygen and HTTP to the prepared controller environment. Then,
from the package root:

```julia
using PerfChecker, PerfCheckerWeb, TestItemRunner, Oxygen, HTTP
register_testitem_routes!(pwd(); project=dirname(Base.active_project()))
Oxygen.serve(host="127.0.0.1", port=8080)
```

Open `/perfchecker/items/`. It executes the same native item API as the REPL and
VS Code. Bind to loopback; external hosting requires its own authentication.

The same path works from scripts and CI. In these commands `--project=.` selects
the current directory's already prepared environment; change it to the actual
test environment path if that differs:

```sh
julia --project=. -e 'using PerfChecker, TestItemRunner; exit(perfchecker_main(ARGS))' -- testitems --root=. --list
julia --project=. -e 'using PerfChecker, TestItemRunner; exit(perfchecker_main(ARGS))' -- testitems --root=. --tags=fast --reports=perf/results/items
```

Use repeated `--item-id=...` arguments for exact selection. Unknown and empty
explicit API selections fail before execution. The JSON report records the
selected items, samples and outcomes; its format identifier is documented in
the [saved-data reference](reference/run-bundles.md).

## Measurement scope

Each item runs once by default, in a fresh process. `samples=N` explicitly repeats
it N times; there are no hidden benchmark warmups. Time and Julia allocation bytes
cover the item lifecycle, including imports, setups, assertions and module cleanup.
Process startup and source discovery are outside the item timer. This is an
end-to-end test cost, including compilation, not warmed operation latency.

The official runner performs setups, snippets, default imports and skip handling.
Failed, skipped or assertion-free items cannot become validated measurements.
Measured bytes describe Julia allocations, not all native allocations or RSS.
For warmed operations, native profiling or detailed control over preparation,
the existing shared scenario API remains available.

Correctness validation is distinct from a performance budget. These initial
item reports do not automatically adopt a regression threshold.
