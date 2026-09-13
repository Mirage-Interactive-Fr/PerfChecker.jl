using Test, PerfChecker, PerfCheckerPluto
mktempdir() do directory
    notebook = write_investigation_notebook(joinpath(directory, "advisor.jl");
        root = directory, project = dirname(Base.active_project()))
    owner = Module(gensym(:AdvisorNotebookPreview))
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
    @testset "Advisor notebook opens without network or mutations" begin
        @test Base.invokelatest(() -> getfield(owner, :active_job)[]) === nothing
        @test Base.invokelatest(() -> getfield(owner, :setup_job)[]) === nothing
        @test Base.invokelatest(() -> getfield(owner, :setup_click)) == 0
        @test Base.invokelatest(() -> getfield(owner, :setup_snapshot))["status"] == "idle"
        @test Base.invokelatest(() -> getfield(owner, :setup_confirm)) === false
        @test readdir(directory) == ["advisor.jl"]
    end
end
