using Pkg, TOML

mode = isempty(ARGS) ? "core" : only(ARGS)
mode in ("core", "web", "pluto", "items") || error("Choose core, web, pluto or items")
root = normpath(joinpath(@__DIR__, "../.."))
sources = TOML.parsefile(joinpath(@__DIR__, "sources.toml"))
mkpath(joinpath(@__DIR__, ".sources"))
for name in sort!(collect(keys(sources)))
    spec = sources[name]
    destination = joinpath(@__DIR__, ".sources", name)
    if !isdir(destination)
        # An optional local mirror saves bandwidth; still verify the public revision.
        origin = get(ENV, uppercase(name) * "_CLONE_FROM", spec["url"])
        run(`git clone --no-hardlinks --no-checkout $origin $destination`)
        run(`git -C $destination checkout --detach $(spec["revision"])`)
    end
    revision = strip(read(`git -C $destination rev-parse HEAD`, String))
    revision == spec["revision"] || error("$name checkout differs from sources.toml")
    isempty(strip(read(`git -C $destination status --porcelain`, String))) ||
        error("$name checkout has local changes; preserve them before preparing the tutorial")
end

# Timing controllers keep measured packages in separate workers. The native-item
# mode prepares a complete test environment for the fresh TestItemRunner process.
Pkg.activate(joinpath(@__DIR__, ".controller", mode))
packages = [Pkg.PackageSpec(path = root)]
if mode == "web"
    append!(packages,
        [Pkg.PackageSpec(path = joinpath(root, "packages", name))
         for name in ("PerfCheckerWeb", "PerfCheckerMakie")])
elseif mode == "pluto"
    push!(packages, Pkg.PackageSpec(path = joinpath(root, "packages/PerfCheckerPluto")))
    push!(packages, Pkg.PackageSpec(path = joinpath(root, "packages/PerfCheckerMakie")))
elseif mode == "items"
    # Functional TestItems import their packages in a fresh process using this
    # prepared test environment. Timing-suite workers keep their separate setup.
    append!(packages,
        [Pkg.PackageSpec(path = joinpath(@__DIR__, ".sources", name))
         for name in ("BibInternal", "BibParser", "Bibliography")])
end
Pkg.develop(packages)
Pkg.add(["BenchmarkTools", "Chairmarks", "TestItemRunner", "UnicodePlots", "JSON"])
mode in ("web", "pluto") && Pkg.add("WGLMakie")
mode == "pluto" && Pkg.add("PlutoUI")
Pkg.instantiate()
next_script = mode == "items" ? "items.jl list" :
              mode == "web" ? "web.jl" : mode == "pluto" ? "pluto.jl" : "run.jl plan"
println("Ready. From ", @__DIR__, ":")
println("julia --startup-file=no --project=.controller/$mode $next_script")
