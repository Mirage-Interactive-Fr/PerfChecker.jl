using PerfChecker, JSON
output = joinpath(@__DIR__, "exports", "native")
mkpath(output)
for tool in (:memcheck, :callgrind, :massif, :cachegrind, :heaptrack, :perf, :vtune)
    plan = native_tool_plan(tool, joinpath(@__DIR__, "native-workload.jl");
        project = dirname(Base.active_project()), output = joinpath(output, string(tool)))
    open(io -> JSON.print(io, plan, 2), joinpath(output, string(tool) * ".json"), "w")
    println(tool, ": ", plan["availability"], " — command prepared, not executed")
end
open(io -> JSON.print(io, machine_profile(), 2), joinpath(output, "machine.json"), "w")
