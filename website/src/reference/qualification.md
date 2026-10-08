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
- The `Documentation` workflow installs documentation dependencies, builds Documenter and VitePress, and publishes `/PerfChecker/dev/` from `main`. No package matrix, browser tests or benchmarks.
- The extended qualification produces a `qualified-collection` artifact with the exact tested revisions and environments.
- Only a complete successful qualification authorizes a package release and stable documentation. The stable publication revalidates all receipts and the site hash, then deploys the exact tested artifact from that campaign at its verified release tag.
- The documentation lane also builds the standalone SFTP site for `https://perfchecker.mirageinteractive.fr/`. Its root paths, `.html` links, version catalogue, search and assets are tested on a static server without rewrite rules. The collection validates its separate hash before publishing; it cannot substitute the GitHub mirror for this export.

Publishing development documentation does not certify the packages it describes. Pull requests build but cannot publish.

## Limits

- The initial supported platforms are Windows and Linux.
- The separate compatibility CI tests the latest stable Julia on Linux 64-bit and 32-bit, macOS Intel 64-bit and Windows 64-bit. Julia LTS and pre-release runtimes are tested on Linux 64-bit. Those core tests do not establish qualification of every interface on macOS.
- Core tests generate and replay PropCheck corpora on these architectures.
  Published Supposition releases fail to load on 32-bit Julia; their optional
  backend is qualified separately on 64-bit Julia. See
  [property-based workloads](extensions.md#Property-based-workloads).
- Up to four jobs run on separate GitHub-hosted virtual machines. Each job keeps sequential workers, one Julia compute thread, single-thread BLAS and a four-thread computation budget.
- No measurement is validated merely because a tool executable was found.
