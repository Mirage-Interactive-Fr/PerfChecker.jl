# Diagnostic providers

Each diagnostic tool owns its compatibility range and worker adapter here. The
PerfChecker controller does not depend on JET, AllocCheck, SnoopCompile or Aqua.
The worker checks the selected environment, loads the requested tool and runs its
adapter. A missing tool produces `unavailable`; diagnosis does not install it.

To prepare a worker, add its target package and the provider's dependencies to a
dedicated environment before running `diagnose`. The Project.toml beside each
adapter documents that provider's bounds; `catalog.toml` exposes them to interfaces.
Reports record the actual tool version, Julia version and environment provenance.

The standalone diagnostic entry point loads shared runtime files and standard
libraries, without importing PerfChecker. Provider adapters execute only inside
that process. The `controller_loaded` result field supports regression tests of
this isolation boundary.
