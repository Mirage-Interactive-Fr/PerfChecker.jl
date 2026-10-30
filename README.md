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
The branch requires the Malt 1.6 lifecycle API. PerfChecker remains an external
measurement tool with its own Julia compatibility policy, independent of the
Julia 1.13 target used to qualify Étendu3D.
