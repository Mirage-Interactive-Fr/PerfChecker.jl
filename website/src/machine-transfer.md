```@raw html
<a id="Machine-similarity-and-experimental-transfer"></a>
```

# Machine calibration

Use this when CI and developer machines differ and you want a rough estimate before running a full local suite. The output is an estimate with diagnostics, not a measured local result and never a release gate.

If both runs use one machine, use an [ordinary comparison](tutorials/comparisons.md) instead.

## Machine profiles

```julia
using PerfChecker
profile = machine_profile(label = "runner-a")
println(profile["schema_version"])
println("Label: ", profile["label"])
println("Fingerprint length: ", length(profile["spec_id"]))
println("Limits verified: ", profile["limits_verified"])
```

Expected output:

```text
perfchecker-machine-profile/1
Label: runner-a
Fingerprint length: 64
Limits verified: false
```

Records CPU, architecture, OS, core counts, SIMD width, installed memory and Julia threads.

- `spec_id` identifies a class of specifications, not a physical device.
- Host names and transient CPU load do not enter the hash.
- Record quotas, affinity and container limits explicitly in `limits`; the capture does not verify them.

`similar_machines(target, profiles)` ranks same-OS/architecture profiles by numerical differences and CPU identity — a shortlist, not evidence of comparable performance.

```@raw html
<a id="Small-calibration-battery"></a>
```

## Calibration battery

`estimate_performance(target, references, workload)` is an experimental nearest-neighbour transfer model. Each input record has this shape (the numbers are format examples, not measurements):

```julia
example_record = Dict(
    "machine" => machine_profile(label = "runner-a"),
    "context" => Dict("suite_revision" => "...", "environment" => "...",
        "measurement" => "warm median latency", "unit" => "seconds",
        "resource_policy" => "one pinned core; declared memory limit"),
    "calibration" => Dict("small_compute" => 0.01, "memory" => 0.02, "dispatch" => 0.03),
    "measurements" => Dict("heldout_workload" => 0.5))
result = estimate_performance(example_record, Dict{String, Any}[], "heldout_workload")
println(result["status"])
println("Estimate: ", result["estimate"])
println("CI gate eligible: ", result["ci_gate_eligible"])
println("External validation: ", result["external_validation"])
```

Expected output with no reference machines:

```text
insufficient_evidence
Estimate: nothing
CI gate eligible: false
External validation: not_performed
```

An empty reference set cannot support a prediction. `nothing` means no estimate,
not zero seconds. This example exercises the refusal path with illustrative data.

- Use a small battery that represents the workloads: computation, memory, dispatch, native calls and I/O need different coverage.
- Calibration names must refer to the same frozen workload definitions, with positive times in the same unit.
- The held-out workload must not appear in target calibration.
- At least three shared calibration workloads and two separately labelled reference machines are required.
- Incompatible contexts, OS/architecture and self-prediction are rejected. Duplicate machine labels are errors.

The result is a central estimate plus an envelope widened by calibration errors. **It is not a confidence interval.** Only synthetic controls have been tested; no cross-machine external validation has been performed.

## CI policy

- Use estimates to prioritize the next real measurements or choose representative runners.
- They are never eligible for a regression gate: `ci_gate_eligible = false`.
- A single sample, incompatible contexts or an unstable calibration yield `insufficient_evidence`. PerfChecker never fabricates an estimate.

The CLI exposes `machine --label=runner-a` and `estimate --source=transfer.json` (with `target`, `references` and `workload` fields).
