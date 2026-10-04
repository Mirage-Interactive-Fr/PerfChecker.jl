# Documentation guide

Contributions are welcome, from fixing a sentence to adding a reproducible example. Use **Edit this page**, or [open an issue](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/issues).

## Write for someone trying the tool

- Introduce the operation before its configuration.
- Show a runnable example, then explain what it does and how to read the output.
- Use familiar names: "The worker times the operation" beats "the lifecycle preserves the measurement boundary".
- Explain a technical term when it is needed.
- Keep limitations beside the operation or result they affect.

Put a plot beside each measured comparison, explain its axes, and discuss the values readers can see. Link out for more options. Keep work notes and proposed features out of the user guides.

## Local build

```sh
julia --project=website -e 'using Pkg; cd("website") do; Pkg.develop(path=".."); Pkg.instantiate(); end'
julia --project=website website/make.jl
```

Install Node.js 22.12 or newer first. The finished site is `website/build/site`. Building never deploys.

```sh
node website/preview.mjs   # browse the completed site at http://127.0.0.1:8870/
```

The build rejects missing references and dead links. The core test suite checks that every exported binding is defined and documented. Review content too: an existing docstring is not proof that its arguments are correct.

## Information architecture

- **Manual** — from a test to an operation benchmark, then results, suites, comparisons, profiling and CI.
- **Examples** — complete experiments for Bibliography, DataStructures and Oxygen.
- **Interfaces** — controls and setup for each UI.
- **Further topics** — additional measurements, larger experiments, remote execution and optional advisors.
- **Reference** — arguments, formats and integration details.
- **Contributing** — architecture, collection tests and documentation.

Keep each detailed explanation in one place and link to it elsewhere. The sidebar order comes from `website/make.jl`; update it when moving a chapter.

Before adding a code block, say whether it is a complete runnable example, a fragment using earlier variables, or a format illustration. Give the working directory and prerequisites, and name placeholder paths explicitly.

Do not present a planned collector, platform or attribution method as implemented.

## Explain a measurement before configuring it

Introduce every collector with one or two paragraphs: the question it answers, the quantity and unit it records, and how to read the result. Define terms such as wall time, GC and flame graph at first use.

- Version comparisons need several actual revisions with input and dependency provenance. A distribution from one version only shows sampling variation.
- Distinguish declared package versions, Git tags and later commits.
- Explain unavailable workloads and failed preparation; never replace them with zero.
- When two collectors expose similarly named fields, explain the difference locally (BenchmarkTools GC time vs Chairmarks GC fraction).

## Screenshots

Store images under `website/src/public/assets/screenshots/<interface>/`. Use actual application output only.

1. Capture a fixed, readable desktop size; add a narrow layout when responsive behavior matters.
2. Remove tokens, private endpoints, usernames, absolute local paths and private package data.
3. Use stable demo bundles so screenshots can be regenerated.
4. Provide descriptive alt text and a caption explaining the user outcome.
5. Prefer SVG for diagrams, PNG/WebP for UI, static Makie export for plots.
6. Verify light and dark themes when the component supports them.
7. Refresh images when labels or flows change, not every release.

## Recordings

Keep source recordings outside Git history. The local archive is `.lab/media/<recording>/`; `website/.gitignore` also excludes WebM, MP4 and MOV copies.

For publication, use an approved project recording on YouTube and set its `youtube_id` in `website/media.json`. The site loads the privacy-enhanced player only after a reader clicks the poster. This does not make YouTube tracker-free.

## Pull-request checklist

- build DocumenterVitepress locally;
- check internal and external links;
- run doctests and any TestItems the examples affect;
- verify screenshots at their rendered size;
- state which commands passed and which integrations you did not exercise.

```@raw html
<a id="Screenshot-policy"></a>
<a id="Recordings-outside-Git"></a>
```
