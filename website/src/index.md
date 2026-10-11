```@raw html
---
layout: home

hero:
  name: "PerfChecker.jl"
  text: "Measure how Julia code changes"
  tagline: Compare time and allocations across versions, then profile what got slower.
  image:
    src: /assets/perfchecker-mark.png
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


```@raw html
<a id="From-a-passing-test-to-a-performance-comparison"></a>
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

```@raw html
<a id="Use-the-results-in-your-own-workflow"></a>
```

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

## Built with the Julia community

PerfChecker.jl brings together work from many projects. We thank their maintainers,
contributors, and the Julia community for making these workflows possible.

- **Measure and profile:** [BenchmarkTools](https://github.com/JuliaCI/BenchmarkTools.jl)
  and [Chairmarks](https://github.com/LilithHafner/Chairmarks.jl) provide timing and
  allocation measurements. Julia's [Profile and Profile.Allocs](https://docs.julialang.org/en/v1/stdlib/Profile/)
  provide stack profiles; [CoverageTools](https://github.com/JuliaCI/CoverageTools.jl)
  supports line-level allocation analysis.
- **Check correctness and investigate:** [TestItems](https://github.com/julia-testitems/TestItems.jl)
  and [TestItemRunner](https://github.com/julia-testitems/TestItemRunner.jl) define and run checks;
  [PropCheck](https://github.com/Seelengrab/PropCheck.jl) and
  [Supposition](https://github.com/Seelengrab/Supposition.jl) supply generated cases
  that PerfChecker freezes into repeatable corpora. Optional analyzers
  [JET](https://github.com/aviatesk/JET.jl), [AllocCheck](https://github.com/JuliaLang/AllocCheck.jl),
  [SnoopCompile](https://github.com/JuliaDebug/SnoopCompile.jl), and
  [Aqua](https://github.com/JuliaTesting/Aqua.jl) examine inference, allocation paths,
  compilation, and package quality.
- **Choose an interface:** [VS Code](https://code.visualstudio.com/) and the
  [MCP community](https://modelcontextprotocol.io/) support editor and agent workflows.
  [Pluto](https://github.com/JuliaPluto/Pluto.jl) and [PlutoUI](https://github.com/JuliaPluto/PlutoUI.jl)
  support reactive notebooks; [Oxygen](https://github.com/OxygenFramework/Oxygen.jl)
  and [HTTP](https://github.com/JuliaWeb/HTTP.jl) support the Web interface.
  [Makie](https://github.com/MakieOrg/Makie.jl), its CairoMakie and WGLMakie backends,
  and [Bonito](https://github.com/SimonDanisch/Bonito.jl) support interactive views and graphical exports;
  [UnicodePlots](https://github.com/JuliaPlots/UnicodePlots.jl) and
  [Tachikoma](https://github.com/kahliburke/Tachikoma.jl) support terminal views.
- **Preserve and share evidence:** [Malt](https://github.com/JuliaPluto/Malt.jl)
  supplies isolated workers, [DrWatson](https://github.com/JuliaDynamics/DrWatson.jl)
  supports experiment storage, and [FlameGraphs](https://github.com/timholy/FlameGraphs.jl)
  and [PProf](https://github.com/JuliaPerf/PProf.jl) support profile export.
- **Configure and qualify:** [Preferences.jl](https://github.com/JuliaPackaging/Preferences.jl)
  supports project-local defaults in PerfChecker 1.1.0 and later.
  [PkgEval.jl](https://github.com/JuliaCI/PkgEval.jl) and the
  [JuliaCI community](https://github.com/JuliaCI) support package qualification
  in isolated test environments; PkgEval is not a performance-measurement backend.
- **Explore optional workloads and counters:** [LinuxPerf](https://github.com/JuliaPerf/LinuxPerf.jl)
  and [LIKWID](https://github.com/JuliaPerf/LIKWID.jl) support hardware-counter companions.
  Julia Threads and Distributed, [Dagger](https://github.com/JuliaParallel/Dagger.jl),
  [KernelAbstractions](https://github.com/JuliaGPU/KernelAbstractions.jl), and
  [CUDA](https://github.com/JuliaGPU/CUDA.jl) support scenarios when supplied by the workload.
- **Document the results:** [Documenter](https://github.com/JuliaDocs/Documenter.jl),
  [DocumenterVitepress](https://github.com/LuxDL/DocumenterVitepress.jl), and
  [VitePress](https://vitepress.dev/) power these guides and API references.

```@raw html
<details><summary>Additional foundations</summary>
<p>Core's data and source handling also depend on
<a href="https://github.com/JuliaData/CSV.jl">CSV</a>,
<a href="https://github.com/m-j-w/CpuId.jl">CpuId</a>,
<a href="https://github.com/JuliaIO/JSON.jl">JSON</a>,
<a href="https://github.com/JuliaLang/JuliaSyntax.jl">JuliaSyntax</a>,
<a href="https://github.com/JuliaData/TypedTables.jl">TypedTables</a>, and
<a href="https://github.com/JuliaData/YAML.jl">YAML</a>.
We also thank the <a href="https://julialang.org/">Julia language</a>, compiler,
runtime, and standard-library maintainers, including those of Base64, Dates,
Downloads, Libdl, Pkg, Profile, Random, SHA, TOML, and UUIDs.</p>
<p>Development-only tests also use
<a href="https://github.com/invenia/Intervals.jl">Intervals</a>,
<a href="https://github.com/JuliaConstraints/PatternFolds.jl">PatternFolds</a>,
and Julia's Test, Logging, and Sockets libraries.</p>
</details>
```

Optional integrations require their packages; hardware and platform support vary.
Thank you to everyone who builds, documents, tests, and maintains these tools.
