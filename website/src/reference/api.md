# Julia API

The public API exported by `PerfChecker`. For an executable introduction, start with [Quickstart](../guide/first-check.md).

- Existing tests: `discover_testitems`, `run_testitems`.
- Inline experiment: `@check`.
- Custom workloads and version matrices: `SoftwareSuite`, `plan_suite`, `run_suite`.
- Shared scenarios: `run_scenarios`, `diagnose`, `compare_scenarios`.

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
Order = [:module, :constant, :type, :macro, :function]
```

```@raw html
<a id="Interface-API-ownership"></a>
<a id="Public-docstrings"></a>
```
