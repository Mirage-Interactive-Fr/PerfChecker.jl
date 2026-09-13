# Publish the documentation

Sources live in `website/` beside the code they describe. Generated pages go to
`Mirage-Interactive-Fr/Mirage-Interactive-Fr.github.io`, branch `gh-pages`.
Development documentation is served at <https://mirage-interactive-fr.github.io/PerfChecker/dev/>.
The organization root is a landing page for project documentation. Documenter
manages its redirect and versions only inside `PerfChecker/`; other projects
publish to their own sibling directories.

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
dependencies, builds Documenter and VitePress, then publishes `/PerfChecker/dev/`. It does not
run package tests, browser tests, benchmarks or qualification. Documenter's own
reference and doctest checks remain part of the build. PRs build but never publish.

`Collection qualification` uses a reduced routine profile on pushes and pull
requests. The weekly schedule and a manual run with `full` enabled use the extended
Windows/Linux matrix, including older dependency combinations. Only that complete
qualification can create a package release and a qualified collection inventory.
Do not combine receipts from different workflow runs.

The workflows can be rerun from their Actions pages. Manual dispatch becomes
available when their definitions are also present on the default branch.

The RC branch supplies `dev/`. Prerelease tags do not define a stable
documentation release. When V1 is accepted, set `devbranch` in
`website/deploy.jl` to `main`, update edit links and extend the publishing
branch filter. Build and test each stable version with its own
`PERFCHECKER_DOCS_BASE` before enabling tag deployments; the RC workflow
deliberately builds only `/PerfChecker/dev/`.
Documenter maintains the redirect and version selector inside `PerfChecker/`.

The separate `release-candidate` job creates a GitHub prerelease only after the
full collection passes. It never replaces a tag pointing to another revision.

## Local preview

From the repository root:

```sh
julia --project=website -e 'using Pkg; Pkg.develop(path="."); Pkg.instantiate()'
julia --project=website website/make.jl
node website/preview.mjs
```

Building locally never publishes. Keep recordings outside Git;
`website/media.json` can reference external videos independently of site builds.
