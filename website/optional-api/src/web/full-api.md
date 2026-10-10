# PerfCheckerWeb full API

This reference renders the actual Julia docstrings of PerfCheckerWeb
1.0.0 with Core from the selected source revision. The companion retains its own
version. Importing the owner does not register routes or start a server.

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
