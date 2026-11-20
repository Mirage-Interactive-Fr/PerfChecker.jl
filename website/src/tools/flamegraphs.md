# FlameGraphs

Export recorded stack weights for tools that read folded stacks or Speedscope. Load FlameGraphs and PProf together; replaying a bundle collects no new samples.

From `examples/kitchen-sink` in the source checkout, run `julia setup.jl extras`. Then start Julia with `julia --project=.controller/extras` for the code below.

```julia
using PerfChecker, FlameGraphs, PProf
# Replace ACTUAL-PROFILE-RUN and ACTUAL-BUNDLE with paths from your completed profile run.
bundle = read_run_bundle("results/ACTUAL-PROFILE-RUN/bundles/ACTUAL-BUNDLE")
write_folded_profile(bundle, "exports/cpu.folded"; metric="julia.cpu.samples")
write_speedscope_profile(bundle, "exports/cpu.speedscope.json";
    metric="julia.cpu.samples")
```

The [recorded DataStructures CPU and wall stacks](../real-packages/datastructures.md) and [interactive CPU capture](cpu-profile.md) provide actual source weights. The supplied `examples/kitchen-sink/profiles.jl` exports these metrics and reports a missing selection instead of writing an empty profile. The [PProf receipt](pprof.md) records a separate export of a genuine allocation bundle.

Flame width represents the selected recorded weight. It does not show elapsed chronology or compare releases.
