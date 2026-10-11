# PerfCheckerWeb public API

This reference renders the actual Julia docstrings of PerfCheckerWeb
1.0.0 with Core from the selected source revision. The companion retains its own
version. Importing the owner does not register routes or start a server.

The [full API](full-api.md) is the canonical reference. Full API also includes documented internal bindings.

```@meta
CurrentModule = PerfCheckerWeb
```

```@docs; canonical=false
PerfCheckerWeb
```

```@autodocs; canonical=false
Modules = [PerfCheckerWeb]
Public = true
Private = false
Order = [:constant, :type, :macro, :function]
```
