# Companion APIs

These Public and Full references render the real Julia docstrings of the optional
packages from the same source revision as this Core 1.0.1 site. Each owner is
loaded in a separate documentation project. Full API includes documented internal
bindings; it does not promise documentation for every private helper.

```@raw html
<table>
<thead><tr><th>Owner</th><th>Public API</th><th>Full API</th><th>Reference inventory</th></tr></thead>
<tbody>
<tr><td>PerfCheckerLinuxPerf 1.0.1</td><td><a href="../optional-api/linuxperf/public-api.html">Public</a></td><td><a href="../optional-api/linuxperf/full-api.html">Full</a></td><td><a href="../optional-api/linuxperf.inv">Inventory</a></td></tr>
<tr><td>PerfCheckerLIKWID 1.0.1</td><td><a href="../optional-api/likwid/public-api.html">Public</a></td><td><a href="../optional-api/likwid/full-api.html">Full</a></td><td><a href="../optional-api/likwid.inv">Inventory</a></td></tr>
<tr><td>PerfCheckerMakie 1.0.1</td><td><a href="../optional-api/makie/public-api.html">Public</a></td><td><a href="../optional-api/makie/full-api.html">Full</a></td><td><a href="../optional-api/makie.inv">Inventory</a></td></tr>
<tr><td>PerfCheckerWeb 1.0.0</td><td><a href="../optional-api/web/public-api.html">Public</a></td><td><a href="../optional-api/web/full-api.html">Full</a></td><td><a href="../optional-api/web.inv">Inventory</a></td></tr>
<tr><td>PerfCheckerPluto 1.0.1</td><td><a href="../optional-api/pluto/public-api.html">Public</a></td><td><a href="../optional-api/pluto/full-api.html">Full</a></td><td><a href="../optional-api/pluto.inv">Inventory</a></td></tr>
<tr><td>PerfCheckerTachikoma 1.0.1</td><td><a href="../optional-api/tachikoma/public-api.html">Public</a></td><td><a href="../optional-api/tachikoma/full-api.html">Full</a></td><td><a href="../optional-api/tachikoma.inv">Inventory</a></td></tr>
</tbody>
</table>
```

The [Core Public API](public-api.md) and [Core Full API](api.md) document Core's
bindings. A companion can define methods of a Core binding: for example,
PerfCheckerWeb defines methods of `PerfChecker.serve_suite`. The Julia signatures,
source links and per-owner provenance retain that distinction. Makie's real WGL
extension documents `PerfChecker.performance_plot_html`; that Core binding is not
an additional export of the extension. Web remains version 1.0.0 alongside Core
1.0.1.

Each inventory is relative to this site's `optional-api/` directory. Inventories
remain separate because a shared Core binding can have different methods in
different owners. They supplement Core's `objects.inv` without replacing entries.
The corresponding `<owner>.toml` files in that directory record the source commit,
Docs and method owners, signatures, source hashes and rendering inputs.

See [installation](../guide/installation.md) for source installation and compatible
worker environments. Generating references does not start a server, open Pluto,
render a plot, run a terminal interface or measure a hardware counter. LinuxPerf
and LIKWID require their documented permissions and native prerequisites; their
explicit Julia executor is not a native CLI, VS Code, Pluto or MCP selector.

The stable Core 1.0.0 site retains its own APIs. These 1.0.1 references are
not injected into an explicit documentation-only refresh of that release.
