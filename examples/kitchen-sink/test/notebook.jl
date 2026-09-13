using Pluto, Test
function validate_notebook()
root = normpath(joinpath(@__DIR__, ".."))
ENV["PERFCHECKER_EXAMPLE_ROOT"] = root
session = Pluto.ServerSession(options = Pluto.Configuration.from_flat_kwargs(
    threads = 1, launch_browser = false, disable_writing_notebook_files = true))
notebook = nothing
try
    notebook = Pluto.SessionActions.open(session, joinpath(root, "notebook.jl"); run_async = false)
    @testset "Recorded package notebook" begin
        for cell in notebook.cells
            cell.errored && println(cell.output.body)
            @test !cell.errored
        end
    end
finally
    notebook === nothing || Pluto.SessionActions.shutdown(session, notebook)
end
end
validate_notebook()
