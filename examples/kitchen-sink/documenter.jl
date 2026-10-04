using PerfChecker, Documenter, DocumenterVitepress
include(joinpath(@__DIR__, "replay.jl"))
length(ARGS) == 1 || error("Pass a completed report directory")
bundle = example_bundle(abspath(only(ARGS)))
destination = joinpath(@__DIR__, "exports", "performance.md")
documenter_page(bundle, destination; title = "Recorded package performance")
println(destination)
# Include this generated Markdown in your own Documenter navigation.
# Building the website never needs to repeat the measurement campaign.
