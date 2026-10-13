# Contributing

Fix code, improve a page or contribute a reproducible experiment. Start with a focused [issue](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/issues) or pull request explaining the problem, expected behavior and checks you actually ran.

## Code and bug reports

Include the Julia/PerfChecker versions, operating system, selected interface or collector, a minimal input and the complete error. For a measurement problem, retain the workload, oracle, units, sample settings and relevant bundle provenance. Remove secrets before sharing reports.

Keep changes focused and follow the repository's SciML JuliaFormatter style. Add a regression test for changed behavior; update its docstring and runnable example. Test the affected package in its own environment. A companion or native-tool result does not qualify every interface or platform. Say which checks could not run.

The project follows [ColPrac](https://github.com/SciML/ColPrac)'s constructive review and focused contribution principles. Prefer review by another maintainer. A sole maintainer may self-review after recording the change and validation; identify that exception explicitly. Registration and publication remain separate maintainer actions after review.

## Documentation

Explain the operation, show runnable code, then describe the real output and its limits. Put saved plots beside the comparison they explain; keep collection out of documentation builds. Use an existing example's data when illustrating behavior, and distinguish unavailable tools from successful measurements.

::: details Build and inspect the documentation locally

Use the checkout's supported Julia version and Node.js **22.12 or newer**. The website and each companion API have separate projects. First follow the repository's [optional API preparation and rendering instructions](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/blob/2cf431eb5a84f05e0af1098b7f6e5db84d479288/website/optional-api/README.md). They prepare all six isolated environments, render real docstrings and produce receipts for the checkout's exact revision. `website/make.jl` rejects absent, stale or mixed exports.

Then prepare the website project and build once:

```sh
julia --project=website -e 'using Pkg; cd("website") do; Pkg.develop(path=".."); Pkg.instantiate(); end'
julia --project=website website/make.jl
node website/preview.mjs
```

Open `http://127.0.0.1:8870/`. The completed site is `website/build/site`; `make.jl` already runs VitePress. The local working-tree procedure in the API README is needed when previewing edited package sources. Building does not publish.

Inspect changed pages, links, search, mobile layout and downloadable examples. The build checks docstrings and references; a successful build still needs a content review.

:::

## Contribute an example

Start with a small lifecycle: prepare deterministic input, perform one meaningful operation and verify it independently. Keep the oracle and preparation outside timing. Test correctness before collecting measurements; start with a small explicit selection.

Include package versions or immutable revisions, dependency manifests, fixture code and seed/frozen inputs, Julia/OS/machine/thread settings, collector and units, sample count and raw observations or a bundle. Explain the baseline and any repeated confirmation. Report failed and unavailable checks alongside successful ones.

Generate plots from those saved observations. A version comparison needs at least two recorded targets; latest-release profiles explain one workload and must keep their fixture size visible. Supply a downloadable Pluto notebook that prepares its dependencies and source without a repository checkout, opens in Pluto's browser UI and starts workers only after an explicit action.

Keep large recordings or bundles at a durable download location. A code or notebook change belongs in the same focused pull request as its explanation and validation. [Bibliography](../tutorials/bibliography.md), [DataStructures](../real-packages/datastructures.md) and [Oxygen](../real-packages/oxygen.md) show complete experiments.

## Read qualification results

Core, companions and external tools are tested in separate environments. Inspect each selected lane's exact source, runtime, environment and verdict; missing or failed lanes cannot be filled from another campaign. Routine targeted tests do not establish a complete release collection, and a documentation build does not qualify the packages it describes.

[PkgEval](../tools/pkgeval.md) tests an installed package in a Linux sandbox. Match its source kind, registered tree or candidate revision and Julia configuration before interpreting the result. It is a compatibility test rather than a benchmark comparison.
