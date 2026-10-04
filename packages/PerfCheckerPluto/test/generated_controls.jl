using Test, PerfChecker, PerfCheckerPluto
let
    root = joinpath(pkgdir(PerfChecker), "examples", "shared-scenarios")
    project = dirname(Base.active_project())
    reports = mktempdir()
    @testset "Generated Pluto controls are idle when opened" begin
        notebook = write_investigation_notebook(
            joinpath(reports, "investigation.jl"); root, project,
            catalog = joinpath(root, "scenarios.toml"), force = true)
        owner = Module(gensym(:NotebookPreview))
        Core.eval(owner, Meta.parse(raw"""
        macro bind(definition, element)
            quote
                local widget = $(esc(element))
                global $(esc(definition)) = Base.get(widget)
                widget
            end
        end
        """))
        Base.include(owner, notebook)
        @test Base.invokelatest(() -> getfield(owner, :active_job)[]) === nothing
        @test Base.invokelatest(() -> getfield(owner, :launch_click)) == 0
        @test Base.invokelatest(() -> getfield(owner, :snapshot))["status"] == "idle"
    end
    @testset "Generated suite notebook does not launch or save on opening" begin
        notebook = write_suite_notebook(joinpath(reports, "suite.jl"); project)
        owner = Module(gensym(:SuitePreview))
        Core.eval(owner, Meta.parse(raw"""
        macro bind(definition, element)
            quote
                local widget = $(esc(element))
                global $(esc(definition)) = Base.get(widget)
                widget
            end
        end
        """))
        Base.include(owner, notebook)
        @test Base.invokelatest(() -> getfield(owner, :job)) === nothing
        @test Base.invokelatest(() -> getfield(owner, :launch_click)) == ""
        @test Base.invokelatest(() -> getfield(owner, :save_click)) == ""
        @test Base.invokelatest(() -> getfield(owner, :snapshot))["state"] == "idle"
        @test !isdir(joinpath(reports, "results", "notebook"))
    end
end
