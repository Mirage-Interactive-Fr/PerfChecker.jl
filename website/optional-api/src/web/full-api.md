# PerfCheckerWeb full API

This development reference renders the actual Julia docstrings of PerfCheckerWeb
1.0.0 with Core 1.0.1. The companion version is 1.0.0; this reference describes its source alongside Core development 1.0.1. Importing the owner does not register routes or start a server.

The [public API](public-api.md) contains exported entry points. Full API also includes documented internal bindings.

```@meta
CurrentModule = PerfCheckerWeb
```

```@docs
PerfCheckerWeb
```

## Index

```@index
Pages = ["full-api.md"]
```

## Docstrings

```@autodocs
Modules = [PerfCheckerWeb]
Public = true
Private = true
Order = [:constant, :type, :macro, :function]
```
