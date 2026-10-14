# PProf

Load `PProf` and `FlameGraphs` together to activate the profile export extension. Replay a
completed bundle without rerunning its workload.

From `examples/kitchen-sink` in the source checkout, run `julia setup.jl extras`. Then start Julia with `julia --project=.controller/extras`. Replace `ACTUAL-PROFILE-RUN` and `ACTUAL-BUNDLE` with paths from your completed profile run.

```julia
using PerfChecker, PProf, FlameGraphs
bundle = read_run_bundle("results/ACTUAL-PROFILE-RUN/bundles/ACTUAL-BUNDLE")
write_folded_profile(bundle, "exports/cpu.folded"; metric="julia.cpu.samples")
write_speedscope_profile(bundle, "exports/cpu.speedscope.json";
    metric="julia.cpu.samples")
write_pprof_profile(bundle, "exports/allocations.pb.gz";
    metric="julia.alloc.bytes", max_samples=1000)
```

```@raw html
<p><code>profiles.jl</code> applies this to CPU, wall and allocation metrics, reporting a
missing stack selection instead of producing an empty profile. The flame graphs
in the <a href="cpu-profile.html">CPU</a>, <a href="wall-profile.html">wall</a> and <a href="allocation-profile.html">allocation</a> pages are observed stack data. A separate replay of the real Bibliography
allocation bundle produced this <a href="../examples/tool-recipes/bibliography-allocations.pb.gz">PProf export</a>,
with its source manifest hash in the <a href="../examples/tool-recipes/receipts.json">export receipt</a>.
The download uses relative runtime filenames; the receipt distinguishes the
original and published export hashes. Stack names, line numbers, samples and
weights are preserved. The adapter quantizes recorded allocation weights into sample repetitions;
<code>max_samples=1000</code> controls that approximation. It collects no new measurements.</p>
```
