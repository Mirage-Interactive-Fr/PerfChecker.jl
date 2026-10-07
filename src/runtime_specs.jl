const JULIA_RUNTIME_SPEC_SCHEMA = "perfchecker-julia-runtime-spec/1"
const JULIA_RUNTIME_PROBE_SCHEMA = "perfchecker-julia-runtime-probe/1"

"""
    JuliaRuntimeSpec(id::Symbol, selector::AbstractString;
                     role=:candidate, source=:juliaup,
                     executable="julia", arguments=String[])

Describe one Julia executable in a runtime campaign, independently of the
package versions selected by its suite. `role` is `:baseline`, `:candidate` or
`:control`; a campaign requires exactly one baseline.

With `source=:juliaup`, the command is `executable +selector` (for example,
`julia +1.10`). With `source=:executable`, `executable` must name an existing
file and the nonempty `selector` is its descriptive label. `arguments` are
additional command-prefix arguments, copied as strings. Construction validates
these fields but neither installs a Julia channel nor launches a process.

```julia
baseline = JuliaRuntimeSpec(:lts, "1.10"; role=:baseline)
candidate = JuliaRuntimeSpec(:current, "release")
```
"""
struct JuliaRuntimeSpec
    id::Symbol
    selector::String
    role::Symbol
    source::Symbol
    executable::String
    arguments::Vector{String}
end

function JuliaRuntimeSpec(id::Symbol, selector::AbstractString;
        role::Symbol = :candidate, source::Symbol = :juliaup,
        executable::AbstractString = "julia", arguments = String[])
    role in (:baseline, :candidate, :control) || throw(ArgumentError(
        "Julia runtime role must be baseline, candidate, or control"))
    source in (:juliaup, :executable) || throw(ArgumentError(
        "Julia runtime source must be juliaup or executable"))
    normalized = strip(String(selector))
    isempty(normalized) && throw(ArgumentError("a Julia runtime selector is required"))
    command = String(executable)
    source === :executable && !isfile(command) &&
        throw(ArgumentError(
            "Julia executable does not exist: $command"))
    return JuliaRuntimeSpec(id, normalized, role, source, command, String.(arguments))
end

"""
    julia_runtime_spec_dict(spec::JuliaRuntimeSpec) -> Dict{String,Any}

Return a `perfchecker-julia-runtime-spec/1` declaration containing `id`,
`selector`, `role`, `source`, `executable` and `arguments`. Symbols become
strings. This does not resolve the selector to an installed runtime; use
[`probe_julia_runtime`](@ref) for an observed version and commit.
"""
function julia_runtime_spec_dict(spec::JuliaRuntimeSpec)
    return Dict{String, Any}(
        "schema_version" => JULIA_RUNTIME_SPEC_SCHEMA,
        "id" => string(spec.id), "selector" => spec.selector,
        "role" => string(spec.role), "source" => string(spec.source),
        "executable" => spec.executable, "arguments" => spec.arguments)
end

"""
    julia_runtime_command(spec::JuliaRuntimeSpec; project=nothing,
                          startup_file=false, history_file=false,
                          extra_arguments=String[]) -> Vector{String}

Build command arguments without executing them. Append the Juliaup selector
when required, `spec.arguments`, startup/history flags, an absolute
`--project` path when supplied, then `extra_arguments`. Startup and REPL history
files are disabled by default; the command still uses the caller's environment
and Julia depot.

```julia
spec = JuliaRuntimeSpec(:lts, "1.10"; role=:baseline)
command = julia_runtime_command(spec; project=pwd(),
    extra_arguments=["-e", "println(VERSION)"])
# Execute explicitly when desired: run(Cmd(command))
```
"""
function julia_runtime_command(spec::JuliaRuntimeSpec; project = nothing,
        startup_file::Bool = false, history_file::Bool = false,
        extra_arguments = String[])
    command = String[spec.executable]
    spec.source === :juliaup && push!(command, "+$(spec.selector)")
    append!(command, spec.arguments)
    push!(command, "--startup-file=$(startup_file ? "yes" : "no")")
    push!(command, "--history-file=$(history_file ? "yes" : "no")")
    project === nothing || push!(command, "--project=$(abspath(String(project)))")
    append!(command, String.(extra_arguments))
    return command
end

"""
    julia_runtime_matrix(; baseline="release", candidates=["rc", "nightly"])
        -> Vector{JuliaRuntimeSpec}

Create a Juliaup runtime axis with baseline ID `:baseline` and candidate IDs
`:candidate_1`, `:candidate_2`, and so on, preserving candidate order. The
selectors must already be usable when the campaign executes; this function
does not install or probe channels. Override `candidates` to use explicit
installed versions instead of moving aliases.

```julia
julia_runtime_matrix(baseline="1.10", candidates=["1.12", "1.13"])
```
"""
function julia_runtime_matrix(; baseline::AbstractString = "release",
        candidates = ["rc", "nightly"])
    specs = JuliaRuntimeSpec[JuliaRuntimeSpec(:baseline, baseline; role = :baseline)]
    for (index, selector) in enumerate(candidates)
        id = Symbol("candidate_", index)
        push!(specs, JuliaRuntimeSpec(id, String(selector); role = :candidate))
    end
    return specs
end

"""
    julia_runtime_suite_command(spec::JuliaRuntimeSpec; suite, reports,
        profile=:ci, factory=:build_suite,
        perfchecker_project=dirname(@__DIR__),
        controller_project=dirname(abspath(suite)), backend_packages=String[])
        -> Vector{String}

Build a child-controller invocation of `bin/perfchecker-runtime-suite.jl` for
`spec`. `suite` is a Julia suite definition; `reports` is its output directory.
`perfchecker_project` must contain that CLI, and `controller_project` must
contain `Project.toml`. Paths become absolute. The factory/profile and each
requested backend package are passed to the CLI.

This validates local input files but does not start Julia, prepare dependencies
or create reports. The runtime campaign constructs separate controller projects
for its runtimes; callers using this lower-level function supply their own.
"""
function julia_runtime_suite_command(spec::JuliaRuntimeSpec;
        suite::AbstractString, reports::AbstractString,
        profile::Symbol = :ci, factory::Symbol = :build_suite,
        perfchecker_project::AbstractString = dirname(@__DIR__),
        controller_project::AbstractString = dirname(abspath(String(suite))),
        backend_packages::AbstractVector{<:AbstractString} = String[])
    suite_path = abspath(String(suite))
    isfile(suite_path) || throw(ArgumentError("suite file does not exist: $suite_path"))
    project = abspath(String(perfchecker_project))
    controller = abspath(String(controller_project))
    isfile(joinpath(controller, "Project.toml")) || throw(ArgumentError(
        "runtime controller Project.toml does not exist: $controller"))
    cli = joinpath(project, "bin", "perfchecker-runtime-suite.jl")
    isfile(cli) || throw(ArgumentError("PerfChecker suite CLI does not exist: $cli"))
    arguments = [cli, "--perfchecker-project=$project", "--suite=$suite_path",
        "--reports=$(abspath(String(reports)))", "--profile=$(string(profile))",
        "--factory=$(string(factory))"]
    append!(
        arguments, ["--backend-package=$(String(package))"
                    for package in backend_packages])
    return julia_runtime_command(spec; project = controller,
        extra_arguments = arguments)
end

"""
    probe_julia_runtime(spec::JuliaRuntimeSpec; project=nothing)
        -> Dict{String,Any}

Launch a fresh Julia process with `--compile=min` and return its observed
`version`, Git `commit`, `bindir`, `llvm_version`, command, UTC resolution time
and declared spec under schema `perfchecker-julia-runtime-probe/1`. Startup and
history files are disabled. `project`, when supplied, selects the child project.

The executable/channel must be available. Process launch failures, nonzero
exits and unexpected output are raised to the caller; no runtime is installed
and no workload is measured.
"""
function probe_julia_runtime(spec::JuliaRuntimeSpec; project = nothing)
    script = "print(string(VERSION), '\\t', Base.GIT_VERSION_INFO.commit, '\\t', Sys.BINDIR, '\\t', Base.libllvm_version)"
    command = julia_runtime_command(spec; project,
        extra_arguments = ["--compile=min", "-e", script])
    output = readchomp(Cmd(command))
    fields = split(output, '\t'; keepempty = true)
    length(fields) == 4 || throw(ErrorException(
        "unexpected Julia runtime probe output for $(spec.selector)"))
    return Dict{String, Any}(
        "schema_version" => JULIA_RUNTIME_PROBE_SCHEMA,
        "spec" => julia_runtime_spec_dict(spec),
        "version" => fields[1], "commit" => fields[2],
        "bindir" => fields[3], "llvm_version" => fields[4],
        "command" => command,
        "resolved_at" => string(Dates.now(Dates.UTC)))
end

@testitem "Julia runtime axis" tags=[:unit, :runtime, :protocol] begin
    using PerfChecker

    specs = julia_runtime_matrix(; baseline = "release", candidates = ["rc", "nightly"])
    @test length(specs) == 3
    @test specs[1].role == :baseline
    @test specs[2].selector == "rc"
    command = julia_runtime_command(specs[2]; project = pwd())
    @test command[1:2] == ["julia", "+rc"]
    @test "--startup-file=no" in command
    @test "--history-file=no" in command
    @test startswith(command[5], "--project=")
    @test julia_runtime_spec_dict(specs[3])["selector"] == "nightly"
    suite_command = julia_runtime_suite_command(specs[1]; suite = pathof(PerfChecker),
        reports = joinpath(pwd(), "runtime-results"),
        controller_project = pkgdir(PerfChecker))
    @test any(argument -> startswith(argument, "--suite="), suite_command)
    @test any(argument -> argument == "--profile=ci", suite_command)
    @test any(argument -> startswith(argument, "--perfchecker-project="), suite_command)
end
