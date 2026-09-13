# Existing TestItems

PerfChecker discovers `@testitem` declarations and measures selected items in worker processes. One item can both check correctness with TestItemRunner and record time and allocations with PerfChecker.

```julia
using PerfChecker, TestItemRunner
# Run from your package root in its prepared test environment.
items = discover_testitems(pwd())
result = run_testitems(pwd(); ids = [first(items["items"])["id"]])
```

The extension requires TestItemRunner 1.3.2 or later. Discovery honors `JuliaTestItems.toml` and never evaluates item bodies.

## One definition, two uses

- **Untagged** — included in both modes.
- `:perf_only` — performance only.
- `:test_only` — functional only.
- Both tags together — configuration error.

Ordinary tags remain available through `tags` and `exclude_tags`. There is no required `:perf` tag.

Until an upstream policy hook exists, functional CI applies the filter explicitly:

```julia
using TestItemRunner, PerfChecker
@run_package_tests filter=testitem_filter(:test)
```

Loading PerfChecker does not change plain TestItemRunner behavior.

## Interfaces

- **VS Code:** run **PerfChecker: Discover existing test items**, then use the **PerfChecker items** controller.
- **Oxygen:** from the package root,

  ```julia
  using PerfChecker, PerfCheckerWeb, TestItemRunner, Oxygen, HTTP
  register_testitem_routes!(pwd(); project = dirname(Base.active_project()))
  Oxygen.serve(host = "127.0.0.1", port = 8080)
  ```

  then open `/perfchecker/items/`.
- **CLI:**

  ```sh
  julia --project=. -e 'using PerfChecker, TestItemRunner; exit(perfchecker_main(ARGS))' -- testitems --root=. --list
  julia --project=. -e 'using PerfChecker, TestItemRunner; exit(perfchecker_main(ARGS))' -- testitems --root=. --tags=fast --reports=perf/results/items
  ```

  Use repeated `--item-id=...` for exact selection. Explicit selections that match nothing fail before execution.

## Measurement scope

- Each item runs once by default, in a fresh process. `samples=N` repeats it N times.
- Time and Julia allocation bytes cover the whole item: imports, setups, assertions and cleanup.
- Process startup and source discovery are outside the item timer.
- Failed, skipped or assertion-free items cannot become validated measurements.
- Allocated bytes are Julia allocations only, not native allocations or RSS.

Correctness and a performance budget are separate. Item reports do not adopt a regression threshold automatically.

## Next

For warmed operations or control over preparation, use [Shared scenarios](shared-scenarios.md).

```@raw html
<a id="Existing-TestItemRunner-items"></a>
```
