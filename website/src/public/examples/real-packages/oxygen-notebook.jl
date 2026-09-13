### A Pluto.jl notebook ###
# v0.20.0
using Markdown
using InteractiveUtils

# ╔═╡ b047a994-7174-4941-a972-cc1470020001
begin
    import Pkg
    example_root = get(ENV, "PERFCHECKER_EXAMPLE_ROOT", @__DIR__)
    Pkg.activate(joinpath(example_root, ".controller/pluto"))
    using PerfChecker, PerfCheckerMakie, WGLMakie, PlutoUI, JSON, UnicodePlots
    include(joinpath(example_root, "oxygen/service.jl"))
    include(joinpath(example_root, "replay.jl"))
end

# ╔═╡ b047a994-7174-4941-a972-cc1470020002
md"""# Oxygen: route, serialize, send, inspect
Run `julia +1.12 setup.jl pluto` from `examples/kitchen-sink` before opening this file.
Keep the notebook there, or set `PERFCHECKER_EXAMPLE_ROOT` to that directory.

First isolate a feature without a socket. Then inspect the complete patch
history. Finally look at real loopback traffic. A router timing cannot measure
network packets: the two experiments have different boundaries.
"""

# ╔═╡ b047a994-7174-4941-a972-cc1470020003
@bind feature Select(collect(EventService.HTTP_FEATURES))

# ╔═╡ b047a994-7174-4941-a972-cc1470020004
begin
    case = EventService.feature_case(feature)
    request = case.prepare()
    response = case.operation(request)
    @assert case.verify(request, response)
    (feature = feature, status = response.status, response_bytes = length(response.body), oracle_passed = true)
end

# ╔═╡ b047a994-7174-4941-a972-cc1470020005
md"""## Measure the selected release range
```sh
julia --project=.controller/oxygen oxygen/features.jl plan
julia --project=.controller/oxygen oxygen/features.jl quick
julia --project=.controller/oxygen oxygen/features.jl history 1.10.0 1.11.0
julia --project=.controller/oxygen oxygen/measure.jl history
```
The catalogue contains 14 releases: one per older minor series, then every
patch in 1.10 and 1.11, from 1.0.0 to 1.11.0.
The same seven feature cases run separately. Thirty warmed samples are collected
for each case/version; each sample gets a fresh request. Oxygen determines its
own dependency compatibility: DataStructures is not paired with selected Oxygen tags.
"""

# ╔═╡ b047a994-7174-4941-a972-cc1470020006
begin
    public_root = normpath(joinpath(example_root, "../../website/src/public/examples/real-packages"))
    figure_root = joinpath(public_root, "oxygen-features")
    catalog = JSON.parsefile(joinpath(figure_root, "catalog.json"))
    matching = filter(row -> get(row, "workload", "") == feature * "_http" && row["kind"] == "normalized_metrics", catalog["views"])
    overlay = saved_plot(joinpath(figure_root, only(matching)["json"]))
end

# ╔═╡ b047a994-7174-4941-a972-cc1470020007
performance_figure(overlay)

# ╔═╡ b047a994-7174-4941-a972-cc1470020008
terminal_plot(overlay)

# ╔═╡ b047a994-7174-4941-a972-cc1470020009
md"""## Count real traffic
On Linux, or inside WSL, from the example directory:
```sh
julia --startup-file=no setup-linux.jl
julia --startup-file=no --project=.controller/linux oxygen/network.jl
julia --startup-file=no --project=.controller/linux oxygen/network-history.jl
```
The script starts an echo endpoint and stops it in `finally`. Each payload size
receives 30 warmed requests, checked byte-for-byte. Interface counters include
protocol overhead. Loopback reports both transmission and reception for the
same transfer: summing them would double-count traffic.

The idle control checks for unrelated loopback traffic. These are whole-interface
observations, not a proof of process attribution. Latency includes the client,
server and scheduler in one process; it is not remote-network latency.
"""

# ╔═╡ b047a994-7174-4941-a972-cc1470020010
PlutoUI.LocalResource(joinpath(public_root, "oxygen-network", "network.svg"))

# ╔═╡ b047a994-7174-4941-a972-cc1470020011
begin
    network = JSON.parsefile(joinpath(public_root, "oxygen-network", "latest.json"))
    [(payload_bytes = row["payload_bytes"], samples = length(row["samples"]),
        minimum_seconds = minimum(s["workload_seconds"] for s in row["samples"]),
        minimum_packets_sent = minimum(s["packets_sent"] for s in row["samples"])) for row in network["records"]]
end

# ╔═╡ b047a994-7174-4941-a972-cc1470020012
md"""## Explain the costs and replay the result
```sh
julia --project=. oxygen/measure.jl profiles
julia setup.jl analyzers
julia --project=.controller/analyzers scenarios.jl diagnose oxygen oxygen-heap
julia setup.jl extras
julia --project=.controller/extras drwatson.jl run oxygen
julia --project=.controller/extras profiles.jl results/YOUR-PROFILE-RUN exports/oxygen-profiles
julia setup.jl web
julia --project=.controller/web web.jl results/YOUR-RUN
```
CPU and wall profiles locate sampled work and waiting; allocation profiles
locate allocated objects. JET, AllocCheck and SnoopCompile address inference,
allocation sites and compilation. These observations are not interchangeable
with ordinary timing. Run the same correctness oracle after changing a handler.

The Web interface (Oxygen) uses its own Oxygen instance. It does not force the target worker
to run that version. VS Code and the terminal read the same saved suite reports;
`controller-notebook.jl oxygen-features` generates a Pluto controller for launching selected cases.
"""

# ╔═╡ b047a994-7174-4941-a972-cc1470020013
md"""## Open the full recorded catalogue
The timing catalogue contains separate absolute metrics, distributions and
release deltas. The profile catalogue concerns the 2,048-event application heap
request, a different workload from the seven small feature requests.
Pies group allocations below 5%; the other profile views retain detailed sites.
"""

# ╔═╡ b047a994-7174-4941-a972-cc1470020014
@bind evidence_family Select(["oxygen-features" => "Seven HTTP features", "oxygen" => "Application routes", "oxygen-profiles" => "Application profiles"])

# ╔═╡ b047a994-7174-4941-a972-cc1470020015
evidence_catalog = JSON.parsefile(joinpath(public_root, evidence_family, "catalog.json"))

# ╔═╡ b047a994-7174-4941-a972-cc1470020016
@bind evidence_view Select([row["json"] => row["title"] * " · " * row["label"] for row in evidence_catalog["views"]])

# ╔═╡ b047a994-7174-4941-a972-cc1470020017
performance_figure(saved_plot(joinpath(public_root, evidence_family, evidence_view)))

# ╔═╡ b047a994-7174-4941-a972-cc1470020018
@bind diagnostic_figure Select([
    "oxygen-network/history-64.svg" => "Network history: 64 bytes",
    "oxygen-network/history-4096.svg" => "Network history: 4 KiB",
    "oxygen-network/history-65536.svg" => "Network history: 64 KiB",
    "oxygen-network/history-1048576.svg" => "Network history: 1 MiB",
    "oxygen-diagnostics/latency.svg" => "Loading and first-call latency",
    "oxygen-diagnostics/gc.svg" => "Garbage collection",
    "oxygen-diagnostics/memory.svg" => "Reachable Julia memory",
    "oxygen-diagnostics/locks.svg" => "Observed lock conflicts",
    "oxygen-diagnostics/heap-types.svg" => "Whole-worker heap categories",
    "oxygen-native/massif-1.svg" => "Native heap, including process startup"])

# ╔═╡ b047a994-7174-4941-a972-cc1470020019
PlutoUI.LocalResource(joinpath(public_root, diagnostic_figure))

# ╔═╡ b047a994-7174-4941-a972-cc1470020020
(
    diagnostics=JSON.parsefile(joinpath(public_root, "oxygen-diagnostics", "diagnosis.json")),
    quality_and_heap=JSON.parsefile(joinpath(public_root, "oxygen-diagnostics", "additional.json")),
    native=JSON.parsefile(joinpath(public_root, "oxygen-native", "summary.json")),
    network_isolation=JSON.parsefile(joinpath(public_root, "oxygen-network", "isolation.json")),
)

# ╔═╡ Cell order:
# ╠═b047a994-7174-4941-a972-cc1470020001
# ╟─b047a994-7174-4941-a972-cc1470020002
# ╠═b047a994-7174-4941-a972-cc1470020003
# ╠═b047a994-7174-4941-a972-cc1470020004
# ╟─b047a994-7174-4941-a972-cc1470020005
# ╠═b047a994-7174-4941-a972-cc1470020006
# ╠═b047a994-7174-4941-a972-cc1470020007
# ╠═b047a994-7174-4941-a972-cc1470020008
# ╟─b047a994-7174-4941-a972-cc1470020009
# ╠═b047a994-7174-4941-a972-cc1470020010
# ╠═b047a994-7174-4941-a972-cc1470020011
# ╟─b047a994-7174-4941-a972-cc1470020012
# ╟─b047a994-7174-4941-a972-cc1470020013
# ╠═b047a994-7174-4941-a972-cc1470020014
# ╠═b047a994-7174-4941-a972-cc1470020015
# ╠═b047a994-7174-4941-a972-cc1470020016
# ╠═b047a994-7174-4941-a972-cc1470020017
# ╠═b047a994-7174-4941-a972-cc1470020018
# ╠═b047a994-7174-4941-a972-cc1470020019
# ╠═b047a994-7174-4941-a972-cc1470020020
