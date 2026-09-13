```@raw html
---
layout: home

hero:
  name: "PerfChecker.jl"
  text: "Measure how Julia code changes"
  tagline: Compare time and allocations across versions, then profile what got slower.
  image:
    src: /assets/perfchecker.svg
    alt: PerfChecker
  actions:
    - theme: brand
      text: Quickstart
      link: /guide/first-check
    - theme: alt
      text: Examples
      link: /real-packages/
    - theme: alt
      text: Use VS Code
      link: /interfaces/vscode
features:
  - title: Measure a test
    details: Run an existing TestItem and inspect its time and allocations.
    link: /guide/first-check
    linkText: Try the quickstart
  - title: Compare versions
    details: Measure the same operation across releases or Git revisions.
    link: /tutorials/comparisons
    linkText: Compare results
  - title: Find expensive calls
    details: Inspect CPU, wall-time and allocation profiles from saved runs.
    link: /guide/investigate
    linkText: Read a profile
  - title: Choose an interface
    details: Work in Julia, VS Code, Oxygen or Pluto with the same results.
    link: /interfaces/packages
    linkText: Explore interfaces
---
```

```@raw html
<MaintainerLink />
```


## What it does

- Runs existing Julia `@testitem`s, or operations you define.
- Measures in a separate worker process, so the UI is not measured.
- Saves results as portable run bundles. Every interface reads the same files.
- Compares releases, Git revisions and Julia runtimes.
- Profiles CPU, wall time and allocations when a timing changes.

```@raw html
<HomeMeasurements />
```

## Where to start

- New here? Read [Introduction](guide/overview.md), then [Installation](guide/installation.md).
- Have a test? [Quickstart: measure a test](guide/first-check.md).
- Have an operation? [Measure an operation](tutorials/quick-tour.md).
- Want to compare? [Suites and comparisons](suites-and-comparisons.md).

## Interfaces

- [VS Code](interfaces/vscode.md) — run one item while editing.
- [Web interface (Oxygen)](interfaces/web-studio.md) — select workloads in a browser.
- [REPL and Pluto](interfaces/repl-pluto.md) — terminal, or an editable notebook.
- [Plots](interfaces/visualization.md) — Makie figures from saved runs.

## Examples

- [Bibliography](tutorials/bibliography.md) — the manual's running example, extended.
- [DataStructures](real-packages/datastructures.md) — 35 containers over eight years.
- [Oxygen](real-packages/oxygen.md) — HTTP handlers and real network traffic.

## Contribute

[Report a problem](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/issues),
[improve a page](contributing/documentation.md), or open a pull request.

```@raw html
<a id="From-a-passing-test-to-a-performance-comparison"></a>
<a id="Use-the-results-in-your-own-workflow"></a>
```
