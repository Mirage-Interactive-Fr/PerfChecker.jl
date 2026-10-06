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
`sitemap.xml`, `versions.js`, `siteinfo.js` and `build-info.json`. The latter
records the source revision, version, channel and canonical base. Its version
catalogue is preview metadata; the automated publisher generates the live
catalogue from completed publications on the destination server.

For an isolated build, set `PERFCHECKER_DOCS_BUILD_DIR` to a directory relative
to `website/`, for example `build/sftp/dev`. This preserves an existing
`website/build/site` export. Set `PERFCHECKER_DOCS_CHANNEL` to `dev`,
`version` or `stable`, and `PERFCHECKER_DOCS_HOSTING=sftp`. Every canonical
base uses actual `.html` files, including `/dev/` and `/vX.Y.Z/`.

The GitHub mirror uses `PERFCHECKER_DOCS_HOSTING=github`, its own deployment
URL and `/PerfChecker/dev/` or version base. Its clean URLs and Documenter
catalogue are separate from the SFTP export. Do not upload a mirror artifact
to the canonical host.

The full qualification still produces `qualified-documentation-static` and
`qualified-documentation-site`, with separate recorded hashes. Its existing
collection and release guards are unchanged. The independent Documentation
workflow's exports are documentation checks, not a complete package qualification.

## Automatic canonical SFTP publication

The `Documentation` workflow builds exports without server credentials and
saves downloadable artifacts before publication. Pull requests build and test
all three canonical bases but never receive SFTP secrets. Main pushes and a
manual dispatch on main publish only `/dev/`. A stable tag matching
`Project.toml` publishes `/vX.Y.Z/` and promotes that version to the domain
root only if it is at least as recent as the previously selected stable version.
Development builds also accept Julia versions such as `1.0.1-DEV`.

Configure these repository Actions variables:

| Variable | Meaning |
| --- | --- |
| `PERFCHECKER_DOCS_SFTP_HOST` | SFTP hostname, without a URL scheme |
| `PERFCHECKER_DOCS_SFTP_PORT` | SSH port |
| `PERFCHECKER_DOCS_SFTP_USER` | Account name |
| `PERFCHECKER_DOCS_SFTP_ROOT` | Absolute document root as seen by the SFTP account, including any chroot |
| `PERFCHECKER_DOCS_SFTP_DEPLOY` | Keep `false` until reviewed; set `true` to enable |

Configure `PERFCHECKER_DOCS_SFTP_PASSWORD` and
`PERFCHECKER_DOCS_SFTP_KNOWN_HOSTS` as Actions secrets. The latter is an
OpenSSH known_hosts entry for the exact host and port, obtained through a trusted
channel; a nonstandard port uses `[host]:port`. The publisher verifies the raw
server public key against this entry and rejects a different key. An optional
`PERFCHECKER_DOCS_SFTP_SSH_KEY` secret can supply an OpenSSH private key instead
of a password. Do not put credentials in build variables, files, artifacts or logs.
The publication job uses the `documentation-sftp` environment; configure any
required environment protection before enabling it.

The transport is `ssh2` **1.17.0**, locked with npm integrity metadata. It opens
only SFTP and requires no remote shell. Existing files require the server's
`posix-rename@openssh.com` extension for safe replacement. Uploads create
adjacent temporary files, apply file mode `0644`, then rename them; created
and used subdirectories have mode `0755`. Assets upload before pages, and
`index.html` follows the other pages. Progress is logged every 500 files.
The publication job allows 45 minutes for the approximately 204 MB export.

No recursive deletion runs. Development, previous versions and unrelated user
files remain present. Hashed assets from older builds remain usable during an
update. Individual file replacements are atomic on a supporting server; an
entire site update is not atomic. Readers may briefly observe pages from two
builds if an update is interrupted. Download the saved artifacts and rerun the
failed publication job to repair the transfer.

All workflow refs share a publication mutex, with cancellation disabled. An
atomic remote `.perfchecker-docs-lock` directory also excludes overlapping
publishers. A cancelled runner can leave this lock behind: confirm there is no
active publisher, then remove only that empty lock directory through SFTP and
retry. Never remove a lock held by an active run.

The publisher maintains `.perfchecker-releases.json`, immutable per-version
`.perfchecker-docs.json` markers, a root `.perfchecker-promotion.json`
watermark and a root `.perfchecker-stable.json` completion marker. It writes
the watermark before changing root files, so a delayed old tag cannot roll back
a partially updated root. It commits a completed root marker after transfer,
then the publication state and live `versions.js` catalogue. A retry recovers
a completed promotion if a metadata write failed. Never edit these records to
force an older version into the root, and never retag a published version to
replace its source or artifact bytes.

For initial activation, merge this configuration, enable SFTP, and dispatch
Documentation on main. Verify `/dev/`, a deep `.html` link, local search and
the version picker. This first deployment preserves the existing manual root.
After the final main commit is registered in General, TagBot creates the matching
stable tag and triggers the version and root documentation builds. The dedicated
`TAGBOT_SSH_KEY` grants TagBot access to the package repository;
`DOCUMENTER_KEY` remains dedicated to the GitHub documentation mirror.

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

The independent `Documentation` workflow installs documentation dependencies,
builds Documenter and VitePress, tests SFTP publication policy and authentication,
and checks canonical routes and browser navigation. It publishes the canonical
`/dev/` and the GitHub mirror from main when each deployment is enabled. It does
not run package tests, benchmarks or a complete qualification. Documenter's own
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

Integrate the reviewed documentation configuration on main before selecting the
registration commit. Confirm the canonical package URL in the General metadata,
then have the package owner register that final main commit. TagBot creates the
stable tag after General accepts it; do not create an earlier manual tag just to
start documentation deployment. The collection qualification remains a separate
validation with its existing exact-source and publication guards.
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
