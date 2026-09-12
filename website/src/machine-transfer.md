# Machine similarity and experimental transfer

Use this when CI and developer machines differ and you want a rough estimate
before running a complete suite locally. First collect comparable workloads on
the donor machines and a small matching calibration set on the target machine.
The output is an estimate with diagnostics, not a measured local result or an
automatic substitute for a release gate. Start with
[ordinary comparisons](tutorials/comparisons.md) if both runs use one machine.

`machine_profile(label="runner-a")` records CPU, architecture, OS, core counts,
SIMD width, installed memory and Julia threads. Its `spec_id` identifies a class
of specifications, not a physical device. Host names and transient CPU load do
not enter the hash. Record quotas, affinity and container limits explicitly in
`limits`; the capture does not claim these have been verified.

`similar_machines(target, profiles)` ranks same-OS/architecture profiles by
relative numerical differences and CPU identity. Missing features remain visible.
This ranking is a shortlist, not evidence of comparable performance.

## Small calibration battery

`estimate_performance(target, references, workload)` is a dependency-free,
experimental nearest-neighbour transfer model. Each input record has the following shape. The numbers below are synthetic
format examples, not measurements of the machine returned by `machine_profile`:

```julia
using PerfChecker
Dict(
    "machine" => machine_profile(label="runner-a"),
    "context" => Dict("suite_revision"=>"commit and workload fingerprint",
        "environment"=>"native and Julia dependency fingerprint",
        "measurement"=>"warm median latency", "unit"=>"seconds",
        "resource_policy"=>"one pinned core; declared memory limit"),
    "calibration" => Dict("small_compute"=>0.01, "memory"=>0.02, "dispatch"=>0.03),
    "measurements" => Dict("heldout_workload"=>0.5))
```

Use an actual small battery representative of the workloads: computation, memory,
dispatch, native library calls and I/O require different coverage. Calibration
names must refer to the same frozen workload definitions. Values are positive
times in the same unit. The held-out workload must not occur in target calibration.

The model fits a median log time ratio per donor. It holds out each calibration
workload in turn and rejects donors whose transfer error exceeds the limit.
At least three shared calibration workloads and two separately labelled reference
machines are required. Incompatible contexts, OS/architecture and self-prediction
are rejected. Duplicate machine labels are errors.

The result supplies a central estimate and an envelope of donor estimates widened
by calibration errors. **This is not a statistical confidence interval.** The
implementation is tested on synthetic controls; cross-machine external validation
has not yet been performed. Machine labels and context hashes are caller-supplied
provenance, not independently attested identities.

## CI policy

Use estimates to prioritize the next actual measurements or select representative
runners. They are never eligible to pass a performance regression gate:
`ci_gate_eligible=false`. A single sample, incompatible contexts, or an unstable
calibration yields `insufficient_evidence` rather than a fabricated estimate.

The CLI exposes `machine --label=runner-a` and `estimate --source=transfer.json`.
The latter accepts `target`, `references` and `workload` fields. Save immutable
source measurements alongside the model input. Before promoting transfer beyond
experimental status, validate with entire machines held out, untouched workloads,
several seeds/sessions and observed interval coverage on real CI runners.
