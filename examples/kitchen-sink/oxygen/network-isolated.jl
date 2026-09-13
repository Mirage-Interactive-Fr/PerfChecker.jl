using PerfChecker, JSON
Sys.islinux() || error("Run this example inside Linux/WSL")
output = mktempdir(joinpath(@__DIR__, "../results"); prefix = "oxygen-isolated-", cleanup = false)
spec = NetworkIsolationSpec(provider = :linux_netns, interface = "lo")
capabilities = network_isolation_capabilities(spec; probe = true)
record = Dict{String,Any}("capabilities" => capabilities, "executed" => false)
if capabilities["supported"]
    observations = joinpath(output, "requests.json")
    command = [Base.julia_cmd().exec..., "--startup-file=no", "--threads=1", "--gcthreads=1",
        "--project=$(dirname(Base.active_project()))", joinpath(@__DIR__, "network.jl"), observations]
    result = measure_isolated_network_command(command; spec, timeout_seconds = 180,
        environment = Dict("JULIA_NUM_THREADS" => "1", "JULIA_NUM_GC_THREADS" => "1", "OPENBLAS_NUM_THREADS" => "1"))
    record["executed"] = true
    record["exit_code"] = result.exit_code
    record["capture"] = isolated_network_result_dict(result)
    delete!(record["capture"], "command")
    if result.exit_code == 0 && isfile(observations)
        requests = JSON.parsefile(observations)
        record["correctness"] = all(r["correctness"] == "passed" for r in requests["records"]) ? "passed" : "failed"
        record["verified_requests"] = sum(length(r["samples"]) for r in requests["records"])
        record["oxygen_version"] = requests["version"]
        record["http_version"] = requests["http_version"]
    else
        record["correctness"] = "not_confirmed"
    end
end
open(io -> JSON.print(io, record, 2), joinpath(output, "isolation.json"), "w")
println("Isolated network evidence: ", output)
get(record, "executed", false) && get(record,"correctness","") != "passed" && error("Inspect the isolated workload failure")
