<p align="center">
  <img src="website/src/public/assets/perfchecker-mark.png" width="180" alt="PerfChecker">
</p>

[![CI](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/actions/workflows/CI.yml/badge.svg?branch=main)](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/actions/workflows/CI.yml)
[![Documentation](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/actions/workflows/Documentation.yml/badge.svg?branch=main)](https://github.com/Mirage-Interactive-Fr/PerfChecker.jl/actions/workflows/Documentation.yml)
[![License: MIT](https://img.shields.io/github/license/Mirage-Interactive-Fr/PerfChecker.jl)](LICENSE)

PerfChecker measures and compares the performance of Julia packages across versions, commits, and local changes.

[Documentation](https://perfchecker.mirageinteractive.fr/)

This review branch strengthens worker shutdown and result acceptance. A returned
table is accepted only after the relevant workers and cleanup have been
qualified; runtime campaigns also retain the actual native termination status.
See [worker lifetime and accepted results](website/src/worker-lifecycle.md) for
ownership, shutdown budgets, recovery and historical-result compatibility.
An interrupted worker constructor counts as cancellation only after an
error-free rollback. Incomplete or faulted cleanup remains a failed suite;
`strict=false` does not hide it. Profile-cache reuse also verifies the acquired
sidecar bytes, without silently recollecting a missing or changed historical
result. The guide separates these integrity checks from authentication,
environment manifests and storage durability.

The branch requires the Malt 1.6 lifecycle API and retains PerfChecker's own
Julia 1.10 compatibility. These are external measurement-tool requirements,
independent of the Julia 1.13 target used to qualify Étendu3D.

This branch's local integration selects the [Malt SDK lifecycle branch](https://gitlab.naze.baffier.fr/etendu3d/Malt.jl/-/tree/release/sdk-1.0)
explicitly. An older Malt installation with the same package name does not
provide that API. Registry-only installation of this source pair is a separate
release step; the targeted verification below does not claim it.
