```@raw html
<a id="Existing-TestItemRunner-items"></a>
```

# Existing TestItems

PerfChecker discovers `@testitem` declarations and measures selected items in worker processes. One item can both check correctness with TestItemRunner and record time and allocations with PerfChecker.

```julia
using PerfChecker, TestItemRunner
# Run from your package root in its prepared test environment.
items = discover_testitems(pwd())
isempty(items["items"]) && error("No performance test items were discovered")
result = run_testitems(pwd(); ids = [first(items["items"])["id"]])
(discovery_executed = items["executed"], selected = length(result["runs"]),
    passed = result["passed"], performance = result["performance"])
```

For one selected item whose assertions pass, this projection has the following
contract-defined values; it is not a recorded timing:

```text
(discovery_executed = false, selected = 1, passed = true, performance = "not_compared")
```

Discovery did not execute the item. The selected run did, and its assertions
passed, but no performance budget was evaluated. Inspect
`only(result["runs"])["samples"]` for the actual `correctness`, `passes`,
`seconds` and Julia allocation `bytes` from each worker. A failing, skipped or
assertion-free item produces `passed=false`; this recipe promises no fixed timing.

The extension requires TestItemRunner 1.3.2 or later. Discovery honors `JuliaTestItems.toml` and never evaluates item bodies.

## One definition, two uses

- **Untagged** — included in both modes.
- `:check_only` (or its alias `:perf_only`) — performance only.
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

See the [recorded Bibliography item result](tutorials/bibliography.md#Reuse-the-upstream-tests-as-native-items) for a real selection: the export item passed while the other discovered item remained unrun. Its table reports the editor's elapsed time separately from the item timer's scope. The [complete round-trip example](#Complete-round-trip-example) shows a standalone item and its saved report.

## Next

For warmed operations or control over preparation, use [Shared scenarios](shared-scenarios.md).

## Complete round-trip example

Measure one existing `@testitem`. No checkout or suite file is needed.

### Install

```julia
import Pkg
Pkg.add(Pkg.PackageSpec(name = "PerfChecker", version = "1"))
Pkg.add(["Bibliography", "TestItems", "TestItemRunner"])
```

Expected effect: the active project's dependencies include all four packages. Pkg prints the resolved versions; installation does not run a check.

### Create a test

This writes one item to a temporary directory.

```julia
using PerfChecker, TestItemRunner

root = mktempdir()
write(joinpath(root, "roundtrip_test.jl"), raw"""
using TestItems

@testitem "Bibliography BibTeX round trip" tags=[:bibliography, :small] begin
    using Bibliography
    mktempdir() do directory
        input = joinpath(directory, "article.bib")
        write(input, "@article{example, title={A small example}, year={2026}}")
        entries = Bibliography.import_bibtex(input)
        exported = Bibliography.export_bibtex(entries)
        @test occursin("example", exported)
        @test occursin("A small example", exported)
    end
end
""")
```

Expected file: `roundtrip_test.jl` under the temporary `root`, containing one item named **Bibliography BibTeX round trip**. Writing it does not execute it.

In your own package, keep the declaration in `test/`.

### Find and run it

Discovery reads declarations without running them.

```julia
listing = discover_testitems(root)
item = only(listing["items"])
item["name"]
```

```text
"Bibliography BibTeX round trip"
```

Measure it:

```julia
reports = mktempdir()
result = run_testitems(root; ids = [item["id"]], samples = 1, threads = 1, reports)
(passed = result["passed"], performance = result["performance"])
```

```text
(passed = true, performance = "not_compared")
```

`not_compared` means the item ran and was measured, but was not compared with a baseline or budget.

```@raw html
<a id="Read-the-measurements"></a>
```

### Read the measurement

```julia
sample = only(only(result["runs"])["samples"])
(seconds = sample["seconds"], bytes = sample["bytes"])
```

Expected output shape (local values, not a recorded timing):

```text
(seconds = <elapsed seconds>, bytes = <Julia allocation bytes>)
```

Your numbers will differ. The measurement covers the **whole test** in a fresh worker: imports, compilation, setup, assertions and cleanup — not a warm BibTeX export.

The run is saved:

```julia
isfile(joinpath(reports, "testitems.json"))
```

Expected result after a successful save:

```text
true
```

```@raw html
<a id="Use-your-existing-tests"></a>
```

### Select from your own package

```julia
root = pwd()
listing = discover_testitems(root)
[(item["name"], item["tags"]) for item in listing["items"]]
```

Expected result: one `(name, tags)` pair per discovered declaration. The temporary example above has the name **Bibliography BibTeX round trip** and tags `:bibliography`, `:small`; your package lists its own declarations.

```julia
item = only(filter(i -> i["name"] == "Bibliography BibTeX round trip", listing["items"]))
result = run_testitems(root; ids = [item["id"]], samples = 30, threads = 1)
```

Expected result after success: one selected run with 30 samples, `passed = true`, and `performance = "not_compared"`. This selection is a recipe to execute locally; no fixed timing is promised.

The active environment must contain the package's test dependencies.


### Recorded examples

```@raw html
<p><a href="examples/bibliography/bibliography-testitems.jl" download="bibliography-testitems.jl">Download a complete Bibliography test item to adapt</a></p>
```
