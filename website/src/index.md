```@raw html
---
layout: home

hero:
  name: "PerfChecker.jl"
  text: "Performance checks from your Julia tests"
  tagline: Run one item, inspect its measurements, and compare results with an explicit performance budget.
  image:
    src: /assets/perfchecker.svg
    alt: PerfChecker performance pulse
  actions:
    - theme: brand
      text: Start measuring
      link: /guide/first-check
    - theme: alt
      text: Use VS Code
      link: /interfaces/vscode
    - theme: alt
      text: View on GitHub
      link: https://github.com/Mirage-Interactive-Fr/PerfChecker.jl

features:
  - icon: "⚗️"
    title: Reuse existing tests
    details: Discover ordinary TestItemRunner items. Share them between correctness and performance, or separate them with tags.
    link: /test-items
  - icon: "↔️"
    title: Compare measured results
    details: Define a baseline, matching measurement scope and regression limits before deciding whether a change passes.
    link: /tutorials/comparisons
  - icon: "🔥"
    title: Investigate a regression
    details: Inspect Julia timings, allocations and profiles, then choose diagnostics for the target and its native dependencies.
    link: /native-profiling
  - icon: "▦"
    title: Run one item in VS Code
    details: Discover items in the Testing view, select a check and retain its measurements and source identity.
    link: /interfaces/vscode
  - icon: "✓"
    title: Automate the same checks
    details: Use scripts and CI with JSON, Markdown and JUnit reports. Keep execution, correctness and regression verdicts separate.
    link: /tutorials/ci
  - icon: "⌘"
    title: Reopen saved evidence
    details: Read portable run bundles in Web Studio, Pluto, plots or reports without repeating the measurement.
    link: /reference/run-bundles
---
```


```@raw html
<MaintainerLink />
<HomeMeasurements />
```

[Read the short Bibliography tutorial](tutorials/quick-tour.md) or [explore the interactive plots](interfaces/visualization.md).

## Performance checks as software tests

PerfChecker treats performance as a versioned contract attached to a **business
feature**. `import_bibtex`, `solve_model`, or `render_frame` is the feature;
BenchmarkTools, Chairmarks, allocation tracking, profiling and network accounting
are selectable ways to evaluate it. This separation keeps the suite readable and
lets every interface offer the same choices.

```text
software suite
  └─ package
      └─ business feature
          ├─ check type
          └─ target: release | working tree | branch | tag | commit
```

The controller resolves this plan, performs compatibility checks and launches
bounded workers. The measured worker loads only the target package, workload and
collector. Results return as a portable run bundle consumed by every UI and CI
adapter.

## Pick a path

```@raw html
<div class="feature-grid">
  <div><strong>I maintain one package</strong>Start with <a href="/guide/first-check">your first test item</a>, then add versions and CI.</div>
  <div><strong>I maintain a software suite</strong>Model package boundaries and version pins in <a href="/suites-and-comparisons">suites and comparisons</a>.</div>
  <div><strong>I am investigating a regression</strong>Compare <a href="/tutorials/comparisons">releases and Git revisions</a> or <a href="/tutorials/julia-runtimes">Julia runtimes</a>.</div>
  <div><strong>I need interactive analysis</strong>Choose <a href="/interfaces/vscode">VS Code</a>, <a href="/interfaces/web-studio">Oxygen</a>, or <a href="/interfaces/visualization">Makie</a>.</div>
  <div><strong>I run a hosted service</strong>Review the <a href="/operations/hosted">controller, authentication and remote-agent model</a>.</div>
  <div><strong>I build automation</strong>Consume <a href="/reference/run-bundles">run bundles</a> and <a href="/report-queries">bounded queries</a>.</div>
</div>
```

## Try a small example

Follow the [short Bibliography tutorial](tutorials/quick-tour.md) to read a real
plot, run one export check and compare nine tagged versions. You can inspect the
recorded results before installing anything.

## Take part

PerfChecker is open source. Bug reports, examples, measurement tools and clearer
documentation are all useful contributions. [Open an issue](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/issues)
or follow the [documentation contribution guide](contributing/documentation.md).

Community contributions are welcome.
