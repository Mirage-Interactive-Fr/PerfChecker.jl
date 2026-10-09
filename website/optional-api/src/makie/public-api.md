# PerfCheckerMakie public API

This development reference renders the actual Julia docstrings of PerfCheckerMakie
1.0.1 with Core 1.0.1. The WGLMakie/Bonito extension is loaded to document its real HTML method. Documentation generation does not render a figure or start a server.

The [full API](full-api.md) is the canonical reference. Full API also includes documented internal bindings.

```@meta
CurrentModule = PerfCheckerMakie
```

```@docs; canonical=false
PerfCheckerMakie
```

```@autodocs; canonical=false
Modules = [PerfCheckerMakie]
Public = true
Private = false
Order = [:constant, :type, :macro, :function]
```

## Optional WGLMakie method

This method belongs to a Core binding and is defined by the loaded Makie companion
extension. Its docstring is rendered from that extension, not copied from Core.

```@docs; canonical=false
PerfChecker.performance_plot_html(::PerfChecker.PerformancePlot)
```
