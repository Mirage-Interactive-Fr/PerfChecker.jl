using Pkg

mode = isempty(ARGS) ? "core" : only(ARGS)
mode in ("core", "oxygen", "web", "pluto", "plots", "extras", "analyzers") || error("Choose core, oxygen, web, pluto, plots, extras or analyzers")
root = normpath(joinpath(@__DIR__, "../.."))
if mode == "core"
    Pkg.activate(@__DIR__)
    Pkg.develop(path = root)
else
    Pkg.activate(joinpath(@__DIR__, ".controller", mode))
    specs = [Pkg.PackageSpec(path = root), Pkg.PackageSpec(path = @__DIR__)]
    names = mode == "web" ? ["PerfCheckerWeb", "PerfCheckerMakie"] :
            mode == "pluto" ? ["PerfCheckerPluto", "PerfCheckerMakie"] :
            mode == "plots" ? ["PerfCheckerMakie"] : String[]
    append!(specs, [Pkg.PackageSpec(path = joinpath(root, "packages", name)) for name in names])
    Pkg.develop(specs)
    Pkg.add(["BenchmarkTools", "Chairmarks", "DataStructures", "JSON", "UnicodePlots", "TestItemRunner"])
    mode in ("oxygen", "web", "pluto", "analyzers") && Pkg.add(["Oxygen", "HTTP"])
    mode == "web" && Pkg.add(["WGLMakie"])
    mode == "pluto" && Pkg.add(["Pluto", "PlutoUI", "WGLMakie"])
    mode == "plots" && Pkg.add(["CairoMakie", "WGLMakie"])
    mode == "extras" && Pkg.add(["DrWatson", "PropCheck", "Supposition", "PProf", "FlameGraphs", "Documenter", "DocumenterVitepress"])
    mode == "analyzers" && Pkg.add(["JET", "AllocCheck", "SnoopCompile", "Aqua"])
end
Pkg.instantiate()
# Pkg.develop writes an absolute source path; keep the distributable example portable.
if mode == "core"
    using TOML
    file = joinpath(@__DIR__, "Project.toml")
    project = TOML.parsefile(file)
    project["sources"]["PerfChecker"] = Dict("path" => "../..")
    open(io -> TOML.print(io, project; sorted = true), file, "w")
end
println("Prepared ", mode, ": ", Base.active_project())
