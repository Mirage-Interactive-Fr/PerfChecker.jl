# Release notes

## 1.0.0

The V1 API has changed substantially since 0.2.4. Use a separate Julia environment
when migrating an existing installation.

### Breaking changes and migration

- Web, Pluto and Makie interfaces now require their explicit packages:
  `PerfCheckerWeb`, `PerfCheckerPluto` and `PerfCheckerMakie`. Loading Oxygen,
  Pluto or Makie alone no longer activates a PerfChecker interface. Keep these
  packages in the controller environment; install instructions include the
  stable repository subdirectories until the interface packages are registered.
- Migrate V1 workflows to the documented suite, TestItems, CLI and saved-result
  contracts. Check each report's format version when consuming it in external
  tooling, and keep a separate environment for an existing 0.2 installation.
- Functional-only and performance-only item selection is explicit. Use
  `testitem_filter(:test)` for a functional TestItemRunner job and the documented
  conditional skip guard when the same items appear in Julia VS Code's Run All.
- Allocation-profile consumers must inspect their qualification status when
  source sites are empty. Measured totals remain available; no samples, source
  attribution failure and measured zero allocations are distinct outcomes.
  Legacy CSV profile caches without matching qualification metadata are refreshed.

### Features

- Run existing TestItems, with tag filters and performance-only items.
- Use a common suite and result model in VS Code, Oxygen, Pluto, the REPL and scripts.
- Install web, notebook and plot interfaces as separate Julia packages.
  Their first General registrations are pending.
- Compare releases and development targets in isolated workers with recorded provenance.
- Preserve local source dependencies when copying worker environments, and keep
  CPU, wall-time and allocation source attribution within the selected target.
- Overlay timing, GC and allocation curves normalized by their respective minima.
  Individual plots and raw values remain available.
- Inspect profiles, process resources and available native diagnostics.
- Explore machine similarity and calibration with explicit uncertainty.
- Follow DocumenterVitepress tutorials with runnable Bibliography examples,
  downloadable notebooks and recorded measurements.
- Qualify the package collection and pinned VS Code client on Windows and Linux.
- Use the full-editor VS Code Studio with complete check and source selectors,
  interactive plots, native Julia notebooks, a dedicated terminal and Julia debug.
- Discuss saved evidence with a configured MCP agent and explicitly request
  implementation in an isolated checkout, with Git checkpoint, diff review,
  controlled application and recovery after an editor restart.
- Connect an authenticated native Codex CLI explicitly through a temporary local
  MCP bridge, with separate advice and implementation tools, preserved provider
  settings and a real-agent lifecycle qualification.
- Bound conversation and MCP payloads, validate tool arguments, preserve source
  encodings and retain explicit cancellation without replaying the target code.
- Keep extension usage, configuration, Julia workflows and MCP guidance in the
  canonical DocumenterVitepress documentation beside the package sources.
- Build and qualify a complete static documentation export for
  `https://perfchecker.mirageinteractive.fr/`, with portable deep links, local
  search, version metadata and a separate inventory from the GitHub mirror.

Report the exact revision, Julia version, operating system and a minimal
reproducer. Remove credentials and private data before sharing reports.

The extended collection matrix covers Windows and Linux; the core compatibility
CI also checks macOS. GPU hardware and privileged native profilers remain outside
the initial collection qualification. Optional tools
report unavailable capabilities rather than treating them as passing checks.
Large recordings stay outside Git history and can be embedded from external hosts.
