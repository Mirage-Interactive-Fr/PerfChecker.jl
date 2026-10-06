# PerfChecker visual assets

The canonical documentation logo is the colored gauge in
`website/src/public/assets/perfchecker-mark.png`. The website uses it in its
navigation, hero and favicon. The VS Code extension uses that same colored logo
and a monochrome gauge silhouette for its activity-bar icon. Treat the existing
PNG as the master for this identity; the Julia generator below does not produce
that image.

The retained comparison illustration is generated from Julia source with Luxor.jl. It represents the core
PerfChecker workflow as a discrete comparison plot: package versions, a local
development target, and a Git commit are placed on the x axis; speed,
allocations, garbage-collection cost, network traffic, and CI test coverage are
attached directly to their traces. Coverage is CI evidence, not a PerfChecker
workload backend.
Each straight segment joins two measured targets, so the slope changes only at
an observed version or revision.

The segmented border uses the familiar Julia green, blue, purple, and red while
remaining a PerfChecker illustration.

## Regenerate

```sh
julia --project=branding -e 'using Pkg; Pkg.instantiate()'
julia --project=branding branding/generate_logo.jl
```

Generated comparison files live only in `branding/exports`. The generator does
not overwrite the documentation or extension logo. Keep its source, SVG,
1024 px PNG, light and dark lockups, and preview sheet in sync when updating the
comparison illustration.
