# Publish the documentation

Sources live in `website/` beside the code they describe. The canonical static
site is <https://perfchecker.mirageinteractive.fr/>, served at the domain root.
The GitHub mirror remains under `PerfChecker/` in
`Mirage-Interactive-Fr/Mirage-Interactive-Fr.github.io`, branch `gh-pages`.
Its development documentation is served at
<https://mirage-interactive-fr.github.io/PerfChecker/dev/>. Documenter manages
the mirror's redirect and versions only inside `PerfChecker/`.

The canonical Studio, configuration, Julia/notebook and MCP guides publish with
the package documentation. Development documentation comes from `main`; stable
documentation comes from the matching version tag. Official extension publication
follows V1 availability in General.

## Static export and SFTP

Build from the repository root, with Julia and Node.js 22.12 or newer:

```sh
julia --startup-file=no --project=website -e 'using Pkg; cd("website") do; Pkg.develop(path=".."); Pkg.instantiate(); end'
PERFCHECKER_DOCS_URL=https://perfchecker.mirageinteractive.fr/ PERFCHECKER_DOCS_BASE=/ julia --startup-file=no --project=website website/make.jl
```

The fresh output is **`website/build/site`**. Upload its **contents** to the SFTP
account's document root, preserving all subdirectories and filenames. Do not
upload `website/`, `build/`, or a new `site/` wrapper directory. The host should
serve `index.html` as a directory index. All generated page links use `.html`,
so no rewrite rule, Julia service, Node service or CMS is required at runtime.
The SFTP account, remote document-root path and upload remain separate deployment
inputs; a successful build does not establish that a remote host was updated.

The export contains runtime assets, fonts, local search, logo/favicon,
`sitemap.xml`, `versions.js` and `siteinfo.js`. Its version picker links the
installed version to `/` and development documentation to the real GitHub
mirror; it does not advertise absent `stable/` or `v1.0/` directories on the
SFTP host. Replace the export as one site, including assets and metadata, instead
of uploading HTML from one build with assets from another.

For other deployments, `PERFCHECKER_DOCS_URL` selects the HTTPS deployment URL
ending in `/`, and `PERFCHECKER_DOCS_BASE` selects its URL path, with leading and
trailing `/`. GitHub mirror workflows set both explicitly. A mirror build uses
clean URLs and Documenter's version catalogue; its artifact must not be uploaded
unchanged to the root SFTP host.

The full qualification produces `qualified-documentation-static`, the tested
root export, and `qualified-documentation-site`, the tested GitHub mirror. The
documentation receipt records **separate hashes** for both. Downloading these
Actions artifacts requires a GitHub login. The collection and stable deployment
revalidate both artifacts from their original campaign.

## GitHub mirror authorization

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

Before General registration, a maintainer can explicitly authorize replacing
an unregistered release. Keep the workflow's tag guard: first qualify the new
exact source and collection completely. Recheck that General has no entry for
that version and that the remote tag still identifies the expected old commit;
replace it only with a force-with-lease against that exact old ref. Update the
GitHub release notes and qualified collection asset from the same campaign,
then rerun only the failed publication/deployment jobs. Do not rerun producers,
mix campaign receipts, replace an already registered package tree or bypass
branch protection.

## Human registration and extension publication

Check that `main`, the stable tag and the qualified collection identify the same
commit before invoking Registrator. The package owner performs registration.
For a breaking release, include migration notes in the registration comment;
notes in a GitHub release alone do not satisfy this step. For example:

```text
@JuliaRegistrator register

Release notes:

## Breaking changes
PerfChecker 1.0.0 changes the 0.2 API. Use a separate environment when migrating.
Web, Pluto and Makie interfaces require their explicit packages. Suite, TestItems,
CLI and saved-result consumers should follow the V1 contracts; empty allocation
profiles retain explicit qualification rather than implying zero allocations.
See CHANGELOG.md at the v1.0.0 tag for migration details.
```

See [RegistryCI's requirements](https://juliaregistries.github.io/RegistryCI.jl/stable/guidelines/#Providing-and-updating-release-notes).
After the registry merge, verify the package UUID/version/tree and an actual
installation from General. Only then publish the exact qualified VSIX to the
Marketplace; do not rebuild a different package for publication.

## Dependency maintenance

The required CI explicitly excludes BenchmarkTools 1.8.0 because its trial
allocation estimate overflows Int32 before bounding. CompatHelper may propose
adding a broad `1` range that would restore this release. That proposal must fail
CI and remain unmerged until the Linux 32-bit contract is reviewed.

CompatHelper also needs repository permission for GitHub Actions to create pull
requests. An HTTP 403 at PR creation is a repository/organization setting issue,
not a package test failure. Keep the workflow's explicit write permissions and
the default repository token policy; do not bypass required status checks.
For a PR created or updated with `GITHUB_TOKEN`, GitHub can hold the resulting
`pull_request` workflow runs for approval. A maintainer with write access should
select **Approve workflows to run** on that PR, then require the normal checks.
See [GitHub's token-trigger rules](https://docs.github.com/en/actions/concepts/security/github_token).

## Local preview

From the repository root:

```sh
julia --project=website -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --project=website website/make.jl
node website/preview.mjs
```

Building locally never publishes. Keep recordings outside Git;
`website/media.json` can reference external videos independently of site builds.
For a check matching SFTP hosting, set `PERFCHECKER_PREVIEW_CLEAN_URLS=false` when
starting the preview and follow the generated `.html` navigation links.
