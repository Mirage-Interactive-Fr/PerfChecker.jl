"Write a Pluto dashboard with explicit launch/cancel controls over the shared investigation APIs. Requires PlutoUI in the selected controller environment."
function PerfChecker.write_investigation_notebook(
        path::AbstractString; root::AbstractString = pwd(),
        catalog::AbstractString = joinpath(root, "perf", "scenarios.toml"),
        project::AbstractString = root, force::Bool = false)
    isfile(path) && !force &&
        throw(ArgumentError("notebook exists; use force=true to replace it"))
    cells = [
        "begin\n    import Pkg\n    Pkg.activate($(repr(abspath(project))))\n    using PerfChecker, PerfCheckerPluto, PlutoUI, Markdown\nend",
        "package_root = $(repr(abspath(root)))",
        "catalogue = isfile($(repr(abspath(catalog)))) ? load_scenario_catalog($(repr(abspath(catalog)))) : ScenarioCatalog(package_root, ScenarioSpec[])",
        "begin\n    last_launch = Ref(0)\n    last_cancel = Ref(0)\n    active_job = Ref{Any}(nothing)\nend",
        "md\"\"\"# PerfChecker investigations\nChoose declared scenarios and an action, then press **Launch**. Changing a selector never starts a measurement.\"\"\"",
        "@bind selected MultiSelect([string(i) => (s.id * \" / \" * s.implementation) for (i,s) in enumerate(catalogue.scenarios)]; default = string.(eachindex(catalogue.scenarios)))",
        "@bind action Select([\"discover\", \"run\", \"diagnose\", \"sync\", \"tools\", \"investigate\", \"narrate\"])",
        "@bind tools MultiSelect([t[\"tool\"] => t[\"scope\"] for t in diagnostic_capabilities()]; default=[\"jet\", \"latency\"])",
        "@bind timeout NumberField(1:3600; default=120)",
        "@bind advisor_file TextField(; placeholder=\"Optional advisor configuration JSON path\")",
        "md\"\"\"## Optional advisor setup\nConfigure a local model, a remote HTTPS endpoint or an MCP advice tool. **Probe** lists models/tools without sending evidence. **Pull/delete/unload** affect the shared local Ollama server and require explicit confirmation. Sizes reported by Ollama include shared layers; free disk space and exact download size may be unavailable. [Install/start Ollama](https://docs.ollama.com/quickstart).\"\"\"",
        "begin\n    last_setup = Ref(0)\n    last_setup_cancel = Ref(0)\n    setup_job = Ref{Any}(nothing)\nend",
        "@bind setup_protocol Select([\"ollama\", \"chat_completions\", \"chat_completions_schema\", \"mcp_http\"])",
        "@bind setup_endpoint TextField(; default=\"http://127.0.0.1:11434/api/chat\")",
        "@bind setup_model TextField(; default=\"qwen3:0.6b\")",
        "@bind setup_remote CheckBox(; default=false)",
        "@bind setup_key_environment TextField(; placeholder=\"Credential environment variable name, never its value\")",
        "@bind setup_instructions TextField((70, 4); placeholder=\"Custom performance advice instructions\")",
        "@bind setup_mcp_tool TextField(; placeholder=\"Selected MCP advice tool; probe first\")",
        "@bind setup_mcp_argument TextField(; default=\"prompt\")",
        "@bind setup_mcp_arguments TextField(; default=\"{}\")",
        "@bind setup_mcp_version Select([\"2026-07-28\", \"2025-11-25\"])",
        "@bind setup_mcp_response Select([\"text\", \"structured\"])",
        "@bind setup_timeout NumberField(1:3600; default=300)",
        "@bind setup_action Select([\"probe\", \"models\", \"save\", \"pull\", \"delete\", \"unload\"])",
        "@bind setup_confirm CheckBox(; default=false)",
        "md\"\"\"The confirmation checkbox authorizes the exact named model operation, or replacement of an existing configuration when saving. Downloads can leave partial files after cancellation. Deletion affects other projects sharing the server. Saving uses the **advisor file** path above.\"\"\"",
        "@bind setup_click CounterButton(\"Execute selected setup action\")",
        """setup_result = begin
    if setup_click > last_setup[]
        last_setup[] = setup_click
        if setup_job[] === nothing || investigation_status(setup_job[])["status"] != "running"
            draft = Dict("protocol"=>setup_protocol, "endpoint"=>setup_endpoint, "model"=>setup_model,
                "allow_remote"=>setup_remote, "api_key_env"=>setup_key_environment, "instructions"=>setup_instructions,
                "timeout"=>setup_timeout, "mcp_tool"=>setup_mcp_tool, "mcp_prompt_argument"=>setup_mcp_argument,
                "mcp_arguments"=>PerfChecker._json_parse(setup_mcp_arguments), "mcp_version"=>setup_mcp_version,
                "mcp_response"=>setup_mcp_response)
            if setup_action == "save"
                isempty(advisor_file) && error("Choose the advisor configuration file path first.")
                isfile(advisor_file) && !setup_confirm && error("Confirm replacement of the existing configuration.")
                validated = advisor_setup(draft; action=:validate)
                mkpath(dirname(abspath(advisor_file)))
                PerfChecker._write_json(advisor_file, validated["config"]; canonical=true)
                "Saved configuration. No provider was called."
            else
                setup_job[] = launch_advisor_setup(draft; action=Symbol(setup_action), model=setup_model,
                    confirmed=setup_confirm, project=$(repr(abspath(project))))
                "Setup launched. Refresh to inspect the available models/tools."
            end
        end
    else
        "Setup idle; changing fields does not send a request."
    end
end""",
        "@bind setup_cancel_click CounterButton(\"Cancel advisor setup\")",
        "if setup_cancel_click > last_setup_cancel[]\n    last_setup_cancel[] = setup_cancel_click\n    setup_job[] === nothing || cancel!(setup_job[])\nend",
        "@bind setup_refresh CounterButton(\"Refresh advisor setup / model inventory\")",
        "setup_snapshot = (setup_refresh; setup_job[] === nothing ? Dict(\"status\"=>\"idle\") : investigation_status(setup_job[]))",
        "@bind evidence_file TextField(; placeholder=\"Saved advice JSON path for narration\")",
        "@bind max_experiments NumberField(1:100; default=4)",
        "@bind budget_seconds NumberField(1:86400; default=300)",
        "@bind launch_click CounterButton(\"Launch selected action\")",
        """job = begin
    if launch_click > last_launch[]
        last_launch[] = launch_click
        if active_job[] === nothing || investigation_status(active_job[])["status"] != "running"
            chosen = ScenarioCatalog(catalogue.root, catalogue.scenarios[parse.(Int, selected)])
            active_job[] = launch_investigation(Symbol(action); root=package_root, catalog=chosen,
                project=$(repr(abspath(project))), tools=Symbol.(tools), timeout, max_experiments, budget_seconds,
                advisor=isempty(advisor_file) ? nothing : load_advisor_config(advisor_file),
                evidence=isempty(evidence_file) ? nothing : read_advice(evidence_file),
                reports=joinpath(package_root, "perf", "results", "notebook", string(time_ns())))
        end
    end
    active_job[]
end""",
        "@bind cancel_click CounterButton(\"Cancel active investigation\")",
        "if cancel_click > last_cancel[]\n    last_cancel[] = cancel_click\n    job === nothing || cancel!(job)\nend",
        "@bind refresh_click CounterButton(\"Refresh status and evidence\")",
        "snapshot = (refresh_click; job === nothing ? Dict(\"status\"=>\"idle\") : investigation_status(job))",
        "haskey(snapshot, \"result\") ? investigation_view(snapshot[\"result\"]) : snapshot",
        "haskey(snapshot, \"advice\") ? investigation_view(snapshot[\"advice\"]) : \"No saved advice yet.\"",
        "md\"\"\"## Before / after\nSupply directories of saved scenario bundles. Comparisons do not execute the target code.\"\"\"",
        "@bind baseline_directory TextField(; placeholder=\"Baseline bundle directory\")",
        "@bind candidate_directory TextField(; placeholder=\"Candidate bundle directory\")",
        "@bind compare_click CounterButton(\"Compare saved measurements\")",
        "compare_click > 0 && !isempty(baseline_directory) && !isempty(candidate_directory) ? investigation_view(compare_scenarios(read_scenario_runs(baseline_directory), read_scenario_runs(candidate_directory))) : \"No comparison selected.\""
    ]
    labels = Dict(
        "setup_protocol" => "Provider protocol", "setup_endpoint" => "Provider endpoint",
        "setup_model" => "Exact model name or MCP report label", "setup_remote" => "Allow a remote HTTPS connection",
        "setup_key_environment" => "Credential environment variable name", "setup_instructions" => "Custom advice instructions",
        "setup_mcp_tool" => "Selected MCP tool", "setup_mcp_argument" => "MCP argument receiving the prompt",
        "setup_mcp_arguments" => "Other MCP arguments as JSON", "setup_mcp_version" => "MCP protocol version",
        "setup_mcp_response" => "MCP response mode", "setup_timeout" => "Maximum setup duration in seconds",
        "setup_action" => "Setup action", "setup_confirm" => "Confirm the exact model operation or configuration replacement")
    labelled = String[]
    for cell in cells
        binding = match(r"^@bind ([A-Za-z_]+) ", cell)
        if binding !== nothing && haskey(labels, binding.captures[1])
            push!(labelled, "md" * repr("**" * labels[binding.captures[1]] * "**"))
        end
        push!(labelled, cell)
    end
    cells = labelled
    # Validate generated syntax before creating the user's notebook.
    foreach(cell -> JuliaSyntax.parseall(JuliaSyntax.SyntaxNode, cell), cells)
    identifiers = [string(uuid4()) for _ in cells]
    mkpath(dirname(abspath(path)))
    open(path, "w") do io
        println(io, "### A Pluto.jl notebook ###\n# v0.20\n")
        for (id, cell) in zip(identifiers, cells)
            println(io, "# ╔═╡ ", id, '\n', cell, '\n')
        end
        println(io, "# ╔═╡ Cell order:")
        foreach(id -> println(io, "# ╠═", id), identifiers)
    end
    return abspath(path)
end
