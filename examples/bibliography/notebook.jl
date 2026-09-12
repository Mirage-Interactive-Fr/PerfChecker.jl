### A Pluto.jl notebook ###
# v1.0.3

using Markdown
using InteractiveUtils

# This Pluto notebook uses @bind for interactivity. When running this notebook outside of Pluto, the following 'mock version' of @bind gives bound variables a default value (instead of an error).
macro bind(def, element)
    #! format: off
    return quote
        local iv = try Base.loaded_modules[Base.PkgId(Base.UUID("6e696c72-6542-2067-7265-42206c756150"), "AbstractPlutoDingetjes")].Bonds.initial_value catch; b -> missing; end
        local el = $(esc(element))
        global $(esc(def)) = Core.applicable(Base.get, el) ? Base.get(el) : iv(el)
        el
    end
    #! format: on
end

# ╔═╡ 58f7db29-c250-46b6-8ae6-3443f786600e
begin
    begin
        import Pkg
        bibliography_root = @__DIR__
        controller_project = joinpath(bibliography_root, ".controller", "pluto")
        isfile(joinpath(controller_project, "Project.toml")) ||
            error("Save notebook.jl in examples/bibliography, then run julia --startup-file=no setup.jl pluto from that directory before opening it.")
        Pkg.activate(controller_project; io = devnull)
        using PerfChecker, PlutoUI, Markdown
    end
end;

# ╔═╡ dbf746e4-9e2f-4237-b414-b15e8094c34f
md"""# Bibliography performance notebook
Save this file as `examples/bibliography/notebook.jl` in a PerfChecker checkout.
Run `julia --startup-file=no setup.jl pluto` from that folder once, then open
the notebook with `julia --startup-file=no --project=.controller/pluto pluto.jl`.

Choose the pinned development suite or nine tagged versions below. Preparation,
input size and source revisions are described in the [Bibliography tutorial](https://mirage-interactive-fr.github.io/PerfChecker.jl/dev/tutorials/bibliography).

Filter the plan, then press **Launch selected checks**. Changing controls never starts workers. Use **Refresh status** while a job runs, then **Save completed reports**."""

# ╔═╡ 3bcf7209-df02-42ee-9fe4-75176ce71481
begin
    begin
        struct SuiteActionButton
            label::String
        end
        Base.get(::SuiteActionButton) = ""
        function Base.show(io::IO, ::MIME"text/html", button::SuiteActionButton)
            label = replace(button.label, '&' => "&amp;", '<' => "&lt;", '>' => "&gt;")
            print(io, "<span><button type='button'>", label, "</button><script>")
            print(io, "const span = currentScript.parentElement; span.value = ''; ")
            print(io, "span.firstElementChild.addEventListener('click', event => { ")
            print(io,
                "span.value = crypto.randomUUID(); span.dispatchEvent(new CustomEvent('input')); event.stopPropagation(); });")
            print(io, "</script></span>")
        end
    end

    begin
        last_launch = Ref("")
        last_cancel = Ref("")
        last_save = Ref("")
        active_job = Ref{Any}(nothing)
        last_saved = Ref("")
    end
end;

# ╔═╡ 0c556d63-34d6-4e79-b1e4-5ec59a121a30
md"""$(@bind historical CheckBox(default=false)) **Compare nine tagged versions (0.1.0–0.4.0)**

Unchecked: seven workloads at pinned development revisions. Checked: the
historical Bibliography suite, with unavailable workloads shown explicitly.
Changing this control prepares a plan; it does not start a measurement."""

# ╔═╡ 7cc75f61-557c-4db2-87f4-7e4c4ce41c08
begin
    suite_path = joinpath(bibliography_root, historical ? "history-suite.jl" : "suite.jl")
    result_path = joinpath(bibliography_root, "results", "suite-result.json")
    reports_root = joinpath(bibliography_root, "results")
    full_plan = suite_path === nothing ? nothing :
                plan_suite(load_software_suite(suite_path; factory = :build_suite);
        profile = historical ? :historical : :quick)
    begin
        available_runs = full_plan === nothing ? [] : full_plan.runs
        package_names = sort!(unique([run.package_suite.package for run in available_runs]))
        workload_names = sort!(unique([string(PerfChecker.workload_id(run))
                                       for run in available_runs]))
        collector_names = sort!(unique([string(run.feature.backend)
                                        for run in available_runs]))
        target_names = sort!(unique([run.target.label for run in available_runs]))
    end
end;

# ╔═╡ 80a3933b-9095-4a3d-9586-9c6b1d2043ca
md"""**Package**

$(@bind selected_package Select(vcat(["" => "All packages"], [name => name for name in package_names])))"""

# ╔═╡ 8c48fad5-7756-48bf-9e64-9dfbb4c1cfb1
md"""**Workload**

$(@bind selected_workload Select(vcat(["" => "All workloads"], [name => name for name in workload_names])))"""

# ╔═╡ 3649c41d-9fa0-415f-9840-84d9d4c4e90d
md"""**Collector**

$(@bind selected_collector Select(vcat(["" => "All collectors"], [name => name for name in collector_names]); default = "benchmark" in collector_names ? "benchmark" : ""))"""

# ╔═╡ 13e36069-cf32-4e1b-9c85-db51d731a69a
md"""**Target**

$(@bind selected_target Select(vcat(["" => "All targets"], [name => name for name in target_names])))"""

# ╔═╡ 3af54c91-6ee7-4006-a604-8e9eaa02ca31
begin
    filtered_plan = full_plan === nothing ? nothing :
                    filter_suite_plan(
        full_plan; packages = isempty(selected_package) ? nothing : selected_package,
        features = isempty(selected_workload) ? nothing : selected_workload,
        backends = isempty(selected_collector) ? nothing : selected_collector)
    selected_plan = filtered_plan === nothing ? nothing :
                    SuitePlan(filtered_plan.suite,
        filtered_plan.profile,
        [run
         for run in filtered_plan.runs
         if isempty(selected_target) || run.target.label == selected_target],
        filtered_plan.comparisons)
end;

# ╔═╡ 89ab1710-634d-40c5-bfe7-96bd71ad59d0
selected_plan === nothing ? md"No executable suite: this notebook reads saved reports." :
Markdown.parse("```text\n" * sprint(print_suite_plan, selected_plan) * "\n```")

# ╔═╡ 8a32c939-2077-4e72-b895-3d0dac67ff37
md"""**Samples**

$(@bind samples NumberField(1:10000; default = 50))"""

# ╔═╡ 26e5aae1-94d0-4f8b-891e-00f6d698e166
md"""**Seconds per benchmark**

$(@bind seconds NumberField(0.1:0.1:60; default = 0.5))"""

# ╔═╡ b4456c82-7a4a-408a-bf72-02c31c33569c
md"""**Worker threads**

$(@bind worker_threads NumberField(1:4; default = 1))"""

# ╔═╡ 2f9abb2a-11de-40cf-ad18-81442c06f212
@bind launch_click SuiteActionButton("Launch selected checks")

# ╔═╡ 25383115-6ca5-468e-b760-e84ef761ccc9
begin
    job = begin
        if launch_click isa AbstractString && !isempty(launch_click) &&
           launch_click != last_launch[]
            last_launch[] = launch_click
            if active_job[] !== nothing &&
               suite_job_status(active_job[]) ∉ (:complete, :failed, :cancelled)
                error("A job is already running. Refresh or cancel it before launching another.")
            end
            selected_plan === nothing && error("This notebook has no executable suite.")
            isempty(selected_plan.runs) && error("The selection contains no checks.")
            active_job[] = launch_suite(selected_plan;
                overrides = Dict{Symbol, Any}(
                    :samples => samples, :seconds => seconds, :threads => worker_threads, :evals => 1))
        end
        active_job[]
    end
end;

# ╔═╡ 4821f33d-1a8e-4264-8e15-805b50cfd9cb
@bind cancel_click SuiteActionButton("Cancel active job")

# ╔═╡ 25e2f0b2-741d-4f10-bf79-e93d95afb8c8
if cancel_click isa AbstractString && !isempty(cancel_click) &&
   cancel_click != last_cancel[]
    last_cancel[] = cancel_click
    job === nothing || cancel!(job)
end

# ╔═╡ 766f8bec-6d29-4fd0-ae8f-e1c838d4c58c
@bind refresh_click CounterButton("Refresh status")

# ╔═╡ caeca5ab-67f0-43d7-ba97-fbaf67b44c51
begin
    snapshot = (refresh_click;
    job === nothing ? Dict("state" => "idle") :
    suite_job_progress(job))
end;

# ╔═╡ e7e3fd4c-adc3-4e83-9ce3-ad0706a4507b
HTML("<p role='status' data-suite-state='" * get(snapshot, "state", "idle") *
     "'><strong>Status:</strong> " * get(snapshot, "state", "idle") * " · " *
     string(get(snapshot, "completed", 0)) * " / " * string(get(snapshot, "total", 0)) *
     " checks completed</p>")

# ╔═╡ f3478491-ccc4-42b5-aeb5-cd60859d41d8
begin
    job_result = (snapshot;
    job === nothing ||
        suite_job_status(job) ∉ (:complete, :failed) ? nothing :
    wait_suite(job; strict = false))
end;

# ╔═╡ d998796d-0321-4ef9-9aef-48e11d20cc32
@bind save_click SuiteActionButton("Save completed reports")

# ╔═╡ b95702d2-3c85-48ae-a18d-d9031c00bfad
saved_reports = begin
    if save_click isa AbstractString && !isempty(save_click) && save_click != last_save[]
        last_save[] = save_click
        job_result === nothing && error("Refresh a completed job before saving.")
        mkpath(reports_root)
        destination = mktempdir(reports_root; prefix = "pluto-", cleanup = false)
        write_suite_reports(job_result, destination)
        last_saved[] = joinpath(basename(reports_root), basename(destination))
    end
    isempty(last_saved[]) ? "No saved reports yet." : "Last saved reports: " * last_saved[]
end

# ╔═╡ 1fc1329a-f91f-43ff-9ab8-696ee91f2c6c
begin
    report = job_result !== nothing ? suite_dict(job_result) :
             isfile(result_path) ? PerfChecker._json_parsefile(result_path) :
             Dict("status" => "missing",
        "message" => "Launch selected checks or choose an existing suite-result.json.")
    runs = get(report, "runs", Any[])
end;

# ╔═╡ dc0313f2-07e9-4f3e-ab19-47fd1a800e20
md"""## Results
A completed collector is not a correctness proof or a performance comparison. Save the reports to inspect correctness and comparison fields in the complete bundle."""

# ╔═╡ 1b1be096-01ca-417b-b9ec-a9a480f43bb2
isempty(runs) ? md"No completed checks yet." :
Markdown.parse("| Package | Workload | Target | Status |\n| --- | --- | --- | --- |\n" *
               join(
    ["| " *
     join(
         [replace(string(get(run, key, "")), "|" => "/", '\n' => ' ')
          for key in ("package", "workload", "version", "status")],
         " | ") * " |" for run in runs],
    "\n"))

# ╔═╡ 924b1935-c312-4c31-82b4-8bfd17782001
md"""## Performance curves
The combined view overlays all four collector measurements, normalized by each
metric's minimum across versions. Individual absolute plots remain selectable.
Run `setup.jl pluto` again if this environment predates the plotting packages.
"""

# ╔═╡ 924b1935-c312-4c31-82b4-8bfd17782002
begin
    plot_bundle = job_result !== nothing ? PerfChecker._suite_run_bundle(job_result) :
    begin
        saved_bundle = joinpath(
            dirname(result_path), "bundles", "run-" * string(get(report, "run_id", "")))
        isdir(saved_bundle) ? read_run_bundle(saved_bundle) : nothing
    end
    plot_entries = plot_bundle === nothing ? [] : plot_catalog(plot_bundle)
end;

# ╔═╡ 924b1935-c312-4c31-82b4-8bfd17782003
@bind selected_plot Select(isempty(plot_entries) ? ["" => "No completed measurements"] :
                           [entry["id"] => entry["title"] * " · " * entry["label"]
                            for entry in plot_entries])

# ╔═╡ 924b1935-c312-4c31-82b4-8bfd17782004
if plot_bundle !== nothing && !isempty(selected_plot)
    if Base.find_package("PerfCheckerMakie") === nothing ||
       Base.find_package("WGLMakie") === nothing
        md"Run setup.jl pluto to prepare this notebook's plotting environment."
    else
        @eval using PerfCheckerMakie, WGLMakie
        HTML(performance_plot_html(performance_plot(plot_bundle, selected_plot)))
    end
end

# ╔═╡ Cell order:
# ╟─58f7db29-c250-46b6-8ae6-3443f786600e
# ╟─dbf746e4-9e2f-4237-b414-b15e8094c34f
# ╟─0c556d63-34d6-4e79-b1e4-5ec59a121a30
# ╟─7cc75f61-557c-4db2-87f4-7e4c4ce41c08
# ╟─80a3933b-9095-4a3d-9586-9c6b1d2043ca
# ╟─8c48fad5-7756-48bf-9e64-9dfbb4c1cfb1
# ╟─3649c41d-9fa0-415f-9840-84d9d4c4e90d
# ╟─13e36069-cf32-4e1b-9c85-db51d731a69a
# ╟─3af54c91-6ee7-4006-a604-8e9eaa02ca31
# ╟─89ab1710-634d-40c5-bfe7-96bd71ad59d0
# ╟─8a32c939-2077-4e72-b895-3d0dac67ff37
# ╟─26e5aae1-94d0-4f8b-891e-00f6d698e166
# ╟─b4456c82-7a4a-408a-bf72-02c31c33569c
# ╟─3bcf7209-df02-42ee-9fe4-75176ce71481
# ╟─2f9abb2a-11de-40cf-ad18-81442c06f212
# ╟─25383115-6ca5-468e-b760-e84ef761ccc9
# ╟─4821f33d-1a8e-4264-8e15-805b50cfd9cb
# ╟─25e2f0b2-741d-4f10-bf79-e93d95afb8c8
# ╟─766f8bec-6d29-4fd0-ae8f-e1c838d4c58c
# ╟─caeca5ab-67f0-43d7-ba97-fbaf67b44c51
# ╟─e7e3fd4c-adc3-4e83-9ce3-ad0706a4507b
# ╟─f3478491-ccc4-42b5-aeb5-cd60859d41d8
# ╟─d998796d-0321-4ef9-9aef-48e11d20cc32
# ╟─b95702d2-3c85-48ae-a18d-d9031c00bfad
# ╟─1fc1329a-f91f-43ff-9ab8-696ee91f2c6c
# ╟─dc0313f2-07e9-4f3e-ab19-47fd1a800e20
# ╟─1b1be096-01ca-417b-b9ec-a9a480f43bb2
# ╟─924b1935-c312-4c31-82b4-8bfd17782001
# ╟─924b1935-c312-4c31-82b4-8bfd17782002
# ╟─924b1935-c312-4c31-82b4-8bfd17782003
# ╟─924b1935-c312-4c31-82b4-8bfd17782004
