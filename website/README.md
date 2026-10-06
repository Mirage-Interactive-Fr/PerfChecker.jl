# PerfChecker website

This directory is the autonomous **DocumenterVitepress** project for PerfChecker
and its interface packages. Documenter reads the Julia documentation; VitePress
provides the site.

From the collection repository root, with Julia and Node.js 22.12 or newer:

```sh
julia --project=website -e 'using Pkg; cd("website") do; Pkg.develop(path=".."); Pkg.instantiate(); end'
julia --project=website website/make.jl
```

The finished site is `website/build/site`. The command performs both documentation
generation and the real HTML build, including on Windows. It never deploys.

The default is the complete static export for
`https://perfchecker.mirageinteractive.fr/`, at the domain root. It includes
portable `.html` deep links, assets, search, favicon, sitemap and version
metadata. Upload the **contents** of `website/build/site`, including subfolders;
uploading its parent directory would put the site under the wrong URL.

For a different host/path, set `PERFCHECKER_DOCS_URL` to its HTTPS deployment URL
ending in `/`, and `PERFCHECKER_DOCS_BASE` to the served path with leading and
trailing `/`. The GitHub workflows set these explicitly for their mirror.

To serve the completed artifact locally, run `npm run docs:preview` from this
directory and open `http://127.0.0.1:8870/`. Set `PORT` to choose another port.
The preview binds only to loopback and serves clean page URLs as well as assets.
Set `PERFCHECKER_PREVIEW_CLEAN_URLS=false` to check the SFTP export without
extensionless-page rewrites; its generated navigation uses `.html` files.

The independent `Documentation` workflow builds and publishes development
documentation without running benchmarks or package qualification. Examples use
saved measurements. See `DEPLOYMENT.md` for publication setup; release qualification
is a separate workflow described in `../qualification/README.md`.
