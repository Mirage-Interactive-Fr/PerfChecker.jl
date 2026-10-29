# PkgEval

Check installation and package tests of an exact registered release on Julia 1.13. PkgEval is an **external Linux sandbox tool**, used by the optional **Registered PkgEval** workflow; it is not a PerfChecker performance collector. This SDK pins both its controller and evaluation runtime to 1.13; it does not schedule nightly runs.

To evaluate an installed release, open **Actions → Registered PkgEval → Run workflow** and select `source_kind=registered`, its `package_version`, a `general_revision` and optionally the expected registered tree. The selector resolves immutable source identity before evaluation.

The historical [completed Core 1.1.0 run](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/actions/runs/38150116805) tested registered tree `753e41cad1c984640a2337b314b70ad6932626ad` (release commit `4e81603c57b47bc08372992492fdf2cbbd718b3b`). Its [recorded result](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/issues/29#issuecomment-6111222715) is preserved below; its nightly result is not an SDK target:

| Runtime | Upstream status | Package assertions | Configuration |
| --- | --- | --- | --- |
| Julia 1.13.1 stable | `test` | 2,380 PASS; 1 Broken | Full suite; shared cache disabled; upstream compilation policy |
| Julia 1.14.0-DEV.3606 nightly | `test` | 2,380 PASS; 1 Broken | Same policy, evaluated separately |

Both used a **configured 90-minute sandbox budget**. That is a limit, not measured duration. These results establish the selected release's package-test outcome on those runtimes; they do not measure speedups or qualify all interfaces/hardware counters.

::: details Read artifacts and choose another source

New SDK runs emit `pkgeval-request` and `pkgeval-1.13`; the historical run above used `pkgeval-stable` and `pkgeval-nightly`. Match request source kind, version/tree, General/controller revisions and workflow identity. Inspect each `result.toml`, `evaluation.log` and `PkgEval-Manifest.toml`, including status/reason and phase-completion fields. A successful package-test status is `test`. Test-phase `duration_seconds` is CPU time in the pinned controller; the final “PkgEval … after …s” log line is total elapsed sandbox wall time. Missing/zero unavailable timing fields must not become zero-cost claims.

The completed run's stable artifact `11707536498` has SHA-256 `2e05e950999151f895bc11a3b00ec3a251a609ceefb76b7b50f28ad7717cf04b`; nightly artifact `11707694207` has SHA-256 `ca6fd33ed193f61330379540b6eb7046b9a024442b4e995c23bf41530e7da1a7`. The original receipts remain unchanged.

For an unpublished candidate use `source_kind=git_candidate`, a lowercase full 40-character `candidate_revision`, and a General revision for dependencies; leave version/expected-tree fields empty. Candidate records identify repository/revision and do not claim registered-tree verification. A candidate pass cannot repair an immutable registered archive.

Manual defaults are `package_images=upstream` and `time_limit_minutes=45`; selecting 90 gives 5,400 seconds for the complete sandbox evaluation and a separate 120-minute job limit. Setup, installation, precompilation and testing share the sandbox budget. `package_images=yes` changes compilation policy; do not equate that outcome with upstream-default qualification. Scheduled source selection/configuration is recorded in the workflow request.

[Earlier 45-minute attempts](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/actions/runs/38145884338) remain failures: stable reached `kill/time_limit` without an observed failed assertion, while nightly failed downloading Julia (code 28) before tests. The older [1.0.1 evaluation](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/actions/runs/38044386943) remains its own failed archive result. A later pass does not rewrite any of these receipts. Observer `cleanup_complete` describes observer-owned resources, not a guarantee that every process on the host stopped.

Local use requires PkgEval's Linux/kernel/container prerequisites. See its [setup instructions](https://github.com/JuliaCI/PkgEval.jl#quick-start).

:::
