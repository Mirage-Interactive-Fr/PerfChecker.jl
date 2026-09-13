# Qualified collections

A PerfChecker release is used with interface packages, Julia versions and external tools. `PerfCheckerQualification` checks an explicit candidate collection; one passing test cannot cover every combination.

## What runs after a change

- Routine CI checks changed interfaces and their consumers with current dependencies on Linux.
- Core changes also check Windows and the minimum supported Julia version.
- Shared contracts and style checks accompany the selected components.
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

- Documentation publication is independent of qualification.
- The `Documentation` workflow installs documentation dependencies, builds Documenter and VitePress, and publishes `/PerfChecker/dev/`. No package matrix, browser tests or benchmarks.
- The extended qualification produces a `qualified-collection` artifact with the exact tested revisions and environments.
- Only a complete successful qualification authorizes a package release.

Publishing development documentation does not certify the packages it describes. Pull requests build but cannot publish.

## Limits

- The initial supported platforms are Windows and Linux.
- Jobs run sequentially: one Julia compute thread, single-thread BLAS, four-thread budget.
- No measurement is validated merely because a tool executable was found.

```@raw html
<a id="What-is-tested-after-a-change"></a>
```
