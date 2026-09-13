# Quickstart: measure a test

Measure one existing `@testitem`. No checkout or suite file is needed.

## Install

```julia
import Pkg
Pkg.add(Pkg.PackageSpec(name = "PerfChecker", rev = "release/v1.0.0-rc1"))
Pkg.add(["Bibliography", "TestItems", "TestItemRunner"])
```

## Create a test

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

In your own package, keep the declaration in `test/`.

## Find and run it

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

## Read the measurement

```julia
sample = only(only(result["runs"])["samples"])
(seconds = sample["seconds"], bytes = sample["bytes"])
```

Your numbers will differ. The measurement covers the **whole test** in a fresh worker: imports, compilation, setup, assertions and cleanup — not a warm BibTeX export.

The run is saved:

```julia
isfile(joinpath(reports, "testitems.json"))
```

## Select from your own package

```julia
root = pwd()
listing = discover_testitems(root)
[(item["name"], item["tags"]) for item in listing["items"]]
```

```julia
item = only(filter(i -> i["name"] == "Bibliography BibTeX round trip", listing["items"]))
result = run_testitems(root; ids = [item["id"]], samples = 30, threads = 1)
```

The active environment must contain the package's test dependencies.


## Recorded examples

```@raw html
<p><a href="../examples/bibliography/bibliography-testitems.jl" download="bibliography-testitems.jl">Download a complete Bibliography test item to adapt</a></p>
```

## Next

- To time export alone, with input preparation outside the timer, read [Measure an operation](../tutorials/quick-tour.md).
- To interpret time, allocations and GC, read [Understand the result](understanding-measurements.md).

```@raw html
<a id="Read-the-measurements"></a>
<a id="Use-your-existing-tests"></a>
```
