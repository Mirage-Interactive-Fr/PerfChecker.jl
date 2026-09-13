```@raw html
---
layout: home

hero:
  name: "PerfChecker.jl"
  text: "Measure how your Julia code changes"
  tagline: Compare execution time and allocations across versions, then profile the operations that need attention.
  image:
    src: /assets/perfchecker.svg
    alt: PerfChecker
  actions:
    - theme: brand
      text: Quickstart
      link: /guide/first-check
    - theme: alt
      text: Explore examples
      link: /real-packages/
    - theme: alt
      text: Use VS Code
      link: /interfaces/vscode
---
```

```@raw html
<MaintainerLink />
```

## From a passing test to a performance comparison

Your tests check that a package produces the right answer. PerfChecker measures
what that answer costs. Start with an existing TestItem, or define an operation
such as importing a file or solving a model. Run it on selected versions and
inspect the changes in time and allocations.

The [manual](guide/overview.md) follows one Bibliography example through these
steps. It starts with a test, separates the export operation from its setup,
compares two revisions and uses a profile to locate expensive calls.

```@raw html
<HomeMeasurements />
```

## Use the results in your own workflow

Run checks from Julia or [VS Code](interfaces/vscode.md), select workloads in
[Web interface (Oxygen)](interfaces/web-studio.md), or explore a saved run in
[Pluto](interfaces/repl-pluto.md). The reports retain the measurements and
their settings, so changing interface does not require a new benchmark.

For larger experiments, the [DataStructures example](real-packages/datastructures.md)
compares 35 containers and the [Oxygen example](real-packages/oxygen.md)
adds HTTP and network measurements. Both include scripts and notebooks to adapt.

## Contribute

PerfChecker is open source. [Report a problem](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/issues),
[contribute an example](real-packages/contributing.md), or
[improve a page](contributing/documentation.md). The source is available
[on GitHub](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl).
