using Pkg, TOML

# A separate process per release prevents one loaded package version from
# contaminating the next check. This is an oracle check, not a benchmark.
root = @__DIR__
package = isempty(ARGS) ? "DataStructures" : ARGS[1]
package in ("DataStructures", "Oxygen") || error("Choose DataStructures or Oxygen")
versions = length(ARGS) > 1 ? VersionNumber.(ARGS[2:end]) :
    package == "DataStructures" ? [v"0.9.0", v"0.10.0", v"0.11.0", v"0.11.1", v"0.12.0", v"0.13.0", v"0.14.1", v"0.15.0", v"0.16.1", v"0.17.0"] :
    [v"1.0.0", v"1.1.0", v"1.2.0", v"1.3.0", v"1.4.0", v"1.5.0", v"1.6.0"]
output = joinpath(root, "results", "compatibility")
mkpath(output)
records = Dict[]
for version in versions
    environments = joinpath(root, ".controller", "compatibility")
    mkpath(environments)
    environment = mktempdir(environments; prefix = package * "-" * string(version) * "-", cleanup = false)
    worker_project = joinpath(root, package == "Oxygen" ? "oxygen/workers/Project.toml" : "workers/Project.toml")
    cp(worker_project, joinpath(environment, "Project.toml"); force = true)
    logfile = joinpath(output, package * "-" * string(version) * ".log")
    code = if package == "Oxygen"
        "include($(repr(joinpath(root, "oxygen/service.jl")))); for kind in (\"heap\",\"counter\",\"buffer\"), n in (0,1,64,2048); c=EventService.request_case(kind,n); s=c.prepare(); @assert c.verify(s,c.operation(s)); end"
    else
        "include($(repr(joinpath(root, "src/PerfCheckerKitchenSink.jl")))); for kind in (\"heap\",\"vector\",\"counter\",\"buffer\"), n in (0,1,64,2048); c=PerfCheckerKitchenSink.event_case(Dict(\"kind\"=>kind,\"n\"=>n)); s=c.prepare(); @assert c.verify(s,c.operation(s)); end"
    end
    install = "using Pkg; Pkg.UPDATED_REGISTRY_THIS_SESSION[]=true; Pkg.add(PackageSpec(name=$(repr(package)), version=$(repr(version)))); "
    command = `$(Base.julia_cmd()) --startup-file=no --threads=1 --gcthreads=1 --project=$environment -e $(install * code)`
    passed = open(logfile, "w") do io
        success(pipeline(command; stdout=io, stderr=io))
    end
    push!(records, Dict("package"=>package, "version"=>string(version), "passed"=>passed, "julia"=>string(VERSION)))
    open(io -> TOML.print(io, Dict("checks"=>records)), joinpath(output, package * ".toml"), "w")
    println(package, " ", version, ": ", passed ? "passed" : "failed; see " * logfile)
    flush(stdout)
end
