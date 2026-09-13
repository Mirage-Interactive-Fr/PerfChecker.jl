# Network measurement

Network collectors measure what a workload sends and receives. Application counters report payload; OS counters also capture packets and protocol overhead. Pick a collector that can attribute traffic to your workload **before** using a byte or packet limit.

## Read the numbers

- **Payload bytes** — application data.
- **Interface bytes** — traffic at the interface boundary; includes protocol overhead and other processes.
- **Packet** — a unit of transmitted traffic; one message can become several packets.
- **Drops** — discarded traffic where observed.
- **Latency** — elapsed time for a declared operation.
- **Throughput** — completed operations or bytes per unit time.

High throughput does not imply low latency per request. Always read sent and received counters separately and check the scope before adding totals.

## Attribution levels

- `:network` — counters the workload reports. CI-worthy for those counters.
- `:network_interface` — shared host interface. Not CI-worthy unless the machine is hermetic.
- `:network_isolated` — dedicated Linux network namespace. CI-worthy.
- `measure_isolated_network_command` — complete isolated process tree. CI-worthy, but covers the whole command lifecycle.

The default unprivileged namespace is loopback-only. It suits a service, database fixture, protocol implementation or client/server stack launched together. `external_connectivity = true` attaches an unprivileged `slirp4netns` TAP device for outbound IPv4 and DNS; the user-mode stack adds measurable overhead, which the capability manifest reports.

## WSL2 process-tree capture

On Windows, PerfChecker can launch the same Linux namespace collector through WSL2. `nftables` counts packets; `sysfs` is a fallback.

```julia
using PerfChecker

isolation = NetworkIsolationSpec(provider = :wsl2_netns, distribution = "Ubuntu")
capabilities = network_isolation_capabilities(isolation; probe = true)
capabilities["supported"] || error(capabilities["reason"])

result = measure_isolated_network_command(
    ["julia", "--startup-file=no", "test/fixtures/network_loopback.jl"];
    spec = isolation, directory = pkgdir(PerfChecker), strict = true)

result.sample.packets_sent
result.sample.packets_received
```

CLI form:

```sh
julia --startup-file=no --project=. -e 'using PerfChecker; exit(perfchecker_main(ARGS))' -- network \
  --provider=linux_netns --output=perf/network.json -- \
  julia --startup-file=no perf/workload.jl
```

On Windows use `--provider=wsl2_netns` and optionally `--distribution=Ubuntu`. Add `--external=true` for outbound traffic (selects `tap0` instead of `lo`). Output is omitted by default; opt in with `--include-output=true`. The result is `perfchecker-isolated-network-result/1` with `capture_layer = isolated_interface` and `attribution_scope = isolated_process_tree`.

## Interpretation

- TCP/IP framing, acknowledgements and retransmissions make wire bytes differ from payload bytes. Record both when it matters.
- On loopback, a transfer appears in **both** transmit and receive counters; summing them double-counts.
- A remote response time should include endpoint identity and experiment conditions; it is not an intrinsic package property.
- Windows host-interface collection is available through `Get-NetAdapterStatistics`. Native Windows process-tree attribution through ETW/WFP or Pktmon is not implemented; use the WSL provider.

```@raw html
<a id="Read-the-network-numbers"></a>
```
