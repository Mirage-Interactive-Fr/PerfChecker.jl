# PerfCheckerQualification

An independent, stdlib-only Julia package for qualifying PerfChecker components.
It lives in this repository so implementation and contracts can change in one PR.
It can move without becoming a runtime dependency of PerfChecker.

## Local use

From the repository root:

```sh
julia --startup-file=no --project=qualification qualification/test/runtests.jl
julia --startup-file=no --project=qualification qualification/scripts/plan.jl --full
julia --startup-file=no --project=qualification qualification/scripts/run.jl contracts-windows-latest-1
```

Use `contracts-ubuntu-latest-1` on Linux. Each lane records the actual Julia
version, OS, source commit, dirty state, resolved manifests and outcome under
`.qualification/results`. Environments are prepared before tests. The common
test-item corpus is `shared/items.jl`; Julia and CLI check identical selection,
identities and tags. Existing integration suites exercise the individual adapters.

Keep `--startup-file=no` in these commands: a personal Julia startup file can
load development tools or modify the active environment before qualification
starts. The controller and its workers must use the declared dependencies.

Set `PERFCHECKER_PLAN` to use the same saved plan in `run.jl` and `collect.jl`.
The default is `.qualification/plan.toml`. Collection verifies all expected
receipts and their recorded artifact hashes; a local run with uncommitted
changes remains non-publishable.

The documentation lane installs Chromium and its system libraries by default.
On a prepared local machine, set `PERFCHECKER_BROWSER_DEPS_READY=true` after
installing Playwright's Chromium system dependencies separately. The lane still
installs the browser and runs every browser check; CI keeps the default setup.

Set `PERFCHECKER_BASE_SHA` to a full base commit SHA for a targeted plan. Missing
base information selects everything. Both paths of renames participate. The most
specific path owns the component; core, contracts and unknown paths select all.
`PERFCHECKER_CHANGED_COMPONENTS=vscode` supports separate-repository candidates.

## Updating the collection

`collection.toml` defines candidates, not validated releases. External repositories
use immutable commits. Updating `sources.vscode.revision` in a PR qualifies that
exact client against the collection. It must pass native-item tests before the
collection can be published.

Web, Pluto and Makie are separate Julia packages under `packages/`, developed
with the core in each relevant lane. Each keeps its unit tests; collection tests
exercise its consumers. Native lanes also execute `examples/first-check/run.jl`.
External checkout currently implements the existing VS Code repository only.

Separate package CI should propose a PR updating its immutable revision here.
That PR triggers qualification and provides an audit trail. Automated updates
require a GitHub App or repository-scoped credentials; manual PRs work without it.

## Qualification and publication

PRs run impacted consumers plus shared contracts. Main, tags, manual runs and a
weekly dependency refresh run the configured Windows/Linux collection. Jobs are
bounded to one concurrent lane, one Julia thread and 90 minutes each. The collection
workflow replaces the earlier core and shared-scenario workflows. The separate
VS Code repository retains its client CI.

`scripts/collect.jl` rejects missing, failed, duplicate, stale and mismatched lanes
and altered environment files. Partial success never authorizes documentation
publication. Full qualification emits `.qualification/collection.toml`, including
the exact environment inventory per lane. These are separate environments, not
one universal Manifest: Oxygen/HTTP 2 and Pluto/HTTP 1 can coexist in the collection.
Every new plan receives a unique campaign identifier, so receipts from earlier
attempts cannot fill missing jobs even when the source revision is unchanged.

The documentation lane hashes the built site. Publication rechecks the complete
collection and the exact site instead of rebuilding with newer dependencies.
`collection.toml` is placed beside the published pages. PR jobs cannot publish.
Receipts check consistency; trust comes from retrieving them from the same CI run,
not from accepting arbitrary TOML supplied by a candidate.

Enable `PERFCHECKER_DOCS_DEPLOY=true` only after configuring the destination,
Pages, branch policy and credentials. Until then the workflow only produces
artifacts. See [documentation deployment](../website/DEPLOYMENT.md) for the
destination and the cross-repository deploy-key setup.

## Explicit limits

- The first complete remote matrix has not run; controller tests alone do not
  qualify the collection or its externally pinned VS Code revision.
- VS Code runs native-controller tests, launches an isolated Extension Development
  Host and packages a VSIX. The host test reuses `shared/items.jl` to prove a single
  selected item ran exactly once; the receipt captures its real VS Code version.
- Pluto checks package activation, generated notebooks and notebook controls,
  without claiming that a browser session was tested.
- macOS, GPU devices and privileged native profilers are outside this initial
  matrix. Capability detection never counts as execution evidence.
