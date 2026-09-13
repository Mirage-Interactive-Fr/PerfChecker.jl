using PerfChecker, JSON, Dates, SHA, Pkg
Sys.islinux() || error("Use Linux/WSL for this native-tool walkthrough")
example = isempty(ARGS) ? "datastructures" : ARGS[1]
example in ("datastructures", "oxygen") || error("Choose datastructures or oxygen")
selected = length(ARGS) < 2 ? (:memcheck, :callgrind, :massif, :cachegrind, :heaptrack, :perf, :vtune) : (Symbol(ARGS[2]),)
output = mktempdir(joinpath(@__DIR__, "results"); prefix = "native-$(example)-", cleanup = false)
records = Any[]
versions = Dict(info.name => string(info.version) for info in values(Pkg.dependencies())
    if info.name in ("DataStructures", "Oxygen", "HTTP") && info.version !== nothing)
script = joinpath(@__DIR__, example == "oxygen" ? "oxygen/native-workload.jl" : "native-workload.jl")
suppression_file = joinpath(@__DIR__, ".controller/native/valgrind-julia-$(VERSION).supp")
suppressions = isfile(suppression_file) ? suppression_file : nothing
# Populate matching generic-target package caches before instrumenting. Otherwise
# a Memcheck finding in a precompile child can prevent the workload from loading.
warm = `$(Base.julia_cmd()) --startup-file=no --cpu-target=generic --project=$(dirname(Base.active_project())) $script`
run(addenv(warm, "PERFCHECKER_NATIVE_SIZE" => "512", "PERFCHECKER_NATIVE_REPETITIONS" => "1"))
for tool in selected
    plan = native_tool_plan(tool, script; output = joinpath(output, string(tool)), suppressions)
    record = Dict("tool" => string(tool), "availability" => plan["availability"],
        "scope" => plan["scope"], "executed" => false, "correctness" => "not_checked",
        "package" => example, "size" => 512, "repetitions" => 3, "resolved_packages" => versions)
    record["suppression_sha256"] = suppressions === nothing ? nothing : bytes2hex(sha256(read(suppressions)))
    record["cpu_target"] = "generic"
    if plan["availability"] == "executable_found"
        # A generic JIT target avoids generating instructions unsupported by an older Valgrind.
        args = String.(plan["arguments"])
        client = joinpath(@__DIR__, ".controller/native/callgrind-window.so")
        windowed = tool == :callgrind && isfile(client)
        if windowed
            pushfirst!(args, "--instr-atstart=no")
            record["scope"] = "three warmed lifecycles including preparation and oracle; startup excluded"
        end
        position = findfirst(==("--startup-file=no"), args)
        position === nothing || insert!(args, position + 1, "--cpu-target=generic")
        position === nothing || insert!(args, position + 1, "--compiled-modules=existing")
        command = Cmd(["timeout", "--kill-after=10", "180", String(plan["executable"]), args...])
        log = joinpath(output, string(tool) * ".log")
        elapsed = @elapsed process = open(log, "w") do io
            run(pipeline(ignorestatus(addenv(command,
                "PERFCHECKER_NATIVE_SIZE" => "512", "PERFCHECKER_NATIVE_REPETITIONS" => "3",
                "JULIA_NUM_THREADS" => "1", "JULIA_NUM_GC_THREADS" => "1", "OPENBLAS_NUM_THREADS" => "1",
                "PERFCHECKER_CALLGRIND_CLIENT" => windowed ? client : "",
                "LD_LIBRARY_PATH" => joinpath(Sys.BINDIR, "../lib/julia") * ":" * get(ENV, "LD_LIBRARY_PATH", ""))), stdout = io, stderr = io))
        end
        record["executed"] = true
        child = process isa Base.ProcessChain ? last(process.processes) : process
        record["exit_code"] = child.exitcode
        record["termination_signal"] = child.termsignal
        record["elapsed_seconds"] = elapsed
        record["correctness"] = occursin("WORKLOAD_ORACLE_PASSED", read(log, String)) ? "passed" : "not_confirmed"
        timed_out = child.exitcode in (124, 137) || (child.termsignal == 9 && elapsed >= 180)
        record["status"] = timed_out ? "time_budget_exceeded" : child.termsignal != 0 ? "tool_failed" :
            child.exitcode == 0 ? (record["correctness"] == "passed" ? "completed" : "oracle_not_confirmed") :
            tool == :memcheck && child.exitcode == 97 && record["correctness"] == "passed" ? "findings_reported" : "tool_failed"
        record["artifacts"] = filter(name -> startswith(name, string(tool)), readdir(output))
    end
    push!(records, record)
    open(io -> JSON.print(io, Dict("records" => records, "julia_version" => string(VERSION),
        "os" => string(Sys.KERNEL), "date" => string(now(UTC))), 2), joinpath(output, "summary.json"), "w")
    println(tool, ": ", get(record, "status", record["availability"]), "; oracle ", record["correctness"])
    flush(stdout)
end
println("Native evidence: ", output)
