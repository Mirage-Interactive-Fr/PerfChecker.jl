const DEFAULT_TEMPLATE_KINDS = (:benchmark, :chairmark, :alloc, :pluto)
const TEMPLATE_KINDS = (:benchmark, :chairmark, :alloc, :pluto)

function _template_filename(kind::Symbol)
    kind === :benchmark && return "benchmark.jl"
    kind === :chairmark && return "chairmark.jl"
    kind === :alloc && return "alloc.jl"
    kind === :pluto && return "dashboard.jl"
    throw(ArgumentError("unknown template kind $kind; expected one of $(TEMPLATE_KINDS)"))
end

function _template_body(kind::Symbol)
    kind === :benchmark && return """
using PerfChecker
using BenchmarkTools

config = PerfConfig(:benchmark;
    path = dirname(@__DIR__),
    tags = [:local],
    samples = 10,
    evals = 1,
)

result = @check config begin
    nothing
end begin
    sum(1:1_000)
end

summary_table(result)
"""

    kind === :chairmark && return """
using PerfChecker
using Chairmarks

config = PerfConfig(:chairmark;
    path = dirname(@__DIR__),
    tags = [:local],
)

result = @check config begin
    nothing
end begin
    sum(1:1_000)
end

summary_table(result)
"""

    kind === :alloc && return """
using PerfChecker

config = PerfConfig(:alloc;
    path = dirname(@__DIR__),
    tags = [:local],
    track = "user",
)

result = @check config begin
    nothing
end begin
    sum(1:1_000)
end

summary_table(result)
"""

    kind === :pluto && return """
### A Pluto.jl notebook ###
# v1.0.0

# This dashboard intentionally uses the surrounding Julia project instead of
# embedding a notebook-specific package environment.

# ╔═╡ 2d1f2ad8-b86a-4a14-a4a1-7656b3797f58
begin
    import Pkg
    project_path = dirname(@__DIR__)
    Pkg.activate(project_path)
    Pkg.instantiate()

    using PerfChecker
end

# ╔═╡ 31f575d1-d1f2-4ac3-a492-4e91f22f3385
run_check = false

# ╔═╡ 102521ea-6249-46c4-810d-2f4cb2cbd7f4
config = PerfConfig(:benchmark;
    path = project_path,
    tags = [:pluto],
    samples = 10,
    evals = 1,
)

# ╔═╡ 19898c08-010b-419a-b6aa-00e1e6c1cf51
result = if run_check
    @check config begin
        nothing
    end begin
        sum(1:1_000)
    end
else
    nothing
end

# ╔═╡ fddfef1d-8d73-4e28-a975-405dcf70a293
summary = result === nothing ? nothing : summary_table(result)

# ╔═╡ Cell order:
# ╠═2d1f2ad8-b86a-4a14-a4a1-7656b3797f58
# ╠═31f575d1-d1f2-4ac3-a492-4e91f22f3385
# ╠═102521ea-6249-46c4-810d-2f4cb2cbd7f4
# ╠═19898c08-010b-419a-b6aa-00e1e6c1cf51
# ╠═fddfef1d-8d73-4e28-a975-405dcf70a293
"""

    throw(ArgumentError("unknown template kind $kind; expected one of $(TEMPLATE_KINDS)"))
end

"""
    write_template(kind::Symbol; path=nothing, force=false) -> String

Write a Julia performance-checking template and return its path.

Supported template kinds are `:benchmark`, `:chairmark`, `:alloc`, and
`:pluto`. The generated files use `PerfConfig`; no external configuration file
format is introduced.
"""
function write_template(kind::Symbol; path = nothing, force::Bool = false)
    kind in TEMPLATE_KINDS ||
        throw(ArgumentError("unknown template kind $kind; expected one of $(TEMPLATE_KINDS)"))
    target = path === nothing ? joinpath("perf", _template_filename(kind)) : String(path)
    if isfile(target) && !force
        throw(ArgumentError("$target already exists; pass force=true to overwrite it"))
    end
    dir = dirname(target)
    isempty(dir) || mkpath(dir)
    open(target, "w") do io
        write(io, _template_body(kind))
    end
    return target
end

"""
    perf_setup(; dir="perf", kinds=(:benchmark, :chairmark, :alloc, :pluto), force=false)

Create a small Julia-native performance workspace.

This writes benchmark, chairmark, allocation, and Pluto dashboard starter files
by default. It intentionally does not create a `Perf.toml`; options stay in
Julia code through `PerfConfig`. The Pluto dashboard activates the surrounding
Julia project so it can be used as a controlled project-local view over stored
or newly run checks.
"""
function perf_setup(; dir = "perf", kinds = DEFAULT_TEMPLATE_KINDS, force::Bool = false)
    mkpath(dir)
    return [write_template(kind; path = joinpath(dir, _template_filename(kind)), force)
            for kind in kinds]
end

"Create an immediately runnable feature-oriented suite for the current package."
function write_software_suite_template(root::AbstractString = pwd();
        force::Bool = false)
    package_root = abspath(String(root))
    project_path = joinpath(package_root, "Project.toml")
    isfile(project_path) || throw(ArgumentError(
        "a package Project.toml is required at $project_path"))
    project = TOML.parsefile(project_path)
    package = String(get(project, "name", ""))
    isempty(package) && throw(ArgumentError("Project.toml has no package name"))
    suite_id = lowercase(replace(package, r"[^A-Za-z0-9]+" => "_"))
    perf_root = joinpath(package_root, "perf")
    feature_path = joinpath(perf_root, "features", "smoke.jl")
    suite_path = joinpath(perf_root, "suite.jl")
    runner_path = joinpath(perf_root, "runner", "Project.toml")
    targets = (feature_path, suite_path, runner_path)
    !force && any(isfile, targets) &&
        throw(ArgumentError(
            "a generated suite file already exists; pass force=true to replace it"))
    mkpath(dirname(feature_path))
    mkpath(dirname(runner_path))
    write(feature_path, """
using $package

perf_setup() = $package
perf_workload(package_module) = nameof(package_module)
perf_oracle(package_module) = nameof(package_module) == :$package
""")
    write(runner_path, """
name = "$(package)PerfRunner"
uuid = "$(uuid4())"
version = "0.1.0"

[deps]
BenchmarkTools = "6e4b80f9-dd63-53aa-95a3-0cdb28fa8baf"

[compat]
BenchmarkTools = "1"
julia = "1.10"
""")
    write(suite_path, """
using PerfChecker

function build_suite()
    package_root = normpath(joinpath(@__DIR__, ".."))
    smoke = FeatureSpec(:smoke;
        description = "Package load smoke measurement; replace with a feature workload",
        backend = :benchmark,
        entrypoint = joinpath(@__DIR__, "features", "smoke.jl"),
        oracle = OracleSpec(),
        options = Dict(:samples => 10, :evals => 1),
    )
    package = PackageSuite("$package";
        source = package_root,
        worker_environment = joinpath(@__DIR__, "runner"),
        versions = :all,
        include_dev = true,
        features = [smoke],
    )
    return SoftwareSuite(:$suite_id, [package];
        description = "$package performance surface")
end
""")
    return String[suite_path, feature_path, runner_path]
end

"""
    write_suite_notebook(path; suite_path=nothing, factory=:build_suite,
        profile=:quick, project=dirname(Base.active_project()),
        result_path="results/suite-result.json", reports_root="results/notebook",
        force=false)

Load `PerfCheckerPluto` and generate an editable Pluto notebook. It selects a
package, workload, collector and target, with explicit Launch, Cancel, Refresh
and Save controls. Generation does not start Pluto or execute a workload.
Without `suite_path`, the notebook only displays an existing saved result.

`project` must be a prepared controller environment containing PerfChecker,
PlutoUI and the selected collectors. Relative report paths resolve beside the
notebook; relative suite and project paths resolve from the caller's directory.
Create parent directories and return the absolute notebook path. Reject an
existing destination unless `force=true` explicitly permits replacement.
"""
function write_suite_notebook end
