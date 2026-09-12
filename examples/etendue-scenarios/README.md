# Étendue consumer scenarios

These ordinary Julia factories share the exact operation and oracle between
`runtests.jl` and `scenarios.toml`. They require EtendueContracts, EtendueGeometry
and EtendueGameIR in a separately prepared environment. The test file does not
load PerfChecker. No engine project or manifest is modified by these examples.

```julia
include("examples/etendue-scenarios/runtests.jl")
using PerfChecker
catalog = load_scenario_catalog("examples/etendue-scenarios/scenarios.toml")
runs = run_scenarios(catalog; project="path/to/prepared/environment",
    samples=10, threads=3, reports="perf/results/etendue")
```

The geometry case checks every translated coordinate independently. The GameIR
cases check known valid and deliberately unknown operations. Both implementations
use fresh state per sample; workspace preparation stays outside timing. This
qualifies these operations, not rendering, physics, native exports or the entire
engine. Compare before/after within each implementation; cross-implementation
measurements remain separate results.

In VS Code, open this directory and set `perfchecker.runnerProject` and
`perfchecker.scenarioProject` to the prepared environment, then set
`perfchecker.scenarioCatalog` to `scenarios.toml`. Discover, select, measure and
diagnose from the investigation panel. The lab's `.lab/engine` environment is a
local example, not a portable dependency lockfile.
