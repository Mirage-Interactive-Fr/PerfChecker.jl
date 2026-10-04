using PerfChecker, PerfCheckerPluto

notebook = isempty(ARGS) ? joinpath(@__DIR__, "notebook.jl") : abspath(only(ARGS))
launch_pluto_dashboard(notebook; host = "127.0.0.1", port = 8872,
    launch_browser = get(ENV, "PERFCHECKER_OPEN_BROWSER", "true") == "true")
