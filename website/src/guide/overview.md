# Your first comparison

PerfChecker measures the same operation across package versions and keeps the conditions with the result. Install Core in a Julia project:

```julia
] add PerfChecker
```

For this benchmark, also run `] add BenchmarkTools`. The figure needs [PerfCheckerMakie and WGLMakie](../interfaces/visualization.md#Customize-and-export-Makie-figures); they are optional, separate installations.

```julia
using PerfChecker, BenchmarkTools
config = PerfConfig(:benchmark; path = dirname(Base.active_project()),
    pkgs = ("Bibliography", :custom, [v"0.3.1", v"0.4.0"], false),
    include_current = false, samples = 50, evals = 1, seconds = 1.0)
result = @check config begin
    using Bibliography
    entries = Bibliography.import_bibtex(
        "@article{example, title={A small example}, author={Ada Lovelace}, " *
        "journal={Julia Studies}, year={2026}}\n")
end begin
    Bibliography.export_bibtex(entries)
end
using PerfCheckerMakie, WGLMakie
WGLMakie.activate!()
checkres_to_scatterlines(result, Val(:benchmark))
```

Preparation parses one entry once outside the timed export; the read-only benchmark reuses it. Two released versions are measured with fifty samples each; dependencies resolve for each release. This compares complete resolved stacks, not an isolated source change.

```@raw html
<NormalizedMeasurements source="/examples/bibliography/first-comparison/normalized.json" html="/examples/bibliography/first-comparison/normalized.html" package-name="Bibliography · first comparison" />
```

The recorded example uses exactly this workload: Linux, Julia 1.13.1, BenchmarkTools 1.7.0. Release 0.4.0 has lower minimum time but higher allocated bytes and allocation count. Four curves overlay each metric's minimum divided by its minimum across the two versions; 1 is the reference, and equal zeros are shown at 1. Inspect a point for its original value, unit and capture conditions. A lower minimum alone does not prove an improvement.

Continue with [a focused investigation](../tutorials/comparisons.md), then [a suite and CI](../software-suites.md). [Installation details](../interfaces/packages.md#Installation) and [measurement definitions](../measurement-model.md) remain available as references.
```@raw html
<a id="Introduction"></a><a id="introduction"></a><a id="The-problem"></a><a id="the-problem"></a><a id="The-workflow"></a><a id="the-workflow"></a><a id="What-runs,-and-where"></a><a id="what-runs,-and-where"></a><a id="Start"></a><a id="start"></a><a id="Measure-safely"></a><a id="measure-safely"></a>
```
