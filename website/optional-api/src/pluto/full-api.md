# PerfCheckerPluto full API

This reference renders the actual Julia docstrings of PerfCheckerPluto
1.0.1 with Core 1.0.1. Notebook generation and Pluto startup are separate actions. Rendering these docstrings performs neither action.

The [public API](public-api.md) contains exported entry points. Full API also includes documented internal bindings.

```@meta
CurrentModule = PerfCheckerPluto
```

```@docs
PerfCheckerPluto
```

## Index

```@index
Pages = ["full-api.md"]
```

## Docstrings

```@autodocs
Modules = [PerfCheckerPluto]
Public = true
Private = true
Order = [:constant, :type, :macro, :function]
```
