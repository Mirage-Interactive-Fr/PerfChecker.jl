# Julia API

This page indexes the documented public API exported by `PerfChecker`. Start
with [your first result](../guide/first-check.md) for an executable introduction.
Use `discover_testitems` and `run_testitems` for existing tests, `@check` for a
direct experiment, or `SoftwareSuite`, `plan_suite` and `run_suite` for custom
workloads and version matrices.
Some entry points gain methods only after their extension or satellite package
is loaded. The shared function belongs to PerfChecker, so its docstring remains
available from a minimal controller. Loading all UI frameworks is not required
to build this reference.

## Interface API ownership

The satellites export the same function bindings as the engine. Install and load
the owner below to obtain its implementation; this is also how the same calls
remain available during migration from the former extension layout.

| Package | Public entry points |
| --- | --- |
| PerfCheckerWeb | [`serve_suite`](@ref), [`register_oxygen_routes!`](@ref), [`register_testitem_routes!`](@ref), [`studio_token_authenticator`](@ref), [`run_studio_agent`](@ref) |
| PerfCheckerPluto | [`prepare_pluto_dashboard`](@ref), [`launch_pluto_dashboard`](@ref), [`write_suite_notebook`](@ref), [`write_investigation_notebook`](@ref) |
| PerfCheckerMakie | [`performance_figure`](@ref), [`suite_dashboard`](@ref), [`checkres_to_boxplots`](@ref), [`checkres_to_scatterlines`](@ref), [`checkres_to_pie`](@ref), [`table_to_pie`](@ref) |
| WGLMakie extension of PerfCheckerMakie | [`performance_plot_html`](@ref) |

See [interface installation](../interfaces/packages.md) for separate environment
setup and [extensions and providers](extensions.md) for the remaining small
interoperability extensions. Diagnostic adapters are internal worker entry points;
their supported public API is [`diagnose`](@ref) and [`diagnostic_capabilities`](@ref).

## Index

```@index
Modules = [PerfChecker]
```

## Public docstrings

```@autodocs
Modules = [PerfChecker]
Public = true
Order = [:module, :constant, :type, :macro, :function]
```
