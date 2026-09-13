# Quickstart: measure a test

This example measures a Bibliography import/export test. Copy the blocks into
the same Julia session. No PerfChecker checkout or suite definition is needed.

## Install

In the Julia environment you want to use:

```julia
import Pkg
Pkg.add(Pkg.PackageSpec(name="PerfChecker", rev="release/v1.0.0-rc1"))
Pkg.add(["Bibliography", "TestItems", "TestItemRunner"])
```

These pages use the V1 release candidate; see [installation](installation.md)
for the stable release and optional interfaces.

## Create a test

The block below writes one `@testitem` into a temporary directory. The test
imports an article, exports it to BibTeX and checks that its title survives.

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
""");
```

Keep this declaration in your package's `test/` directory when adapting it.
For this trial, `root` is temporary and does not modify your package.

## Find and run it

```julia
listing = discover_testitems(root)
item = only(listing["items"])
item["name"]
```

```text
"Bibliography BibTeX round trip"
```

Discovery reads the declaration without running the test. Now measure it:

```julia
reports = mktempdir()
result = run_testitems(root; ids=[item["id"]], samples=1, threads=1, reports)
(passed=result["passed"], performance=result["performance"])
```

```text
(passed = true, performance = "not_compared")
```

The assertions passed. `not_compared` means we have a measurement, but have not
compared it with another version or a performance budget.

## Read the measurements

```julia
sample = only(only(result["runs"])["samples"])
(seconds=sample["seconds"], bytes=sample["bytes"])
```

One recorded run (Windows, Julia 1.13.0, Bibliography 0.4.0):

```text
(seconds = 6.5892513, bytes = 249498047)
```

Your numbers will differ. This measures the **whole test**, including imports,
compilation during the test, setup, assertions and module cleanup, in a fresh
worker. It is not the cost of a warm BibTeX export. One sample is enough to try
the API; use repeated measurements for a performance comparison.

The run is already saved:

```julia
isfile(joinpath(reports, "testitems.json"))
```

```text
true
```

`reports` is a temporary directory in this example. To keep future runs, pass
a new directory of your choice to `reports`; existing reports are protected
from replacement.

## Use your existing tests

Set `root` to your package directory and select one of its TestItems by name:

```julia
root = pwd()  # Start Julia at your package's root.
listing = discover_testitems(root)
[(item["name"], item["tags"]) for item in listing["items"]]
```

Replace the name below with one from that listing:

```julia
item = only(filter(item -> item["name"] == "Bibliography BibTeX round trip",
    listing["items"]))
result = run_testitems(root; ids=[item["id"]], samples=30, threads=1)
```

This runs the selected test 30 times, each in a fresh process, sequentially.
The active environment must contain its test dependencies. Discovery includes
shared tests and `:perf_only` items, and excludes `:test_only`; see
[TestItems and tags](../test-items.md). A package using only `@testset` needs
TestItem declarations before this discovery can find its tests.

```@raw html
<p><a href="../examples/bibliography/bibliography-testitems.jl" download="bibliography-testitems.jl">Download a complete Bibliography test item to adapt</a></p>
```

To measure export alone, with input preparation outside the timer, continue to
[measure an operation](../tutorials/quick-tour.md). For the meaning of time,
allocations and GC, read [understand the result](understanding-measurements.md).
