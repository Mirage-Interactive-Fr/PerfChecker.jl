using TestItemRunner, PerfCheckerMakie, CairoMakie
CairoMakie.activate!()
rendering = Base.find_package("WGLMakie") !== nothing
if rendering
    using WGLMakie
end
TestItemRunner.run_tests(dirname(@__DIR__); filter = ti -> rendering || :wgl ∉ ti.tags)
