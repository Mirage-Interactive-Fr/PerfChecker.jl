# Shared CPU, threaded, CUDA and distributed cases

`cases.jl` uses ordinary Julia functions and does not load PerfChecker. The CPU and threaded affine transformations use the same oracle. CUDA runs the common broadcast operation on `CuArray`; synchronization is inside the measured operation and before verification. Allocation and cleanup of state remain outside timing. Availability requires both the CUDA package and a functional device.

`distributed_sum` creates two workers during preparation, includes communication and completion in the operation, and removes the workers during cleanup. It measures an operation with fresh workers, not steady-state reuse of a persistent distributed cluster. Startup costs are outside the operation measurement. A failed preparation cleans up workers it already created.

Run ordinary tests with `julia --project=examples/backend-scenarios examples/backend-scenarios/test/runtests.jl`. For PerfChecker, prepare a separate controller environment with PerfChecker and BenchmarkTools, optionally CUDA, then call `run_scenarios(load_scenario_catalog("examples/backend-scenarios/scenarios.toml"); project="your-controller", threads=3)`. Missing packages or devices produce `unavailable`, never a passed oracle.

This example establishes a portable scenario contract. It does not qualify AMD, Metal, oneAPI or NPU devices. An NPU case can supply the same preparation/operation/synchronization/oracle/cleanup functions once its actual runtime and device are available.
