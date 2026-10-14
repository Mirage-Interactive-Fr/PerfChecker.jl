# LIKWID

Count one callback invocation with the explicit `PerfCheckerLIKWID` companion. First prepare its worker project using **Prepare the explicit worker** below, then start Julia in that project. The companion does not change kernel permissions or affinity.

```julia
using PerfChecker, PerfCheckerLIKWID
# Pick the first CPU inside the current inherited Linux affinity, without repinning.
line = only(filter(l -> startswith(l, "Cpus_allowed_list:"),
    split(read("/proc/self/status", String), '\n')))
cpu = parse(Int, first(split(first(split(strip(split(line, ':')[2]), ',')), '-')))
called = Ref(false)
result = measure_counters(;
    event_set="INSTR_RETIRED_ANY:FIXC0,CPU_CLK_UNHALTED_CORE:FIXC1",
    cpuids=[cpu], units=Dict("INSTR_RETIRED_ANY"=>"1", "CPU_CLK_UNHALTED_CORE"=>"1")) do
    called[] = true
    sum(1:10000)
end
println((result.status, result.reason, called[], length(result.records)))
```

```@raw html
<p>Observed output: <strong><code>(:unavailable, &quot;library_unavailable&quot;, false, 0)</code></strong>.
The host lacks <code>liblikwid</code>; the <a href="../examples/tool-recipes/likwid.json">receipt</a>
records the real refusal, selected CPU and resolved versions. No callback ran.
A permitted native installation is required for positive hardware evidence;
count units are explicit and backend access mode determines attribution.</p>
```


::: details Prepare the explicit worker

PerfCheckerLIKWID 1.0.1 is registered in General. Use a separate worker project:

```julia
using Pkg
Pkg.activate("perf/likwid-worker")
Pkg.add(["PerfChecker", "PerfCheckerLIKWID"])
Pkg.add(Pkg.PackageSpec(name="LIKWID", version="0.4.6"))
```

Start Julia with `--project=perf/likwid-worker` for the callback above. Install your measured target in that worker project separately. LIKWID 0.4.6 requires PrettyTables 3; the other companion requires PrettyTables 2. Native liblikwid and permitted CPU counter access must already exist. Choose exact event/counter pairs supported by your hardware and CPUs inside inherited affinity; group aliases and automatic repinning are refused. Published Core has a [known ARM import limitation](../guide/overview.md#ARM-installations).

:::

::: details Collection window

The suite integration runs operation and synchronization once, then stops counters before the oracle. It has no implicit warmup. LinuxPerf counts the calling OS thread's user-space execution, excluding other threads/processes; enabled/running times are separate nanosecond values. LIKWID measures selected CPUs within inherited affinity; access mode and PID configuration determine attribution and direct/daemon modes may include unrelated activity. LIKWID group time is in seconds; raw event units are explicit. Counts and CPU cycles use unit `1`, not seconds. An unavailable result is missing evidence. LinuxPerf's `counter_not_scheduled` refusal can occur after the operation, so inspect its lifecycle before retrying.

Use `run_counter_suite` or an explicit `counter_executor` in a Julia suite runner. Default CLI, VS Code, Pluto and MCP selectors do not offer these companions.

:::
