# Documentation guide

Contributions are welcome, from fixing a sentence to adding a reproducible example. Use **Edit this page**, or [open an issue](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/issues).

## Work together

PerfChecker adopts the practical contribution principles of
[ColPrac](https://github.com/SciML/ColPrac): focused pull requests, constructive
review, documented changes and passing checks. Discuss a large API or workflow
change in an issue before implementing it. Describe the problem, the resulting
behavior and the checks you actually ran; identify platforms or integrations
you could not exercise.

Follow the surrounding code and the repository's JuliaFormatter configuration,
which uses the SciML style. Keep unrelated formatting out of the pull request.
Add regression tests for a behavior change, update docstrings and examples when
an API changes, and build the documentation when editing a guide. A fast result
still needs an independent correctness check and reproducible measurement
conditions. Use semantic versioning when assessing compatibility.

Review the proposed change before merging and let the required CI checks pass;
do not bypass them to resolve a failing check. Prefer review by someone other
than the author when another maintainer is available. ColPrac's independent
approval rule is not guaranteed here: a sole maintainer may review and merge
their own change after recording its scope and validation in the pull request.
State that exception plainly rather than presenting self-review as independent
approval. Address review comments respectfully and keep fixes easy to inspect.

Package registration remains a deliberate maintainer action after reviewing
the final commit. TagBot creates the release tag after registration; a merged
pull request or successful development deployment does not make a registered
release. See the publication procedure below for documentation channels.

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

## Register Core and its companions

Registration is a human maintainer action on the reviewed final commit, after
the required checks and documented installation paths pass. Registering Core
does not register the six packages under `packages/`. They currently await
their first General registrations; a version in a source `Project.toml` alone
does not make `Pkg.add("CompanionName")` available.

These packages have independent versions:

| Package | Version | Registrator subdirectory |
| --- | --- | --- |
| PerfChecker | 1.0.1 | Repository root |
| PerfCheckerLinuxPerf | 1.0.1 | `packages/PerfCheckerLinuxPerf` |
| PerfCheckerLIKWID | 1.0.1 | `packages/PerfCheckerLIKWID` |
| PerfCheckerMakie | 1.0.1 | `packages/PerfCheckerMakie` |
| PerfCheckerPluto | 1.0.1 | `packages/PerfCheckerPluto` |
| PerfCheckerTachikoma | 1.0.1 | `packages/PerfCheckerTachikoma` |
| PerfCheckerWeb | 1.0.0 | `packages/PerfCheckerWeb` |

First, the maintainer comments `@JuliaRegistrator register` on that final
commit and waits for Core 1.0.1 to appear in General. Then the maintainer requests
each companion separately on its reviewed source commit, using
`@JuliaRegistrator register subdir=packages/PerfCheckerMakie`, for example,
and the corresponding path from the table. Register Makie before Tachikoma's
optional Makie integration. Review each registry pull request and its package
installation checks; new-package registration is distinct from a Core update.
Each package subtree includes its own copy of the repository's MIT license.

The existing TagBot workflow handles the root and each subdirectory separately.
It creates `v1.0.1` for Core and namespaced tags such as
`PerfCheckerMakie-v1.0.1` and `PerfCheckerWeb-v1.0.0` for the companions. Do not
replace an existing tag. DrWatson and DocumenterVitepress integrations are Core
extensions of separately maintained dependencies, not additional PerfChecker
packages to register.

After registration, verify the documented named installations in fresh
projects and verify the actual tagged documentation before publishing an
extension release that requires them. A repository-subdirectory installation
from Core's tag can use the companion source before its separate registration;
it does not imply that the companion is available by name in General.

See the official [Registrator subdirectory procedure](https://github.com/JuliaRegistries/Registrator.jl#registering-a-package-in-a-subdirectory),
[TagBot monorepo configuration](https://github.com/JuliaRegistries/TagBot#subpackage-configuration)
and [General registration checks](https://juliaregistries.github.io/RegistryCI.jl/stable/guidelines/).

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

New walkthroughs form a YouTube playlist: a short introduction followed by
thematic chapters, split into independent videos when a topic needs more room.
Shorts answer one useful question about a backend, interface or feature. Their
number follows the content; there is no fixed clip quota. Compose portrait
shots separately, with readable controls and plots.

Start with the result readers want to understand, then explain one action before
showing it. Use natural English narration, quiet music and enough silence to
read a reply, plot or completed action. Keep axes, units and qualification
visible. Identify candidate builds, controlled replies and actual measurements
accurately. A recorded control test is not a real-package agent conversation.

After the owner publishes and verifies a video, set its real `youtube_id` in
`website/media.json`. Use the existing `DocMedia` recording entry with a readable
poster, descriptive caption and relevant chapter link. The privacy-enhanced
YouTube player loads only after the reader clicks the poster; it is not
tracker-free. Opening a documentation page must start no playback and request
no MP4 or YouTube player. Keep new MP4s out of the public tree and SFTP exports;
do not set `embed_local` for the new playlist or Shorts.

Provide English captions and inspect them against the spoken track. Check the
published player, captions, seeking, fullscreen and text size on desktop and
mobile. Preserve full-size screenshot links and the source of every measured
figure. Put a useful Short beside its action and link the playlist from the
recordings index. The guide must still contain the complete commands, steps and
interpretation for someone who never plays a video.

Existing local clips and their verified release-asset manifest entries remain
historical examples. When maintaining one, retain its exact HTTPS
`download_url`, `bytes` and `sha256`; the build rejects changed bytes. Use
`preload="none"` and explicit playback. Do not present the earlier long master
as the qualified walkthrough for the new series.

## Pull-request checklist

- build DocumenterVitepress locally;
- check internal and external links;
- run doctests and any TestItems the examples affect;
- verify screenshots at their rendered size;
- state which commands passed and which integrations you did not exercise.
