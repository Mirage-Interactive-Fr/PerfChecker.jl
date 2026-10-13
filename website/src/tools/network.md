# Network

From `examples/kitchen-sink` in the source checkout, prepare one Linux controller for both scripts. These scripts require Linux or WSL:

```sh
julia setup-linux.jl
julia --project=.controller/linux oxygen/network.jl
julia --project=.controller/linux oxygen/network-isolated.jl
```

For the public API below, start Julia with `julia --project=.controller/linux`. It checks capability before capture:

```julia
using PerfChecker
spec = NetworkIsolationSpec(provider=:linux_netns, interface="lo")
capabilities = network_isolation_capabilities(spec; probe=true)
if capabilities["supported"]
    result = measure_isolated_network_command(
        [Base.julia_cmd().exec..., "--project=.controller/linux", "oxygen/network.jl"];
        spec, timeout_seconds=180)
    display(isolated_network_result_dict(result))
else
    display(capabilities)
end
```

```@raw html
<p>The <a href="../examples/real-packages/oxygen-network/isolation.json">actual isolated receipt</a>
records <code>supported=true</code>, <code>executed=true</code>, exit 0 and <strong>120 verified requests</strong>.
The <code>linux-netns-nftables</code> provider observed <strong>69,465,109 bytes sent</strong> and
<strong>69,466,045 bytes received</strong>, with zero discarded packets. Capture scope is the
isolated process tree over its lifecycle, <strong>13.662857426 s</strong>, not pure HTTP
handler latency. Ordinary interface counters include unrelated traffic unless
isolation establishes attribution.</p>
```

::: details Recorded network samples

```@raw html
<InteractiveRecordedPlot source="/examples/real-packages/oxygen-network/network.plot.json" html="/examples/real-packages/oxygen-network/network.html" title="Observed loopback network samples" />
```

:::


::: details Attribution and platform options

- `:network` records application-reported counters. They describe payload only when that is the workload's counter contract.
- `:network_interface` observes a shared host interface; unrelated traffic prevents attribution unless the host is hermetic.
- `:network_isolated` uses a dedicated namespace; `measure_isolated_network_command` covers the full isolated command tree.

Loopback observes the transfer in both transmit and receive counters: do not sum them as payload. The default unprivileged namespace is loopback-only. `external_connectivity=true` uses slirp4netns for outbound IPv4/DNS and adds user-mode-stack overhead. Windows can use `NetworkIsolationSpec(provider=:wsl2_netns, distribution="Ubuntu")`; the published capture above is Linux evidence, not a WSL recording. Native Windows process-tree attribution through ETW/WFP/Pktmon is not implemented. Host-interface counters use Get-NetAdapterStatistics.

:::
