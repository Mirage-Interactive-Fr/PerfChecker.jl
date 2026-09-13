# Release notes

## 1.0.0-rc1

This is a release candidate for community testing, not the final V1 release.
The API has changed substantially since 0.2.4; use a separate Julia environment
when evaluating the candidate alongside an existing installation.

- Run existing TestItems, with tag filters and performance-only items.
- Use a common suite and result model in VS Code, Oxygen, Pluto, the REPL and scripts.
- Install web, notebook and plot interfaces as separate Julia packages.
  Their first General registrations are pending.
- Compare releases and development targets in isolated workers with recorded provenance.
- Overlay timing, GC and allocation curves normalized by their respective minima.
  Individual plots and raw values remain available.
- Inspect profiles, process resources and available native diagnostics.
- Explore machine similarity and calibration with explicit uncertainty.
- Follow DocumenterVitepress tutorials with runnable Bibliography examples,
  downloadable notebooks and recorded measurements.
- Qualify the package collection and pinned VS Code client on Windows and Linux.

Report the exact revision, Julia version, operating system and a minimal
reproducer. Remove credentials and private data before sharing reports.

General still provides stable version 0.2.4. macOS, GPU hardware and privileged
native profilers are outside the initial qualification matrix. Optional tools
report unavailable capabilities rather than treating them as passing checks.
Large recordings stay outside Git history and can be embedded from external hosts.
