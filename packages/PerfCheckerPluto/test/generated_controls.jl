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
        @testset "Standalone plot documents stay inside a fresh sandboxed frame" begin
            content = "<!doctype html><script>const text = \"&<>'\";</script>"
            title = "Plot \"quoted\" & <tag> 'single'"
            frame_type = getfield(owner, :SuitePlotFrame)
            first_frame = Base.invokelatest(frame_type, content, title)
            next_frame = Base.invokelatest(frame_type, content, title)
            rendered = Base.invokelatest(sprint, show, MIME"text/html"(), first_frame)
            @test first_frame.token != next_frame.token
            @test occursin("data-perfchecker-plot-frame='$(first_frame.token)'", rendered)
            @test occursin("id='$(first_frame.token)'", rendered)
            @test occursin("sandbox='allow-scripts'", rendered)
            @test !occursin("allow-same-origin", rendered)
            @test occursin(
                "title='Plot &quot;quoted&quot; &amp; &lt;tag&gt; &#39;single&#39;'",
                rendered)
            @test occursin(
                "srcdoc='&lt;!doctype html&gt;&lt;script&gt;const text = &quot;&amp;&lt;&gt;&#39;&quot;;&lt;/script&gt;'",
                rendered)
            @test !occursin("<script>", rendered)
        end
    end
end
