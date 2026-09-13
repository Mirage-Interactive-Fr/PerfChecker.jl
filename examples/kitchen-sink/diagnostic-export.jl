using CairoMakie, JSON
length(ARGS) == 2 || error("Pass diagnosis.json and an export directory")
source, output = abspath.(ARGS)
mkpath(output)
raw = JSON.parsefile(source)["records"]
keep = ("tool", "tool_version", "status", "correctness", "analysis_scope", "summary", "measurements", "findings", "runtime")
function public_value(value)
    if value isa AbstractDict
        return Dict(string(k) => public_value(v) for (k,v) in value if !(k in ("pid", "timestamp_ns", "source", "project", "path")))
    elseif value isa AbstractVector
        return public_value.(value)
    elseif value isa AbstractString
        # Native/source paths are useful locally, but unnecessary in public projections.
        return replace(value, r"[A-Za-z]:[\\/][^\s\n\"<>]+" => "<local-source>")
    end
    value
end
records = [public_value(Dict(k => r[k] for k in keep if haskey(r,k))) for r in raw]
open(io -> JSON.print(io, Dict("records" => records), 2), joinpath(output, "diagnosis.json"), "w")
findtool(name) = only(filter(r -> r["tool"] == name, records))

latency = findtool("latency")["measurements"]
fig = Figure(size = (900,450))
ax = Axis(fig[1,1]; title = "Loading, first operation and warm operation", ylabel = "milliseconds (log scale)",
    yscale = log10, xticks = (1:3, ["load", "first operation", "warm operation"]))
scatter!(ax, 1:3, [latency[k]*1000 for k in ("load_seconds", "first_case_seconds", "warm_case_seconds")]; markersize = 16)
save(joinpath(output, "latency.svg"), fig)

gc = findtool("gc")["measurements"]["samples"]
fig = Figure(size = (1000,420))
for (i,(key,title,unit,scale)) in enumerate((("allocated_bytes", "Allocation activity", "KiB", 1024), ("gc_seconds", "Garbage-collection time", "milliseconds", 0.001)))
    local ax = Axis(fig[1,i]; title, xlabel = "diagnostic operation", ylabel = unit)
    scatterlines!(ax, 1:length(gc), [s[key]/scale for s in gc])
end
save(joinpath(output, "gc.svg"), fig)

memory = findtool("memory")["measurements"]["samples"]
fig = Figure(size = (1000,450))
ax = Axis(fig[1,1]; title = "Reachable Julia objects", xlabel = "operation", ylabel = "KiB")
for (key,label) in (("state_before_bytes","state before"),("state_after_bytes","state after"),("state_and_result_bytes","state + result"))
    scatterlines!(ax, 1:length(memory), [s[key]/1024 for s in memory]; label)
end
axislegend(ax)
ax = Axis(fig[1,2]; title = "Resident process memory", xlabel = "operation", ylabel = "MiB")
for key in ("process_before", "process_after")
    scatterlines!(ax, 1:length(memory), [s[key]["rss_bytes"]/2^20 for s in memory]; label = replace(key,"_"=>" "))
end
axislegend(ax)
save(joinpath(output, "memory.svg"), fig)

locks = findtool("locks")["measurements"]["samples"]
fig = Figure(size = (900,400))
ax = Axis(fig[1,1]; title = "Observed lock conflicts", xlabel = "diagnostic operation", ylabel = "conflicts")
scatterlines!(ax, 1:length(locks), [s["lock_conflicts"] for s in locks])
save(joinpath(output, "locks.svg"), fig)
println("Published seven diagnostic reports and four figures")
