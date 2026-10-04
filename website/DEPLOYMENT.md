# Publish the documentation

Sources live in `website/` beside the code they describe. Generated pages go to
`Mirage-Interactive-Fr/Mirage-Interactive-Fr.github.io`, branch `gh-pages`.
Development documentation is served at <https://mirage-interactive-fr.github.io/PerfChecker/dev/>.
The organization root is a landing page for project documentation. Documenter
manages its redirect and versions only inside `PerfChecker/`; other projects
publish to their own sibling directories.

The canonical Studio, configuration, Julia/notebook and MCP guides publish with
the package documentation. Development documentation comes from `main`; stable
documentation comes from the matching version tag. Official extension publication
follows V1 availability in General.

A later move to `perfchecker.mirageinteractive.fr` is planned separately. Do not
change DNS, a CNAME or the current canonical links as part of guide
updates. Rebuild and validate the complete site with the new base and deployment
URL when that migration is authorized; `PERFCHECKER_DOCS_BASE` already permits
testing a different URL path without changing the current host.

## One-time authorization

Documenter's cross-repository deployment requires a dedicated SSH key pair:

1. In the **site repository**, open **Settings → Deploy keys → Add deploy key**.
   Add the public key and enable **Allow write access**.
2. In **PerfChecker.jl**, open **Settings → Secrets and variables → Actions**.
   Add the base64-encoded private key as repository secret `DOCUMENTER_KEY`.
3. In the **site repository**, configure **Settings → Pages → Deploy from a branch**:
   branch `gh-pages`, folder `/ (root)`.
4. In **PerfChecker.jl**, set Actions repository variable
   `PERFCHECKER_DOCS_DEPLOY` to `true`.

Keep the private key out of both repositories. This key grants write access only
to the site repository; no personal token is needed. See
[Documenter's deployment instructions](https://documenter.juliadocs.org/stable/man/hosting/#Out-of-repo-deployment).

## Development documentation and release qualification

The independent `Documentation` workflow installs only the documentation
dependencies, builds Documenter and VitePress, then publishes `/PerfChecker/dev/` from `main`. It does not
run package tests, browser tests, benchmarks or qualification. Documenter's own
reference and doctest checks remain part of the build. PRs build but never publish.

`Collection qualification` uses a reduced routine profile on pushes and pull
requests. The weekly schedule and a manual run with `full` enabled use the extended
Windows/Linux matrix, including older dependency combinations. Only that complete
qualification can create a package release and a qualified collection inventory.
Do not combine receipts from different workflow runs.

The workflows can be rerun from their Actions pages. Manual dispatch becomes
available when their definitions are also present on the default branch.

`main` supplies `dev/`. A qualified release publishes a version-specific site built with
`PERFCHECKER_DOCS_BASE=/PerfChecker/v1.0.0/` for `v1.0.0`. Documenter maintains
the redirect, `stable/` alias and version selector inside `PerfChecker/`.
The full qualification's `stable-documentation` job retrieves all receipts and
the tested site from its own campaign, rechecks the recorded site hash, then
deploys that artifact. It verifies the real published tag against the qualified
revision and supplies that tag through Documenter's `GitHubActions` deployment
configuration. It never rebuilds the stable site during publication, and the tag
does not launch a second collection campaign.

The `release` job requires a complete extended qualification from the same run,
a clean collection at the exact release revision and an explicit `publish` input.
It creates a stable GitHub release without replacing an existing tag. General
registration and Marketplace publication are separately verified release steps.

## Local preview

From the repository root:

```sh
julia --project=website -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --project=website website/make.jl
node website/preview.mjs
```

Building locally never publishes. Keep recordings outside Git;
`website/media.json` can reference external videos independently of site builds.
