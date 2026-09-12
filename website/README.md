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

To serve the completed artifact locally, run `npm run docs:preview` from this
directory and open `http://127.0.0.1:8870/`. Set `PORT` to choose another port.
The preview binds only to loopback and serves clean page URLs as well as assets.

`website/deploy.jl` accepts only a complete qualified collection and its matching
site artifact. Deployment destination and credentials remain separately configured.
See `DEPLOYMENT.md` for publication setup and `../qualification/README.md`
for the publication gate and exact environment records.
