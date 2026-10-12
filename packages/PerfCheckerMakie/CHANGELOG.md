# Changelog

## 1.0.2

- Add `observation_plot` for saved measurements with explicit axes, units,
  collector, scope and provenance, including non-version comparisons.
- Render these models with native Makie figures and standalone interactive HTML.
  Inspect exact points, filter panels/series/recorded versions, navigate with the
  keyboard, and download the full model or visible CSV data.
- Preserve unavailable values and zeros, distinguish series and versions, dodge
  grouped bars and retain readable axes in narrow embeds.

This companion release does not change PerfChecker Core or the VS Code extension.
