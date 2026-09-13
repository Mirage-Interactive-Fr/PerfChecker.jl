using Pkg
Sys.islinux() || error("Use Linux/WSL for loopback packet counters")
ENV["JULIA_PKG_PRECOMPILE_AUTO"] = "0"
# The recent server API supports asynchronous startup and clean termination.
# Older releases remain covered by the independent in-process routing history.
versions = vcat([VersionNumber(1,7,p) for p in 0:5],
    [v"1.8.0", v"1.9.0", v"1.10.0", v"1.10.1", v"1.10.2", v"1.11.0"])
length(ARGS) >= 1 && (versions = filter(v -> v >= VersionNumber(ARGS[1]), versions))
output = mktempdir(joinpath(@__DIR__, "../results"); prefix = "oxygen-network-history-", cleanup = false)
failures = String[]
for version in versions
    environment = mktempdir()
    try
        Pkg.activate(environment)
        Pkg.develop(path = normpath(joinpath(@__DIR__, "../../..")))
        Pkg.add([PackageSpec(name = "Oxygen", version = version), PackageSpec(name = "HTTP"),
            PackageSpec(name = "JSON"), PackageSpec(name = "DataStructures")])
        command = `$(Base.julia_cmd()) --startup-file=no --threads=1 --gcthreads=1 --project=$environment $(joinpath(@__DIR__, "network.jl")) $(joinpath(output, string(version) * ".json"))`
        run(command)
    catch error
        push!(failures, string(version))
        write(joinpath(output, string(version) * ".error.txt"), sprint(showerror, error))
    end
end
println("Network history: ", output)
isempty(failures) || error("Unavailable network runs: " * join(failures, ", "))
