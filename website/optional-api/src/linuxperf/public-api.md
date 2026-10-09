# PerfCheckerLinuxPerf public API

This reference uses the actual Julia docstrings of PerfCheckerLinuxPerf
1.0.1. These APIs are absent from the stable PerfChecker 1.0.0 source. Rendering
documentation does not execute a counter window or qualify hardware availability.

The [full API](full-api.md) is the canonical reference. The companion requires an
explicit Julia executor; it is not a native CLI, VS Code, Pluto or MCP selector.

```@meta
CurrentModule = PerfCheckerLinuxPerf
```

```@docs; canonical=false
PerfCheckerLinuxPerf
```

```@autodocs; canonical=false
Modules = [PerfCheckerLinuxPerf]
Public = true
Private = false
Order = [:constant, :type, :macro, :function]
```
