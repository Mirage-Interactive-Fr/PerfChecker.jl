using PerfChecker
include(joinpath(@__DIR__, "replay.jl"))
length(ARGS) == 2 || error("Pass a completed profile report and an output directory")
bundle = example_bundle(abspath(ARGS[1]))
output = abspath(ARGS[2]); mkpath(output)
for metric in ("julia.cpu.samples", "julia.wall.samples", "julia.alloc.bytes")
    # Empty selections are reported explicitly rather than producing empty profiles.
    try
        write_folded_profile(bundle, joinpath(output, metric * ".folded"); metric)
        write_speedscope_profile(bundle, joinpath(output, metric * ".speedscope.json"); metric)
        if Base.find_package("PProf") !== nothing && Base.find_package("FlameGraphs") !== nothing
            @eval using PProf, FlameGraphs
            Base.invokelatest(write_pprof_profile, bundle, joinpath(output, metric * ".pb.gz"); metric)
        end
        println("Exported ", metric)
    catch exception
        exception isa ArgumentError || rethrow()
        println(metric, ": ", sprint(showerror, exception))
    end
end
