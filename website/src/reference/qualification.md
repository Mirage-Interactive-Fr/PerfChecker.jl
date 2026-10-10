# Qualified collections

A PerfChecker release is used with interface packages, Julia versions and external tools. `PerfCheckerQualification` checks an explicit candidate collection; one passing test cannot cover every combination.

```@raw html
<a id="What-is-tested-after-a-change"></a>
```

## What runs after a change

- Routine CI checks changed interfaces and their consumers with current dependencies on Linux.
- Core changes also check Windows and the minimum supported Julia version.
- Shared contracts and style checks accompany the selected components.
- The optional Supposition corpus backend has a separate 64-bit environment:
  routine checks run it on Linux, and extended checks also run it on Windows.
- Core, contract and unknown-path changes conservatively select every component.
- The extended Windows/Linux matrix runs weekly or on request with `full`, adding older dependency combinations and broader platform coverage.

Only the extended matrix can qualify a release. Passing routine CI is not a substitute. Each lane records its runtime and resolved dependency environment.

## Candidate versus qualified

- `qualification/collection.toml` selects candidates.
- External repositories use full commit SHAs; mutable branches are rejected.
- A dependency-update PR proposes a new candidate and triggers qualification. Until it passes, the last qualified collection stays the published reference.

Each attempt has its own campaign ID. Missing jobs cannot be filled with reports from an earlier attempt, even at the same revision. Failed, cancelled, skipped, duplicate or mismatched records prevent full qualification.

The resulting inventory identifies the exact package versions and environment fingerprints per lane — several environments, no single shared Manifest.

## Documentation publication

- Development documentation publication is independent of qualification.
- The `Documentation` workflow builds Documenter and VitePress without running a package qualification matrix or benchmarks. Its canonical checker serves the exported files and checks HTML, search, assets, metadata and browser interactions before transfer.
- An ordinary `main` build exports the canonical SFTP site at `https://perfchecker.mirageinteractive.fr/dev/` and the GitHub mirror at `/PerfChecker/dev/`. Each publisher is enabled separately; a build alone does not prove a transfer succeeded. Pull requests build and check exports but do not publish.
- The extended qualification produces a `qualified-collection` artifact with the exact tested revisions and environments.
- Collection publication requires a complete successful qualification and revalidates its receipts and site hash. Separately, the `Documentation` workflow builds tagged exports at `/vX.Y.Z/` and the stable root `/`, verifies the tag/version and validates the exports before SFTP publication. Documentation publication alone does not qualify the package collection.
- The documentation lane also builds the standalone SFTP site for `https://perfchecker.mirageinteractive.fr/`. Its root paths, `.html` links, version catalogue, search and assets are tested on a static server without rewrite rules. The collection validates its separate hash before publishing; it cannot substitute the GitHub mirror for this export.

A manual **stable documentation refresh** is a distinct docs-only route, not a
new release. Dispatch `Documentation` on `main` with `publication=stable`.
The ordinary refresh uses main's version and validates it against the existing
stable tag. For a different reviewed documentation source, supply both
`stable_version` (for example `v1.0.0`) and a full 40-character
`docs_source_revision`. The explicit pair is accepted only for that stable
dispatch on `main`; it does not override the trusted publisher revision.

The explicit source must have the tag's Project.toml version, its checkout HEAD
must equal the requested SHA, and its diff from the release must pass the
documentation-only allowlist. Functional package sources and metadata must stay
unchanged. Build metadata and source links retain that same source SHA, and the
publisher checks the same source again. This route builds and publishes only
the stable root: it does not write `/dev/`, the GitHub mirror, a versioned archive
or the version catalogue. Existing archive/stable guards remain in force.
See the [deployment contract](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/blob/1a7577da782ba8676683f3ceefcb8dccf055afe5/website/DEPLOYMENT.md)
and the [workflow](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/blob/1a7577da782ba8676683f3ceefcb8dccf055afe5/.github/workflows/Documentation.yml)
for the exact checks and publication switches. A refresh is not hardware,
frontend or release qualification.

Publishing development documentation does not certify the packages it describes. Pull requests build but cannot publish.

## Registered-package evaluation

The **Registered PkgEval** workflow, introduced in 1.1.0, evaluates an immutable
release selected from General by default, on Julia stable
and nightly in Linux sandboxes. An explicit manual Git-candidate mode evaluates
a fixed PerfChecker commit instead; General then supplies only its dependencies. This is
separate from checkout CI, collection qualification and documentation publication.
It does not measure benchmark regressions or qualify all frontends.
Pull-request checks validate source selection without launching the sandboxes;
the real evaluations run on a schedule or an explicit manual dispatch.

See [installed-release evaluation](../tutorials/ci.md#Check-installed-releases-with-PkgEval)
for source-tree verification, artifact fields, limits, the known 1.0.1 read-only
fixture failure and how to request a registered version or an unpublished Git
candidate. A green checkout
test of a fixture correction cannot be substituted for PkgEval of the release
that eventually contains it.

## Limits

- The initial supported platforms are Windows and Linux.
- The separate compatibility CI tests the latest stable Julia on Linux 64-bit and 32-bit, macOS Intel 64-bit and Windows 64-bit. Julia LTS and pre-release runtimes are tested on Linux 64-bit. Those core tests do not establish qualification of every interface on macOS.
- Core tests generate and replay PropCheck corpora on these architectures.
  Published Supposition releases fail to load on 32-bit Julia; their optional
  backend is qualified separately on 64-bit Julia. See
  [property-based workloads](extensions.md#Property-based-workloads).
- Up to four jobs run on separate GitHub-hosted virtual machines. Each job keeps sequential workers, one Julia compute thread, single-thread BLAS and a four-thread computation budget.
- No measurement is validated merely because a tool executable was found.
