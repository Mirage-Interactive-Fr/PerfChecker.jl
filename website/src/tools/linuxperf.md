# LinuxPerf

Count one callback invocation with the explicit `PerfCheckerLinuxPerf` companion. First prepare its worker project using **Prepare the explicit worker** below, then start Julia in that project. The companion does not change kernel permissions or affinity.

```julia
using PerfChecker, PerfCheckerLinuxPerf
called = Ref(false)
result = measure_counters(; events=["instructions", "cpu-cycles"]) do
    called[] = true
    sum(1:10000)
end
println((result.status, result.reason, called[], length(result.records)))
```

```@raw html
<p>Observed on Linux x86_64/Julia 1.13.1:
<strong><code>(:unavailable, &quot;permission_denied&quot;, false, 0)</code></strong>.
The <a href="../examples/tool-recipes/linuxperf.json">actual receipt</a> preserves dependency
versions and environment hashes. The callback did not execute, so there is no
counter plot or performance result. With permission, scope is the calling OS
thread's user-space execution; cycles have count unit <code>1</code>, not seconds.</p>
```


::: details Prepare the explicit worker

PerfCheckerLinuxPerf 1.0.1 is registered in General. Use a separate worker project:

```julia
using Pkg
Pkg.activate("perf/linuxperf-worker")
Pkg.add(["PerfChecker", "PerfCheckerLinuxPerf"])
Pkg.add(Pkg.PackageSpec(name="LinuxPerf", version="0.4.2"))
```

Start Julia with `--project=perf/linuxperf-worker` for the callback above. Install your measured target in that worker project separately. LinuxPerf 0.4.2 requires PrettyTables 2; the other companion requires PrettyTables 3. The kernel must permit perf events on a supported little-endian Linux x86_64, i686 or aarch64 ABI; architecture guards do not qualify positive hardware counts. Published Core has a [known ARM import limitation](../guide/overview.md#ARM-installations).

:::

::: details Collection window

The suite integration runs operation and synchronization once, then stops counters before the oracle. It has no implicit warmup. LinuxPerf counts the calling OS thread's user-space execution, excluding other threads/processes; enabled/running times are separate nanosecond values. LIKWID measures selected CPUs within inherited affinity; access mode and PID configuration determine attribution and direct/daemon modes may include unrelated activity. LIKWID group time is in seconds; raw event units are explicit. Counts and CPU cycles use unit `1`, not seconds. An unavailable result is missing evidence. LinuxPerf's `counter_not_scheduled` refusal can occur after the operation, so inspect its lifecycle before retrying.

Use `run_counter_suite` or an explicit `counter_executor` in a Julia suite runner. Default CLI, VS Code, Pluto and MCP selectors do not offer these companions.

:::
