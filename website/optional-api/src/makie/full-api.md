# PerfCheckerMakie full API

This reference renders the actual Julia docstrings of PerfCheckerMakie
1.0.1 with Core from the selected source revision. The WGLMakie/Bonito extension
is loaded to document its real HTML method. Documentation generation does not
render a figure or start a server.

The [public API](public-api.md) contains exported entry points. Full API also includes documented internal bindings.

```@meta
CurrentModule = PerfCheckerMakie
```

```@docs
PerfCheckerMakie
```

## Index

```@index
Pages = ["full-api.md"]
```

## Docstrings

```@autodocs
Modules = [PerfCheckerMakie]
Public = true
Private = true
Order = [:constant, :type, :macro, :function]
```

## Optional WGLMakie method

This method belongs to a Core binding and is defined by the loaded Makie companion
extension. Its docstring is rendered from that extension, not copied from Core.

```@docs
PerfChecker.performance_plot_html(::PerfChecker.PerformancePlot)
```

## Internal WGLMakie helpers

These helpers implement inspection of recorded points in exported figures.

```@autodocs
Modules = [Base.get_extension(PerfCheckerMakie, :WGLMakieExt)]
Public = false
Private = true
Filter = value -> value !== PerfChecker.performance_plot_html
Order = [:function]
```
