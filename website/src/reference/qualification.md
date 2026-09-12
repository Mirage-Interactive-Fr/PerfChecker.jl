# Qualified collections

A PerfChecker release is used with interface packages, Julia versions and external
tools. A passing test in one package cannot establish that all these combinations
work together. `PerfCheckerQualification` checks an explicit candidate collection.

## What is tested after a change

Routine CI checks changed interfaces and their consumers with current dependencies
on Linux. Core changes also check Windows and the minimum supported Julia version.
The shared contracts and style checks accompany the selected components.
Core, contract and unknown-path changes conservatively select every component,
but still use this reduced profile.

The extended Windows/Linux matrix runs weekly or on manual request with `full`
enabled. It adds older dependency combinations and broader platform coverage.
Only the extended matrix can qualify a release; passing routine CI is not a
substitute. Each lane records its runtime and resolved dependency environment.

The initial supported qualification platforms are Windows and Linux. Jobs execute
sequentially, with one Julia compute thread and single-thread BLAS defaults, within
a four-thread computation budget. No measurement is validated merely because a
tool executable was found.

## Candidate versus qualified

`qualification/collection.toml` selects candidates. External repositories use full
commit SHAs; mutable branches are rejected. A dependency-update PR proposes a new
candidate and triggers qualification. Until it passes, the last qualified collection
remains the published reference.

Every qualification attempt has its own campaign ID. Missing jobs cannot be filled
with reports from an earlier attempt, even at the same source revision. Failed,
cancelled, skipped, duplicate or mismatched records prevent full qualification.

The resulting inventory identifies the exact package versions and environment
fingerprints used in each lane. It describes several environments, rather than
claiming all interfaces can share one Manifest. This matters for HTTP dependencies.

## Documentation publication

Documentation publication is independent of qualification. The `Documentation`
workflow installs the documentation dependencies, builds Documenter and VitePress,
and publishes `/PerfChecker/dev/`. It runs no package matrix, browser tests or benchmarks.
Documenter's own reference and doctest checks remain part of the build.

The extended qualification produces its own `qualified-collection` artifact with
the exact tested package revisions and environments. Only complete successful
qualification authorizes a package release. Publishing development documentation
does not certify the packages it describes. Pull requests build but cannot publish.
