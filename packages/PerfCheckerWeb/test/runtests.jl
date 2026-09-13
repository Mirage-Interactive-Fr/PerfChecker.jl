using TestItemRunner, PerfCheckerWeb
rendering = Base.find_package("PerfCheckerMakie") !== nothing &&
            Base.find_package("WGLMakie") !== nothing
if rendering
    using PerfCheckerMakie, WGLMakie
end
TestItemRunner.run_tests(
    dirname(@__DIR__); filter = ti -> rendering || :oxygen_latest ∉ ti.tags)
