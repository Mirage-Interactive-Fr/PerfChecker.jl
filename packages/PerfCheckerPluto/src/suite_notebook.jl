"""
    write_suite_notebook(path; result_path="results/suite-result.json",
                         suite_path=nothing, factory=:build_suite,
                         profile=:quick, project=active_project_directory,
                         reports_root="results/notebook", force=false)

Create a Pluto controller with package, workload, collector and target filters.
Changing a selector never starts a measurement: Launch, Cancel, Refresh and Save
are explicit buttons. A notebook without `suite_path` only reads saved reports.
`project` identifies the prepared controller environment; it need not be the
notebook directory. Relative report paths are resolved beside the notebook;
relative suite paths are resolved from the caller's working directory.

Return the absolute notebook path. Refuse to overwrite an existing file unless
`force=true`; validate generated cell syntax, create parent directories and write
the notebook. Generation does not install dependencies, start Pluto or execute
the suite. On opening, cells activate `project` and, when supplied, load the suite
factory and build its plan. The controller project must already contain
`PerfChecker` and `PlutoUI`; plotting also needs `PerfCheckerMakie` and WGLMakie.
"""
function PerfChecker.write_suite_notebook(path::AbstractString;
        result_path::AbstractString = "results/suite-result.json", suite_path = nothing,
        factory::Symbol = :build_suite, profile::Symbol = :quick,
        project::AbstractString = dirname(something(
            Base.active_project(), joinpath(pwd(), "Project.toml"))),
        reports_root::AbstractString = "results/notebook", force::Bool = false)
    target = abspath(path)
    isfile(target) && !force &&
        throw(ArgumentError("$target already exists; pass force=true to overwrite it"))
    suite_literal = suite_path === nothing ? "nothing" : repr(abspath(suite_path))
    control(label, binding) = "md\"\"\"**$label**\n\n\$($binding)\"\"\""
    # CounterButton restarts at zero on browser reload. A fresh token per click
    # preserves explicit actions without requiring several clicks after reconnect.
    action_button = raw"""
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
        print(io, "span.value = crypto.randomUUID(); span.dispatchEvent(new CustomEvent('input')); event.stopPropagation(); });")
        print(io, "</script></span>")
    end
end
"""
    # Each static export creates its own Bonito root session. Keep its WGLMakie
    # module state in a separate document when Pluto replaces the selected plot.
    plot_frame = raw"""
begin
    @doc "    SuitePlotFrame(html, title)

Display a standalone plot export in a separate HTML document. `html` is the
complete document returned by `performance_plot_html`; `title` names the plot
for assistive technology. Rendering escapes both values once as HTML attributes
and emits an iframe with scripts allowed and same-origin access omitted.

Each instance has a fresh DOM identifier so replacing a Pluto result also
replaces the document and its JavaScript module state, including when an HTML
export is reused from a cache. The frame follows the notebook width, reserves
between 360 and 760 CSS pixels of height, and lets the export fit its own canvas.
Constructing or displaying the frame does not launch a measurement or a worker.
" struct SuitePlotFrame
        html::String
        title::String
        token::String
    end
    SuitePlotFrame(html::AbstractString, title::AbstractString) =
        SuitePlotFrame(String(html), String(title), string(gensym(:perfchecker_plot)))
    function Base.show(io::IO, ::MIME"text/html", frame::SuitePlotFrame)
        attribute(value) = replace(value, '&' => "&amp;", '<' => "&lt;",
            '>' => "&gt;", '"' => "&quot;", '\'' => "&#39;")
        print(io, "<iframe data-perfchecker-plot-frame='", attribute(frame.token),
            "' id='", attribute(frame.token), "' title='", attribute(frame.title),
            "' sandbox='allow-scripts' style='display:block;width:100%;",
            "height:min(760px,85vh);min-height:360px;border:0' srcdoc='",
            attribute(frame.html), "'></iframe>")
    end
end
"""
    cells = [
        "begin\n    import Pkg\n    Pkg.activate($(repr(abspath(project))); io = devnull)\n    using PerfChecker, PlutoUI, Markdown\nend",
        "md\"\"\"# PerfChecker suite\nFilter the plan, then press **Launch selected checks**. Changing controls never starts workers. Use **Refresh status** while a job runs, then **Save completed reports**.\"\"\"",
        "suite_path = $suite_literal",
        "result_path = $(repr(normpath(joinpath(dirname(target), result_path))))",
        "reports_root = $(repr(normpath(joinpath(dirname(target), reports_root))))",
        "full_plan = suite_path === nothing ? nothing : plan_suite(load_software_suite(suite_path; factory = $(repr(factory))); profile = $(repr(profile)))",
        "begin\n    available_runs = full_plan === nothing ? [] : full_plan.runs\n    package_names = sort!(unique([run.package_suite.package for run in available_runs]))\n    workload_names = sort!(unique([string(PerfChecker.workload_id(run)) for run in available_runs]))\n    collector_names = sort!(unique([string(run.feature.backend) for run in available_runs]))\n    target_names = sort!(unique([run.target.label for run in available_runs]))\nend",
        control("Package",
            "@bind selected_package Select(vcat([\"\" => \"All packages\"], [name => name for name in package_names]))"),
        control("Workload",
            "@bind selected_workload Select(vcat([\"\" => \"All workloads\"], [name => name for name in workload_names]))"),
        control("Collector",
            "@bind selected_collector Select(vcat([\"\" => \"All collectors\"], [name => name for name in collector_names]); default = \"benchmark\" in collector_names ? \"benchmark\" : \"\")"),
        control("Target",
            "@bind selected_target Select(vcat([\"\" => \"All targets\"], [name => name for name in target_names]))"),
        "filtered_plan = full_plan === nothing ? nothing : filter_suite_plan(full_plan; packages = isempty(selected_package) ? nothing : selected_package, features = isempty(selected_workload) ? nothing : selected_workload, backends = isempty(selected_collector) ? nothing : selected_collector)",
        "selected_plan = filtered_plan === nothing ? nothing : SuitePlan(filtered_plan.suite, filtered_plan.profile, [run for run in filtered_plan.runs if isempty(selected_target) || run.target.label == selected_target], filtered_plan.comparisons)",
        "selected_plan === nothing ? md\"No executable suite: this notebook reads saved reports.\" : Markdown.parse(\"```text\\n\" * sprint(print_suite_plan, selected_plan) * \"\\n```\")",
        control("Samples", "@bind samples NumberField(1:10000; default = 50)"),
        control("Seconds per benchmark",
            "@bind seconds NumberField(0.1:0.1:60; default = 0.5)"),
        control("Worker threads", "@bind worker_threads NumberField(1:4; default = 1)"),
        action_button,
        "begin\n    last_launch = Ref(\"\")\n    last_cancel = Ref(\"\")\n    last_save = Ref(\"\")\n    active_job = Ref{Any}(nothing)\n    last_saved = Ref(\"\")\nend",
        "@bind launch_click SuiteActionButton(\"Launch selected checks\")",
        """job = begin
    if launch_click isa AbstractString && !isempty(launch_click) && launch_click != last_launch[]
        last_launch[] = launch_click
        if active_job[] !== nothing && suite_job_status(active_job[]) ∉ (:complete, :failed, :cancelled)
            error("A job is already running. Refresh or cancel it before launching another.")
        end
        selected_plan === nothing && error("This notebook has no executable suite.")
        isempty(selected_plan.runs) && error("The selection contains no checks.")
        active_job[] = launch_suite(selected_plan; overrides = Dict{Symbol, Any}(
            :samples => samples, :seconds => seconds, :threads => worker_threads, :evals => 1))
    end
    active_job[]
end""",
        "@bind cancel_click SuiteActionButton(\"Cancel active job\")",
        "if cancel_click isa AbstractString && !isempty(cancel_click) && cancel_click != last_cancel[]\n    last_cancel[] = cancel_click\n    job === nothing || cancel!(job)\nend",
        "@bind refresh_click CounterButton(\"Refresh status\")",
        "snapshot = (refresh_click; job === nothing ? Dict(\"state\" => \"idle\") : suite_job_progress(job))",
        "HTML(\"<p role='status' data-suite-state='\" * get(snapshot, \"state\", \"idle\") * \"'><strong>Status:</strong> \" * get(snapshot, \"state\", \"idle\") * \" · \" * string(get(snapshot, \"completed\", 0)) * \" / \" * string(get(snapshot, \"total\", 0)) * \" checks completed</p>\")",
        "job_result = (snapshot; job === nothing || suite_job_status(job) ∉ (:complete, :failed) ? nothing : wait_suite(job; strict = false))",
        "@bind save_click SuiteActionButton(\"Save completed reports\")",
        """saved_reports = begin
if save_click isa AbstractString && !isempty(save_click) && save_click != last_save[]
    last_save[] = save_click
    job_result === nothing && error("Refresh a completed job before saving.")
    mkpath(reports_root)
    destination = mktempdir(reports_root; prefix = "pluto-", cleanup = false)
    write_suite_reports(job_result, destination)
    last_saved[] = joinpath(basename(reports_root), basename(destination))
end
isempty(last_saved[]) ? "No saved reports yet." : "Last saved reports: " * last_saved[]
end""",
        "report = job_result !== nothing ? suite_dict(job_result) : isfile(result_path) ? PerfChecker._json_parsefile(result_path) : Dict(\"status\" => \"missing\", \"message\" => \"Launch selected checks or choose an existing suite-result.json.\")",
        "runs = get(report, \"runs\", Any[])",
        "md\"\"\"## Results\nA completed collector is not a correctness proof or a performance comparison. Save the reports to inspect correctness and comparison fields in the complete bundle.\"\"\"",
        "isempty(runs) ? md\"No completed checks yet.\" : Markdown.parse(\"| Package | Workload | Target | Status |\\n| --- | --- | --- | --- |\\n\" * join([\"| \" * join([replace(string(get(run, key, \"\")), \"|\" => \"/\", '\\n' => ' ') for key in (\"package\", \"workload\", \"version\", \"status\")], \" | \") * \" |\" for run in runs], \"\\n\"))"
    ]
    append!(cells,
        [
            "md\"\"\"## Performance curves\nThe default overlay divides each metric by its own minimum across versions. Select an individual plot to read absolute units. Plotting uses PerfCheckerMakie and WGLMakie in the notebook environment.\"\"\"",
            "plot_bundle = job_result !== nothing ? PerfChecker._suite_run_bundle(job_result) : begin; saved_bundle = joinpath(dirname(result_path), \"bundles\", \"run-\" * string(get(report, \"run_id\", \"\"))); isdir(saved_bundle) ? read_run_bundle(saved_bundle) : nothing; end",
            "plot_entries = plot_bundle === nothing ? [] : plot_catalog(plot_bundle)",
            "@bind selected_plot Select(isempty(plot_entries) ? [\"\" => \"No completed measurements\"] : [entry[\"id\"] => entry[\"title\"] * \" · \" * entry[\"label\"] for entry in plot_entries])",
            plot_frame,
            "if plot_bundle !== nothing && !isempty(selected_plot); if Base.find_package(\"PerfCheckerMakie\") === nothing || Base.find_package(\"WGLMakie\") === nothing; md\"Install PerfCheckerMakie and WGLMakie in this notebook environment to display plots.\"; else; @eval using PerfCheckerMakie, WGLMakie; let plot = performance_plot(plot_bundle, selected_plot); SuitePlotFrame(performance_plot_html(plot), \"Performance plot: \" * plot.title); end; end; end"
        ])
    # Keep internal plans, paths and task objects out of the rendered dashboard.
    hidden_outputs = Set(["suite_path", "result_path", "reports_root", "full_plan",
        "filtered_plan", "selected_plan", "job", "snapshot", "job_result",
        "report", "runs", "plot_bundle", "plot_entries"])
    cells = map(cells) do cell
        binding = match(r"^([a-z_]+) =(?!=)", cell)
        startswith(cell, "begin\n") ||
            (binding !== nothing && binding.captures[1] in hidden_outputs) ? cell * ";" :
        cell
    end
    compact = String[]
    pending = String[]
    for cell in cells
        if endswith(cell, ";")
            push!(pending, cell)
        else
            if !isempty(pending)
                push!(compact, "begin\n" * join(pending, '\n') * "\nend;")
                empty!(pending)
            end
            push!(compact, cell)
        end
    end
    isempty(pending) || push!(compact, "begin\n" * join(pending, '\n') * "\nend;")
    cells = compact
    foreach(cell -> JuliaSyntax.parseall(JuliaSyntax.SyntaxNode, cell), cells)
    identifiers = [string(uuid4()) for _ in cells]
    mkpath(dirname(target))
    open(target, "w") do io
        println(io, "### A Pluto.jl notebook ###\n# v0.20\n")
        for (id, cell) in zip(identifiers, cells)
            println(io, "# ╔═╡ ", id, '\n', cell, '\n')
        end
        println(io, "# ╔═╡ Cell order:")
        foreach(id -> println(io, "# ╟─", id), identifiers)
    end
    return target
end
