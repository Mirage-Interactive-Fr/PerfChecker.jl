@testitem "Fresh qualification releases its closed owner before measurement" tags = [:unit, :lifecycle, :qualification_owner] begin
    using PerfChecker
    # Main callback entrypoints require their own process. This is the existing
    # intrinsic legacy-collector regression suite, not a generated helper file.
    project = dirname(Base.active_project())
    script = joinpath(pkgdir(PerfChecker), "test", "shared_legacy.jl")
    command = `$(Base.julia_cmd()) --startup-file=no --threads=2 --project=$project $script`
    @test success(run(command))
end
