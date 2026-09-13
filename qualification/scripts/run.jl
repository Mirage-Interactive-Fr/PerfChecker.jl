using PerfCheckerQualification, TOML, Pkg

# Keep the driver and its sequential workers within a four-thread computation budget.
Threads.nthreads() <= 4 || error("Qualification allows at most four Julia compute threads")
for variable in ("OPENBLAS_NUM_THREADS", "OMP_NUM_THREADS", "MKL_NUM_THREADS",
    "JULIA_NUM_PRECOMPILE_TASKS", "UV_THREADPOOL_SIZE")
    ENV[variable] = "1"
end
ENV["JULIA_NUM_THREADS"] = "1"
ENV["JULIA_NUM_GC_THREADS"] = "1"

root = normpath(joinpath(@__DIR__, "../.."))
plan = TOML.parsefile(get(
    ENV, "PERFCHECKER_PLAN", joinpath(root, ".qualification/plan.toml")))
lane = only(filter(l -> l["id"] == only(ARGS), plan["lanes"]))
actual_os = Sys.iswindows() ? "windows-latest" :
            Sys.islinux() ? "ubuntu-latest" : "unsupported"
actual_os == lane["os"] || error("Lane does not match this platform")
revision = strip(read(`git -C $root rev-parse HEAD`, String))
revision == plan["revision"] || error("Source changed since planning")
output = joinpath(root, ".qualification/results", lane["id"])
mkpath(output)
receipt = Dict{String, Any}("schema" => "perfchecker-qualification-receipt/1",
    "plan_id" => plan["id"], "lane" => lane["id"], "revision" => revision,
    "os" => actual_os, "runtime" => string(VERSION), "status" => "failed",
    "dirty" => !isempty(strip(read(
        `git -C $root status --porcelain --untracked-files=normal`, String))),
    "compute_thread_budget" => 4,
    "environments" => Dict{String, Any}[], "external_revision" => "")
julia = Base.julia_cmd()
environment = mktempdir()

function capture_environment(directory, label)
    records = Dict{String, Any}("label" => label)
    for file in ("Project.toml", "Manifest.toml", "package.json", "package-lock.json")
        source = joinpath(directory, file)
        isfile(source) || continue
        target = label * "-" * file
        cp(source, joinpath(output, target); force = true)
        records[file] = Dict("file" => target, "sha256" => file_digest(source))
        if file == "Manifest.toml"
            manifest = TOML.parsefile(source)
            records["packages"] = [merge(Dict("name" => name),
                                       Dict(key => string(entry[key])
                                       for key in ("uuid", "version",
                                               "git-tree-sha1", "repo-rev")
                                       if haskey(entry, key)))
                                   for (name, entries) in get(manifest, "deps", Dict())
                                   for entry in entries]
        end
    end
    length(records) > 1 || error("No environment captured")
    push!(receipt["environments"], records)
end

function prepare(project = nothing; packages = String[],
        satellites = String[], shared = false, first_check = false)
    if project !== nothing
        cp(joinpath(root, project, "Project.toml"),
            joinpath(environment, "Project.toml"); force = true)
    end
    Pkg.activate(environment)
    Pkg.develop([Pkg.PackageSpec(path = root);
                 [Pkg.PackageSpec(path = joinpath(root, "packages", name))
                  for name in satellites]])
    shared && Pkg.develop(path = joinpath(root, "examples/shared-scenarios"))
    first_check && Pkg.develop(path = joinpath(root, "examples/first-check"))
    isempty(packages) || Pkg.add(packages)
    Pkg.instantiate()
    capture_environment(environment, "julia")
end

function execute(file; tags = "", extra = String[])
    command = `$julia --startup-file=no --project=$environment $(joinpath(root, file)) $extra`
    run(addenv(command, "PERFCHECKER_TEST_TAGS" => tags,
        "PERFCHECKER_SHARED_REPORTS" => joinpath(output, "shared-results"),
        "JULIA_LOAD_PATH" => "@" * (Sys.iswindows() ? ";" : ":") * "@stdlib"))
end

try
    suite = lane["suite"]
    if suite == "style"
        Pkg.activate(environment)
        Pkg.add(Pkg.PackageSpec(name = "JuliaFormatter", version = "1.0.50"))
        capture_environment(environment, "formatter")
        execute("qualification/scripts/style.jl")
    elseif suite == "contracts"
        run(`$julia --startup-file=no --project=$(joinpath(root, "qualification")) $(joinpath(root, "qualification/test/runtests.jl"))`)
        capture_environment(joinpath(root, "qualification"), "qualification")
    elseif suite in ("core", "legacy_protocol")
        # Explicit test environment preserves the exact solver output as evidence.
        project = TOML.parsefile(joinpath(root, "Project.toml"))
        deps = merge(project["deps"], project["extras"])
        compat = Dict(k => v
        for (k, v) in project["compat"] if k == "julia" || haskey(deps, k))
        if suite == "legacy_protocol"
            compat["HTTP"] = "1"
            compat["JSON"] = "=0.21.4"
        end
        write_toml(
            joinpath(environment, "Project.toml"), Dict("deps" => deps, "compat" => compat))
        prepare()
        execute("test/runtests.jl")
    elseif suite == "native"
        prepare("test/environments/native-items"; first_check = true)
        execute("test/runtests.jl"; tags = "v1")
        execute("qualification/shared/contracts.jl")
        execute("examples/first-check/run.jl")
    elseif suite == "shared"
        prepare(;
            packages = ["BenchmarkTools", "Chairmarks", "TestItemRunner", "HTTP", "Oxygen"],
            satellites = ["PerfCheckerWeb"],
            shared = true)
        execute("test/runtests.jl";
            tags = "shared_scenarios,memory_diagnostics,development_provenance,worker_environment")
        execute("test/shared_integration.jl")
        execute("test/shared_legacy.jl")
        execute("test/shared_studio.jl")
    elseif suite == "web"
        run(`node $(joinpath(root, "qualification/shared/web_assets.mjs"))`)
        prepare(
            "test/environments/oxygen-latest"; packages = ["BenchmarkTools", "Chairmarks"],
            satellites = ["PerfCheckerWeb", "PerfCheckerMakie"], shared = true)
        execute("packages/PerfCheckerWeb/test/runtests.jl")
        execute("test/advisor_setup_web.jl")
        execute("test/shared_studio.jl")
        execute("qualification/shared/contracts.jl")
    elseif suite in ("advisor_http1", "advisor_http2")
        project = TOML.parsefile(joinpath(
            root, "test/environments/advisor-ui/Project.toml"))
        project["compat"]["HTTP"] = suite == "advisor_http1" ? "1" : "2"
        write_toml(joinpath(environment, "Project.toml"), project)
        prepare(; satellites = ["PerfCheckerWeb"])
        execute("test/runtests.jl"; tags = "advisor_setup,advisor_mcp,advisor_http,advisor")
        execute("test/advisor_setup_web.jl")
    elseif suite == "pluto"
        prepare(; packages = ["Pluto", "PlutoUI", "TestItemRunner", "JSON"],
            satellites = ["PerfCheckerPluto"])
        execute("test/advisor_setup_notebook.jl")
        execute("qualification/shared/pluto.jl")
        execute("packages/PerfCheckerPluto/test/runtests.jl")
        execute("packages/PerfCheckerPluto/test/generated_controls.jl")
        execute("qualification/shared/contracts.jl")
    elseif suite == "plots"
        prepare("test/environments/wgl"; satellites = ["PerfCheckerMakie"])
        execute("packages/PerfCheckerMakie/test/runtests.jl")
    elseif suite == "legacy_interfaces"
        project = TOML.parsefile(joinpath(root, "Project.toml"))
        deps = merge(project["deps"], project["extras"])
        compat = Dict(k => v
        for (k, v) in project["compat"] if k == "julia" || haskey(deps, k))
        write_toml(
            joinpath(environment, "Project.toml"), Dict("deps" => deps, "compat" => compat))
        prepare(; packages = ["Makie", "Oxygen", "Pluto"],
            satellites = ["PerfCheckerWeb", "PerfCheckerPluto", "PerfCheckerMakie"])
        execute("qualification/shared/legacy_runner.jl")
    elseif suite == "analyzers"
        prepare("test/environments/analyzers")
        execute("test/latest_analyzers.jl")
    elseif suite == "docs"
        cd(joinpath(root, "website")) do
            Pkg.activate(".")
            Pkg.develop(path = "..")
            Pkg.instantiate()
        end
        capture_environment(joinpath(root, "website"), "documentation")
        run(`$julia --startup-file=no --project=$(joinpath(root, "website")) $(joinpath(root, "website/make.jl"))`)
        capture_environment(joinpath(root, "website"), "documentation-built")
        site = joinpath(root, "website/build/site")
        isfile(joinpath(site, "index.html")) || error("Documentation has no index.html")
        npm = Sys.iswindows() ? `cmd /d /c npm.cmd` : `npm`
        tooling = joinpath(root, "qualification")
        run(Cmd(`$npm ci --ignore-scripts --no-audit --no-fund`; dir = tooling))
        # Prepared local machines can install OS libraries separately; CI keeps
        # the complete dependency installation as its default.
        browser_install = get(ENV, "PERFCHECKER_BROWSER_DEPS_READY", "false") == "true" ?
                          `$npm exec -- playwright install chromium` :
                          `$npm exec -- playwright install --with-deps chromium`
        run(Cmd(browser_install; dir = tooling))
        capture_environment(tooling, "browser-tooling")
        run(`node $(joinpath(root, "qualification/shared/website-browser.mjs")) $output`)
        receipt["site_sha256"] = tree_digest(site)
    elseif suite == "vscode"
        client = get(
            ENV, "PERFCHECKER_VSCODE_ROOT", joinpath(root, ".qualification/vscode"))
        external = strip(read(`git -C $client rev-parse HEAD`, String))
        external == plan["sources"]["vscode"]["revision"] ||
            error("VS Code checkout does not match candidate collection")
        receipt["external_revision"] = external
        receipt["dirty"] |= !isempty(strip(read(
            `git -C $client status --porcelain`, String)))
        npm = Sys.iswindows() ? `cmd /d /c npm.cmd` : `npm`
        run(Cmd(`$npm ci`; dir = client))
        run(Cmd(`$npm test`; dir = client))
        # A client without the native-item contract cannot qualify this V1.
        isfile(joinpath(client, "test/native-items-host.test.mjs")) ||
            error("VS Code candidate lacks native item qualification")
        capture_environment(client, "vscode")
        prepare("test/environments/native-items")
        execute("qualification/shared/contracts.jl")
        run(Cmd(`$npm ci --ignore-scripts --no-audit --no-fund`;
            dir = joinpath(root, "qualification")))
        capture_environment(joinpath(root, "qualification"), "host-tooling")
        host = `node $(joinpath(root, "qualification/shared/vscode-host.mjs")) $client $environment $output`
        host = Sys.islinux() ? `xvfb-run -a $host` : host
        run(addenv(host, "PERFCHECKER_JULIA_EXECUTABLE" => first(julia.exec)))
        host_result = joinpath(output, "vscode-host-result.json")
        push!(receipt["environments"],
            Dict("label" => "vscode-host",
                "result" => Dict(
                    "file" => basename(host_result), "sha256" => file_digest(host_result))))
        run(Cmd(
            `$npm run package:pre-release -- --out $(joinpath(output, "perfchecker-vscode.vsix"))`;
            dir = client))
        receipt["dirty"] |= !isempty(strip(read(
            `git -C $client status --porcelain`, String)))
    else
        error("Suite has no runner: $suite")
    end
    # Test code may not silently change the qualified controller environment.
    for env in receipt["environments"]
        if env["label"] == "julia" && haskey(env, "Manifest.toml")
            file_digest(joinpath(environment, "Manifest.toml")) ==
            env["Manifest.toml"]["sha256"] || error("Environment changed during tests")
        end
    end
    # A lane may not promote source modifications made during preparation/tests.
    receipt["dirty"] |= !isempty(strip(read(
        `git -C $root status --porcelain --untracked-files=normal`, String)))
    strip(read(`git -C $root rev-parse HEAD`, String)) == revision ||
        error("Source revision changed during qualification")
    receipt["status"] = "passed"
finally
    write_toml(joinpath(output, "receipt.toml"), receipt)
end
