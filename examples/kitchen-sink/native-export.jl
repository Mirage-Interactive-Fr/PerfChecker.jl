using JSON, CairoMakie
length(ARGS) == 2 || error("Pass a native result directory and an export directory")
source, output = abspath.(ARGS)
mkpath(output)
summary = JSON.parsefile(joinpath(source, "summary.json"))
for record in summary["records"]
    # Older captures stored exitcode but not the terminating signal. Retain the
    # raw exitcode and identify the timeout from its duration and termination log.
    log_path = joinpath(source, record["tool"] * ".log")
    if get(record,"executed",false) && record["correctness"] != "passed" && isfile(log_path)
        timed_out = get(record,"elapsed_seconds",0) >= 180 && occursin("signal 15: Terminated", read(log_path,String))
        if timed_out
            record["status"] = "time_budget_exceeded"
            record["status_evidence"] = "180-second budget followed by SIGTERM in the tool log; raw exitcode retained"
        elseif get(record,"status","") == "completed"
            record["status"] = "oracle_not_confirmed"
        end
    end
    # Earlier captures used the generic nonzero-exit label for Memcheck findings.
    if record["tool"] == "memcheck" && get(record,"exit_code",0) == 97 && record["correctness"] == "passed"
        record["status"] = "findings_reported"
    end
    if record["tool"] == "callgrind" && record["correctness"] == "passed"
        captures = filter(f -> occursin(r"^callgrind\.\d+$", f), record["artifacts"])
        for (index,file) in enumerate(captures)
            content = read(joinpath(source,file), String)
            total = match(r"(?m)^totals:\s+(\d+)",content)
            total === nothing && (total = match(r"(?m)^summary:\s+(\d+)",content))
            total === nothing && continue
            record["instrumented_instructions"] = parse(Int,total[1])
        end
    end
    if record["tool"] == "massif" && record["correctness"] == "passed"
        captures = filter(f -> occursin(r"^massif\.\d+$", f), record["artifacts"])
        isempty(captures) && continue
        # Each file is a separate process. Never concatenate parent and child timelines.
        for (index,file) in enumerate(captures)
            content = read(joinpath(source,file), String)
            matches = collect(eachmatch(r"snapshot=\d+\n#-+\ntime=(\d+)\nmem_heap_B=(\d+)\nmem_heap_extra_B=(\d+)\nmem_stacks_B=(\d+)", content))
            isempty(matches) && continue
            rows = [Dict("time" => parse(Int,m[1]), "heap_bytes" => parse(Int,m[2]),
                "allocator_overhead_bytes" => parse(Int,m[3]), "stack_bytes" => parse(Int,m[4])) for m in matches]
            time_unit = match(r"time_unit:\s*(\S+)", content)
            unit = time_unit === nothing ? "tool time units" : time_unit[1] == "i" ? "instrumented instructions" : time_unit[1]
            fig = Figure(size = (1000,480))
            axis = Axis(fig[1,1]; title = "Massif native heap — process $(index)", xlabel = unit, ylabel = "MiB")
            for (key,label) in (("heap_bytes","native heap"),("allocator_overhead_bytes","allocator overhead"),("stack_bytes","tracked stacks"))
                lines!(axis, [r["time"] for r in rows], [r[key]/2^20 for r in rows]; label)
            end
            axislegend(axis; position = :lt)
            save(joinpath(output,"massif-$(index).svg"),fig)
            open(io -> JSON.print(io, Dict("observations"=>rows,"time_unit"=>unit,"scope"=>record["scope"]),2),joinpath(output,"massif-$(index).json"),"w")
        end
    end
end
open(io -> JSON.print(io, summary, 2), joinpath(output,"summary.json"), "w")
println("Published native statuses and completed Massif timelines")
