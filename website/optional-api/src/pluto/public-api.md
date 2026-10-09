# PerfCheckerPluto public API

This development reference renders the actual Julia docstrings of PerfCheckerPluto
1.0.1 with Core 1.0.1. Notebook generation and Pluto startup are separate actions. Rendering these docstrings performs neither action.

The [full API](full-api.md) is the canonical reference. Full API also includes documented internal bindings.

```@meta
CurrentModule = PerfCheckerPluto
```

```@docs; canonical=false
PerfCheckerPluto
```

```@autodocs; canonical=false
Modules = [PerfCheckerPluto]
Public = true
Private = false
Order = [:constant, :type, :macro, :function]
```
