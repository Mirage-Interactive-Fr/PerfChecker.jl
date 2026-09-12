# Your first result

Measure a test your package already owns. This walkthrough uses the V1
TestItemRunner integration; check [installation and V1 availability](installation.md)
first. No generated suite or separate performance source file is required.

Start Julia at your package's root, in an environment containing PerfChecker,
TestItemRunner and the dependencies needed by your tests. If you already have
items, go straight to **Find an existing item**. Otherwise, try the complete
Bibliography item below.

## Start from a downloadable item

This example imports one BibTeX article, exports it, and checks that its key and
title survive. It uses Bibliography's public API and contains its own tiny input.
It needs no upstream source checkout or generated suite.

```@raw html
<p><a href="../examples/bibliography/bibliography-testitems.jl" download="bibliography-testitems.jl"><strong>Download the complete Bibliography test item</strong></a></p>
```

Save the file as `test/bibliography-testitems.jl` in your package. Add
`Bibliography`, `TestItems` and `TestItemRunner` to the environment in which you
will run this example, alongside PerfChecker. These are example/test dependencies;
Bibliography is not required to measure your own package.

```julia
import Pkg
Pkg.add(["Bibliography", "TestItems", "TestItemRunner"])
```

Start Julia with that environment active. The following steps also work if you
put the downloaded file in an otherwise empty example directory and use that
directory as `root`.

## Find an existing item

```julia
using PerfChecker, TestItemRunner

root = pwd()
listing = discover_testitems(root)
[(item["name"], item["tags"]) for item in listing["items"]]
```

Discovery reads declarations without executing their bodies. It includes
ordinary shared tests and `:perf_only` items, and excludes `:test_only`.
If the list is empty, check the package root and discovery configuration.
A package using only `@testset` has no TestItems to discover automatically.
The [Bibliography example](../tutorials/bibliography.md#Reuse-the-upstream-tests-as-native-items)
shows thin declarations that reuse upstream tests without copying them.

## Measure one item

Choose an item from the listing. For the downloaded example, select its name
explicitly so other tests in your package are not run:

```julia
item = only(filter(item -> item["name"] == "Bibliography BibTeX round trip",
    listing["items"]))
result = run_testitems(root; ids=[item["id"]], samples=1, threads=1)
result["passed"]
```

For one of your existing items, replace the name with one from the listing.
`only` deliberately reports an error if no item or several items match.
Successful execution returns `true` for the final expression.

One fresh worker runs one sample. The environment must already contain the test
dependencies: measurement does not install packages while timing a test.
The duration includes imports, setup and assertions, with no hidden warmup.
It measures the whole item, not just one operation inside it.

## Read and save the result

```julia
only(result["runs"])["samples"]
result["performance"]
```

The samples contain measurements and their provenance. `passed=true` means the
assertions passed; `performance="not_compared"` means no regression budget or
measured baseline was evaluated. The [measurement guide](understanding-measurements.md)
explains duration, allocation bytes and GC.

Saving is optional. To retain the next run, choose a new report directory:

```julia
saved = run_testitems(root; ids=[item["id"]], samples=1, threads=1,
    reports=joinpath(root, "results", "first-item"))
```

This executes the item again and writes `testitems.json`. An existing report
is protected from replacement. The report directory is output, not an
installation prerequisite.

## Adapt the item to your package

Keep the `@testitem` declaration and assertions. Replace `using Bibliography`,
the fixture and the import/export calls with a representative operation from
your package. Give the item a name describing that operation. The ordinary tags
`:bibliography` and `:small` are just selectors; choose your own.

The same item works in functional TestItemRunner runs and PerfChecker runs.
Add `:perf_only` only when you intentionally want to exclude it from functional
runs that apply PerfChecker's filter. See [tag behavior](../test-items.md).
To time export alone with preparation outside the measurement, continue to the
[small benchmark tutorial](../tutorials/quick-tour.md). Its measurement boundary
differs from the full round-trip test above.

## Choose the next operation

The [test-item guide](../test-items.md) covers tags and scripts. In VS Code, use
**PerfChecker: Discover existing test items**, then run one item in the Testing
view with the same prepared Julia environment.

For a complete recorded example across interfaces, follow
[Bibliography](../tutorials/bibliography.md). Define a
[software suite](../software-suites.md) only when you need custom workloads,
separate preparation or version comparisons beyond the existing items.
