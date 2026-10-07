# Full API

```@raw html
<a id="Julia-API"></a>
```

This is the complete reference generated from PerfChecker's Julia docstrings,
including documented implementation hooks. Start with the [Public API](public-api.md)
for supported package entry points or [Quickstart](../guide/first-check.md) for an
executable introduction. Internal bindings support extensions and maintenance;
their behavior can change independently of the exported interface.

Each entry retains its Julia signature, argument and result documentation, and a
source link pinned to the revision used to build this site. This page keeps the
historical `reference/api` route and function anchors.

- Existing tests: `discover_testitems`, `run_testitems`.
- Inline experiment: `@check`.
- Custom workloads and version matrices: `SoftwareSuite`, `plan_suite`, `run_suite`.
- Shared scenarios: `run_scenarios`, `diagnose`, `compare_scenarios`.
- Optional MCP APIs: `chat_advice` for bounded conversation; `implement_advice` for an explicit tool on a caller-owned isolated checkout. The caller owns checkpointing and diff review outside the VS Code extension; see [the MCP guide](../mcp-advisor.md).

## Interface packages

Some entry points are implemented by an interface package. Install and load the owner to get its method.

- **PerfCheckerWeb** — `serve_suite`, `register_oxygen_routes!`, `register_testitem_routes!`, `studio_token_authenticator`, `run_studio_agent`.
- **PerfCheckerPluto** — `prepare_pluto_dashboard`, `launch_pluto_dashboard`, `write_suite_notebook`, `write_investigation_notebook`.
- **PerfCheckerMakie** — `performance_figure`, `suite_dashboard`, `checkres_to_boxplots`, `checkres_to_scatterlines`, `checkres_to_pie`.
- **PerfCheckerMakie + WGLMakie** — `performance_plot_html`.

## Index

```@index
Modules = [PerfChecker]
```

## Docstrings

```@autodocs
Modules = [PerfChecker]
Public = true
Private = true
Order = [:module, :constant, :type, :macro, :function]
```

```@raw html
<a id="Interface-API-ownership"></a>
<a id="Public-docstrings"></a>
```
