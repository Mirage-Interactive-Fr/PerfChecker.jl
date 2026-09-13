# A separate controller avoids reusing Windows manifests in WSL/Linux.
using Pkg
Sys.islinux() || error("Run this setup inside Linux or WSL")
ENV["JULIA_PKG_PRECOMPILE_AUTO"] = "0"
Pkg.activate(joinpath(@__DIR__, ".controller/linux"))
Pkg.develop(path = normpath(joinpath(@__DIR__, "../..")))
Pkg.add([PackageSpec(name = "Oxygen", version = "1.11.0"),
    PackageSpec(name = "HTTP"), PackageSpec(name = "JSON"), PackageSpec(name = "DataStructures"),
    PackageSpec(name = "BenchmarkTools"), PackageSpec(name = "Chairmarks")])
println("Linux controller ready. Run with --project=examples/kitchen-sink/.controller/linux")
