# Machine profiles

Capture real machine identity, then explicitly exercise the refusal path without
inventing calibration times:

Start Julia in a project containing PerfChecker (`] add PerfChecker` if needed).

```julia
using PerfChecker
profile = machine_profile(label="local-recipe")
context = Dict("suite_revision"=>"refusal-fixture-v1",
    "environment"=>"local-recipe", "measurement"=>"warm median latency",
    "unit"=>"seconds", "resource_policy"=>"no calibration executed")
target = Dict("machine"=>profile, "context"=>context,
    "calibration"=>Dict{String,Float64}(), "measurements"=>Dict{String,Float64}())
result = estimate_performance(target, Dict{String,Any}[], "heldout")
println((result["status"], result["estimate"], result["ci_gate_eligible"]))
```

```@raw html
<p>Observed output: <strong><code>(&quot;insufficient_evidence&quot;, nothing, false)</code></strong>.
The <a href="../examples/tool-recipes/receipts.json">receipt</a> records a real
<code>perfchecker-machine-profile/1</code> profile, 64-character specification hash and
<code>limits_verified=false</code>; external transfer validation is <code>not_performed</code>.
There is no multi-host calibration dataset here. A useful transfer experiment
needs overlapping real calibration workloads and independent held-out
measurements on distinct machines; see <a href="machine.html#Calibration-limits">machine calibration</a>.</p>
```


::: details Calibration limits

## Calibration limits

A calibration record maps workload IDs to positive elapsed times in seconds. **Shared workloads** are the same IDs measured on both the target machine and a reference machine. At least three are required for each reference. Use at least two distinct reference-machine labels; none may be the target label. Freeze workload definitions and units, and exclude the workload being predicted from the target's calibration record.

The algorithm scales each reference machine's measured result by its typical target/reference calibration ratio. It rejects unstable transfers using leave-one-workload-out error. The returned **envelope** spans the selected references' estimates, widened by that calibration error; it is not a confidence interval or a measurement.

Mismatched contexts, incompatible OS/architecture and self-prediction are refused; duplicate labels are errors. `spec_id` identifies a specification class, not a physical device. Capture does not verify quotas or affinity, and `similar_machines` produces only a shortlist. No cross-machine external validation is published; estimates retain `ci_gate_eligible=false`.

:::
