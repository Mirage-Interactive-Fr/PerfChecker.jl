# Documentation guide

Documentation contributions are welcome, from fixing an unclear sentence to
adding a reproducible example. Use **Edit this page** to suggest a change, or
[open an issue](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/issues)
with the page address and the step that was difficult to follow.

## Write for someone trying the tool

Introduce the operation before its configuration. Show a runnable example,
then explain what the code does and how to read its output. The Julia manual's
[profiling chapter](https://docs.julialang.org/en/v1.14-dev/manual/profile/)
is a useful example of this sequence.

Use familiar names and concrete statements: “The worker times `operation`”
is clearer than “The lifecycle preserves the measurement boundary.” Explain
technical terms when they are needed. Keep limitations beside the operation
or result they affect, rather than repeating general warnings in every section.

Use [Bibliography](../tutorials/quick-tour.md), [DataStructures](../real-packages/datastructures.md)
or [Oxygen](../real-packages/oxygen.md) for examples. Put a plot beside each
measured comparison, explain its axes and discuss the values readers can see.
Link to a reference for additional options. Keep work notes and proposed
features outside the user guides.

## Local build

```sh
julia --project=website -e 'using Pkg; cd("website") do; Pkg.develop(path=".."); Pkg.instantiate(); end'
julia --project=website website/make.jl
```

Install Node.js 22.12 or newer first. The build uses the system Node runtime and
writes the static site to `website/build/site`. DocumenterVitepress writes intermediate
Markdown; the explicit VitePress step makes a missing Windows HTML build fail.
Building never deploys. The independent documentation workflow publishes development pages after building them. Package qualification runs separately and never blocks documentation publication.

Run `node website/preview.mjs` to browse the completed site locally. The preview
keeps a snapshot so another build cannot interrupt readers. Restart the preview
after a successful build to display its new pages.

The build rejects missing references and dead links. The core test suite checks
that every exported binding is defined and documented. Review the content too:
an existing docstring is not proof that its arguments and guarantees are correct.

## Information architecture

- **Manual** follows Bibliography from a test to an operation benchmark, then
  explains the results, suites, comparisons, profiling and CI. Each chapter
  continues the previous one; its ending points to the next operation.
- **Examples** develops complete experiments for Bibliography, DataStructures
  and Oxygen, with saved measurements and runnable notebooks.
- **Interfaces** describes the controls and setup for each UI.
- **Further topics** covers additional measurements, larger experiments,
  remote execution and optional advisors.
- **Reference** documents arguments, formats and integration details.
- **Contributing** covers architecture, collection tests and documentation.

Keep each detailed explanation in one place and link to it from other pages.
The sidebar and previous/next links come from `website/make.jl`; update their
order when moving a chapter. Follow the approaches used by the
[Julia manual](https://docs.julialang.org/en/v1.14-dev/),
[JuMP tutorials](https://jump.dev/JuMP.jl/stable/tutorials/getting_started/getting_started_with_JuMP/)
and [Julia Constraints introduction](https://juliaconstraints.github.io/dev/cp/30_getting_started):
introduce a problem, add the concepts needed to solve it, and inspect the result.

Before adding a code block, say whether it is a complete runnable example, a
fragment using earlier variables, or a format illustration. Give the working
directory, prerequisites and expected output. Name placeholder paths explicitly.
Link to the step that creates an input file before asking the reader to use it.

Do not duplicate feature claims across pages without linking to the canonical
reference. Never present a planned collector, platform, or attribution method as
implemented.

## Explain a measurement before configuring it

Introduce every collector with one or two paragraphs explaining the question it
answers, the quantity and unit it records, and how to read the result. Define
terms such as wall time, GC and flame graph at first use or link directly to
the [measurement tutorial](../guide/understanding-measurements.md). A table of
option names alone is not an introduction.

Use Bibliography for the worked examples. Version comparisons must contain
several actual revisions, with input and dependency provenance; a distribution
from one version only demonstrates sampling variation. Distinguish declared
package versions, Git tags and later commits. Explain unavailable workloads and
failed preparation without replacing them with zero-valued measurements.

When two collectors expose similarly named fields, explain their differences
locally: BenchmarkTools GC time and Chairmarks GC fraction have different units,
and CPU samples, task wall-time stacks and elapsed benchmark times answer
different questions. Add a reading paragraph beside an interactive plot so the
reader can interpret it without opening a separate reference page.

## Screenshot policy

Store images under `website/src/public/assets/screenshots/<interface>/` or a similarly
specific folder. Use actual application output only—never a fabricated UI—and:

1. capture a fixed, readable desktop size and an additional narrow layout when
   responsive behavior matters;
2. remove tokens, private endpoints, usernames, local absolute paths, and private
   package data;
3. use stable demo bundles so screenshots can be regenerated;
4. provide descriptive alt text and a caption that explains the user outcome;
5. prefer SVG for diagrams, PNG/WebP for UI, and static Makie export for plots;
6. verify both light and dark themes when the component supports them;
7. refresh images when labels or flows change, not merely on every release.

Use the `doc-screenshot` figure class for consistent borders and captions.

The lightweight figures beside the tutorials are generated from the public
recorded JSON files. To regenerate them, install the optional plotting dependency
and run the exporter from the repository root:

```sh
python -m pip install -r website/scripts/plot-requirements.txt
python website/scripts/render-measured-plots.py
```

This redraws saved measurements without launching benchmarks. The exporter
records its input digests in `examples/bibliography/figures/provenance.json`
under the site's public directory. Interactive Makie exports remain separate;
their own download links contain the same historical measurements.

## Recordings outside Git

Keep source recordings outside the Git history. The local archive is
`.lab/media/<recording>/`; `website/.gitignore` also excludes WebM, MP4 and MOV
copies used by the preview. Screenshots, captions, the written walkthrough and
`website/media.json` remain versioned. The catalogue records the original
file's byte count and SHA-256 digest.

For publication, use an approved project recording on YouTube for the embedded
player. Set the recording's `youtube_id` in `website/media.json` after uploading
and reviewing the video and its captions. The site loads the privacy-enhanced
YouTube player only after the reader clicks its poster. This mode does not make
YouTube a tracker-free service; see the
[YouTube embedding documentation](https://support.google.com/youtube/answer/171780?hl=en).

The Bibliography originals and English captions are available in the [documentation recordings release](https://github.com/Mirage-Interactive-Fr/Mirage-Interactive-Fr.github.io/releases/tag/documentation-media-v1). Attach further originals to a GitHub Release and put its HTTPS URL in
`download_url`. Release attachments distribute binaries separately from the Git
history. GitHub Actions artifacts are useful for temporary test captures, but
their retention period makes them unsuitable as permanent documentation media.
See [GitHub releases](https://docs.github.com/en/repositories/releasing-projects-on-github/about-releases)
and [artifact retention](https://docs.github.com/en/organizations/managing-organization-settings/configuring-the-retention-period-for-github-actions-artifacts-and-logs-in-your-organization).

Until the video is published, a local build can read an ignored copy at the
catalogue's `file` path beneath `website/src/public/`. The build verifies its
size and digest. A clean checkout without that file shows the poster and a
written-walkthrough fallback, with no broken video request. The browser tests
check whichever state the build actually contains; they do not claim to test
YouTube playback when no published video is configured.

The opt-in `qualification/shared/bibliography-web.mjs` script records a real
run; the ordinary documentation tests replay its video without launching Julia
measurement workers. Neither workflow uploads media or publishes the site.

## Pull-request checklist

- build DocumenterVitepress locally;
- check internal and external links;
- run doctests and package TestItems affected by examples;
- verify screenshots at their rendered size;
- scan for stale organization/repository identities;
- state which commands passed and which optional integrations were not exercised.
