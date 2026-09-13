# Network measurement

Network collectors measure the data sent and received by a workload. Application
counters report payload sizes; operating-system counters also capture packets
and protocol overhead. For a runnable example with both, see the
[Oxygen network measurements](real-packages/oxygen.md#4.-Measure-real-network-traffic).

Before using a byte or packet limit in CI, choose a collector that can attribute
the traffic to your workload. A shared interface may also carry other processes'
traffic. The attribution table below describes the available collectors.
Latency is retained as contextual evidence; byte and packet budgets can gate
CI only when the collector's attribution is strong enough.

## Read the network numbers

**Payload bytes** count application data. **Interface bytes** count traffic at
the interface's accounting boundary and can include protocol overhead and
other activity. A **packet** is a unit of transmitted traffic; one application
message can produce several packets. **Drops** count discarded traffic where
the collector observes it. Always read sent and received counters separately
and check the observation scope before adding totals.

**Latency** is elapsed time for a declared operation, while **throughput** is
completed operations or bytes per unit of time. High throughput does not imply
low latency for each request. Bibliography's local `web_render` example formats
content and does not itself measure an HTTP exchange. To study serving that
content, define a client/server workload with explicit request boundaries. The
[measurement guide](guide/understanding-measurements.md) explains elapsed time
and why a profile answers a different question from a duration measurement.

## Attribution levels

| Collector | Scope | Counters | Suitable for blocking CI |
|---|---|---|---|
| `:network` | Explicit application workload | Payload bytes, operations, optional packets/connections/retransmissions | Yes, for the counters reported by the workload |
| `:network_interface` | Shared host interface | Bytes, packets and drops | No; informative unless the machine/interface is otherwise hermetic |
| `:network_isolated` | Worker group inside a dedicated Linux network namespace | Bytes, packets and drops | Yes, for traffic inside the isolated namespace |
| `measure_isolated_network_command` | Complete isolated process tree | Bytes, packets and drops | Yes, but it measures the complete command lifecycle |

The default unprivileged namespace is loopback-only. It is suitable for an
Oxygen service, database fixture, protocol implementation, or client/server
stack launched together. Set `external_connectivity=true` to attach an
unprivileged `slirp4netns` TAP device. This provides outbound IPv4 and DNS while
preserving process-tree attribution; the user-mode network stack adds measurable
overhead, which is identified by the capability manifest. Dependencies and
artifacts should still be prepared before the isolated run.

## WSL2 process-tree capture

This system-level example needs WSL2, a Linux Julia executable and the namespace
tools reported by the capability probe. It uses PerfChecker's supplied loopback
fixture, not Bibliography's local formatter. Prepare the Linux dependencies
before measuring; a Windows environment does not prepare its WSL counterpart.
The provider's availability result explains unsupported prerequisites.


On Windows, PerfChecker can launch the same Linux namespace collector through
WSL2. `nftables` counts input and output packets inside the new namespace;
`sysfs` is retained as a fallback for Linux systems where it works correctly.

```julia
using PerfChecker

isolation = NetworkIsolationSpec(
    provider = :wsl2_netns,
    distribution = "Ubuntu",
)

capabilities = network_isolation_capabilities(isolation; probe = true)
capabilities["supported"] || error(capabilities["reason"])

result = measure_isolated_network_command(
    ["julia", "--startup-file=no", "test/fixtures/network_loopback.jl"];
    spec = isolation,
    directory = pkgdir(PerfChecker),
    strict = true,
)

result.sample.packets_sent
result.sample.packets_received
isolated_network_result_dict(result)
```

The same collector has a CI-oriented command-line entry point:

```sh
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- network \
  --provider=linux_netns --output=perf/network.json -- \
  julia --startup-file=no perf/workload.jl
```

On Windows use `--provider=wsl2_netns` and optionally
`--distribution=Ubuntu`. Add `--external=true` for outbound traffic through
`slirp4netns`; this selects `tap0` instead of `lo`. The command exits with the workload status and writes
`perfchecker-isolated-network-result/1` JSON. Captured stdout and stderr are
omitted by default so reports do not accidentally retain application output;
`--include-output=true` opts into bounded logs.

The `capture_layer` is `isolated_interface` and the command result uses
`attribution_scope = isolated_process_tree`. The `:network_isolated` backend
narrows its snapshots around the feature workload and reports
`isolated_worker_group`.

To run an entire suite inside the namespace, compose the existing commands:

```julia
runtime = JuliaRuntimeSpec(:candidate, "rc")
suite_command = julia_runtime_suite_command(runtime;
    suite = "perf/suite.jl", reports = "perf/results/rc")

run = measure_isolated_network_command(suite_command;
    spec = isolation, directory = pkgdir(PerfChecker), strict = true)
```

The WSL Julia environment and package artifacts must already be instantiated.
PerfChecker remains in the controller; every feature is still executed by a
fresh Malt worker. The namespace is inherited by the controller and its worker
tree, while `:network_isolated` records only the counters surrounding the
feature workload.

## Interpretation

TCP/IP framing, acknowledgements and retransmission alter wire-level counts, so
transport bytes are not expected to equal application payload bytes. Record
both layers when the distinction matters. A remote response time should include
endpoint identity and experiment conditions and should not be treated as an
intrinsic package property.

Windows host-interface collection remains available through
`Get-NetAdapterStatistics`. Native Windows process-tree attribution through
ETW/WFP or Pktmon is not implemented. Use the WSL provider for the documented
namespace workflow; its results describe the Linux guest.
