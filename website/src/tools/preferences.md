# Preferences.jl

Persist thread, warmup and log defaults in the active **controller** project. These APIs require PerfChecker **1.1.0** or newer.

Start Julia in a project containing PerfChecker (`] add PerfChecker` if needed).

```julia
using PerfChecker
set_check_preferences!(threads=2, repeat=false, quiet=true)
check_preferences()
config = PerfConfig(:profile; path=pwd(), threads=1) # explicit value wins
reset_check_preferences!(:threads) # remove local value and inherit again
```

The returned dictionary contains `threads=2`, `repeat=false`, `quiet=true` immediately after the setter. It writes `LocalPreferences.toml` beside the controller's active Project. Reading preferences or running a normal check does not write it. `PerfConfig.path` chooses the workload environment and does not choose preference storage.

Precedence is **collector defaults → inherited preferences → explicit options**. Local preferences override exported project values; a suite freezes its resolved defaults before preparing workers. Changes affect future checks without restarting Julia.

`threads` must be a positive integer representable as `Int`, excluding `Bool`; `repeat` and `quiet` must be Boolean. `repeat` controls optional allocation/profile/network warmup. BenchmarkTools and Chairmarks use their own sampling options. `quiet` suppresses package-management logs, not workload output.

::: details Shared settings, reset and saved evidence

The local file produced by the first setter contains:

```toml
[PerfChecker]
check_threads = 2
check_repeat = false
check_quiet = true
```


```julia
set_check_preferences!(threads=2, export_prefs=true) # Project.toml
reset_check_preferences!(:threads; export_prefs=true)
reset_check_preferences!(block_inheritance=true) # block all three inherited values
```

A reset without keys selects all three settings at the chosen storage level, preserving other packages' preferences. Ordinary reset allows inheritance; `block_inheritance=true` uses Preferences.jl clear markers. Unknown/invalid settings are rejected before writes. No path, command or credential can be saved through these APIs.

Investigations and TestItems use their own explicit scenario/item thread setting (one by default). Saved `check_configuration` retains values, origins and `config_hash`; workers receive resolved values rather than rereading preferences. A cache hit records the current request's configuration; cache identity uses effective values, not whether they came from explicit or persistent options.

:::
