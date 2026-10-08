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

## Canonical publication

The canonical stable site is [perfchecker.mirageinteractive.fr](https://perfchecker.mirageinteractive.fr/).
Main updates publish development documentation under `/dev/`; stable tags
publish a version under `/vX.Y.Z/` and select the latest stable version for the
root. A delayed old tag leaves the selected newer version in place. Every
canonical channel uses `.html` page links, so plain static hosting needs no
rewrite rules. The GitHub mirror keeps its own base and version catalogue.

The Documentation workflow checks builds, navigation, search and SFTP publication
policy without publishing from a pull request. Builds never receive server
credentials, and completed exports remain downloadable if a transfer fails.
An initial main deployment updates only `/dev/` and preserves the existing
root. Register the reviewed final commit first; TagBot then creates the stable
tag that triggers version publication.

Publication uses SFTP with a pinned server key and no remote shell. Uploads
preserve existing versions and unrelated files. Individual files are replaced
through temporary-file renames; the whole tree is not changed atomically. After
an interruption, retry the same publication rather than deleting the server's
contents. The version catalogue lists channels actually published on that host.

Maintainers can find the variables, secrets, export layout, locking and recovery
procedure in the repository's
[deployment guide](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/blob/main/website/DEPLOYMENT.md).
These documentation checks do not replace the package's complete qualification.

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

```@raw html
<a id="Screenshot-policy"></a>
```

## Screenshots

Store images under `website/src/public/assets/screenshots/<interface>/`. Use actual application output only.

1. Capture a fixed, readable desktop size; add a narrow layout when responsive behavior matters.
2. Remove tokens, private endpoints, usernames, absolute local paths and private package data.
3. Use stable demo bundles so screenshots can be regenerated.
4. Provide descriptive alt text and a caption explaining the user outcome.
5. Prefer SVG for diagrams, PNG/WebP for UI, static Makie export for plots.
6. Verify light and dark themes when the component supports them.
7. Refresh images when labels or flows change, not every release.

```@raw html
<a id="Recordings-outside-Git"></a>
```

## Recordings

Keep source recordings outside Git history. The local archive is `.lab/media/<recording>/`; `website/.gitignore` also excludes WebM, MP4 and MOV copies.

For a local tutorial extract, publish its qualified MP4 as an approved release
asset and record its exact HTTPS `download_url`, `bytes` and `sha256` in
`website/media.json`. Set `embed_local` to `true` for the twenty guide extracts.
The build fetches a missing copy, checks its length and digest before writing it
under the entry's public `file` path, and refuses an existing copy with different
bytes. The normal documentation exports then include these compressed extracts.
Keep the long master outside the public tree and link to its separate deliverable.

Use AVC/AAC MP4 with faststart, a readable poster and English VTT captions. The
guide's `DocMedia` uses `video`, `recording`, `src`, `poster`, `subtitles`,
`preload="metadata"` and `short` for an extract. Provide a useful caption and,
once the master is accessible, `walkthrough` and `chapter` for the full tutorial.
Playback uses native controls and `playsinline`, with no automatic playback.
For the long master, verify the published asset's bytes/SHA first and add its
HTTPS manifest entry without `embed_local`. Set `external` on its `DocMedia`
player to stream that URL while keeping the poster and VTT in the documentation.
The MP4 stays outside every SFTP export. Test the real hosted file, including
range seeking and the local captions, before publishing its player or links.
Retain full-size screenshot links and identify candidate, fixture or recorded
measurement provenance. Verify loading, seeking, captions and fullscreen on
desktop and mobile; metadata preloading should not fetch all twenty full clips.
Place each extract beside its relevant action; use a separate index to browse
all twenty.

An explicitly approved YouTube publication can instead set `youtube_id` in the
manifest. The site loads the privacy-enhanced player only after a reader clicks
the poster. This does not make YouTube tracker-free.

## Pull-request checklist

- build DocumenterVitepress locally;
- check internal and external links;
- run doctests and any TestItems the examples affect;
- verify screenshots at their rendered size;
- state which commands passed and which integrations you did not exercise.
