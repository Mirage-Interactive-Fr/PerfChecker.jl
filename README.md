<p align="center">
  <img src="website/src/public/assets/perfchecker-mark.png" width="180" alt="PerfChecker">
</p>

[![CI](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/actions/workflows/CI.yml)
[![Documentation](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/actions/workflows/Documentation.yml/badge.svg?branch=main)](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/actions/workflows/Documentation.yml)
[![License: MIT](https://img.shields.io/github/license/Mirage-Interactive-Fr/PerfChecker.jl)](LICENSE)

PerfChecker measures and compares the performance of Julia packages across versions, commits, and local changes.

[Documentation](https://perfchecker.mirageinteractive.fr/)

### Measuring live callbacks

`run_scenario` measures an already-loaded callback scenario without generating a
source wrapper or serializing closures:

```julia
using PerfChecker

case = (
    prepare = () -> [3, 1, 2],
    operation = values -> sort!(values),
    verify = (values, result) -> result === values && values == [1, 2, 3],
    cleanup = values -> nothing,
)
bundles = run_scenario(case; id="live_sort", samples=10,
    qualification_limits="Interactive definitions; source-file identity is unavailable")
```

Verification and cleanup run outside the timed operation. The returned ordinary
`RunBundle`s retain collector samples, source/environment qualification and raw
evidence. Declared or discoverable source/environment drift invalidates a run.
Live callbacks share the caller's process, compilation history and other tasks;
these results do not claim isolated workers or portable anonymous functions.
Use `run_scenarios` with a file-backed catalog when process isolation is needed.

Optional `:profile` and `:profile_alloc` collectors require
`exclusive_profiles=true`, granting ownership of the global profile buffers.
Concurrent or nested `run_scenario` calls are rejected; unrelated external
profiling remains the caller's responsibility. Neither allocation traffic nor
process RSS is silently labelled owned-memory footprint.
