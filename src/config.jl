const VERSION_SELECTORS = (:patches, :breaking, :major, :minor, :custom)
const CHECK_PREFERENCE_KEYS = (:threads, :repeat, :quiet)

"Validate the shared scalar settings identically for explicit options and preferences."
function _validate_check_settings(options)
    if haskey(options, :threads)
        threads = options[:threads]
        threads isa Integer && !(threads isa Bool) && 0 < threads <= typemax(Int) ||
            throw(ArgumentError(":threads must be a positive integer representable as Int"))
    end
    for key in (:repeat, :quiet)
        haskey(options, key) && !(options[key] isa Bool) &&
            throw(ArgumentError("$key must be Bool"))
    end
    return options
end

"""
    check_preferences() -> Dict{Symbol,Any}

Read PerfChecker's persistent `threads`, `repeat` and `quiet` defaults through
Preferences.jl in the current Julia environment stack. Return only settings
that have a preference, as an independent dictionary; this does not write files
or start workers. Malformed settings raise `ArgumentError`.

Checks read these settings at runtime, below explicit `Dict`/`PerfConfig` options
and suite feature, variant and run overrides. A suite freezes them before its
first worker is prepared. They are not compile-time switches, so changing them
does not require restarting Julia. Preferences belong to the controller's active
environment stack, not the workload directory in `PerfConfig.path`.

`repeat` controls the optional warmup used by allocation, profile and network
collectors; BenchmarkTools and Chairmarks use their own sampling controls and
do not use `repeat`. `quiet` suppresses PerfChecker's package-management logs,
not arbitrary output printed by the workload.
"""
function check_preferences()
    options = Dict{Symbol, Any}()
    for key in CHECK_PREFERENCE_KEYS
        value = Preferences.load_preference(@__MODULE__, "check_" * String(key),
            nothing; force_compiletime_default = true)
        value === nothing || (options[key] = value)
    end
    return _validate_check_settings(options)
end

"""
    set_check_preferences!(; export_prefs=false, kwargs...)

Persist any supplied check defaults in the active Julia project using
Preferences.jl and return [`check_preferences`](@ref). `threads` must be a
positive `Int`-representable integer other than `Bool`; `repeat` and `quiet`
must be `Bool`. Unknown keys and invalid values are rejected before writing.
Unspecified settings are preserved. No workload path, command or credential is
accepted by this API.

The default writes `LocalPreferences.toml`; `export_prefs=true` explicitly writes
shareable preferences into `Project.toml`. Julia's environment-stack inheritance
still applies, and local preferences override exported preferences. Existing
explicit check options win over these defaults. Changes affect future checks,
not a running suite's frozen settings. No restart is required.

```julia
set_check_preferences!(threads=2, quiet=true)
config = PerfConfig(:profile; path=pwd(), threads=1) # explicit value wins
```

Use [`reset_check_preferences!`](@ref) to remove selected settings or block their
inheritance. Other packages' preferences are not changed.
"""
function set_check_preferences!(; export_prefs::Bool = false, kwargs...)
    options = Dict{Symbol, Any}(kwargs)
    all(key -> key in CHECK_PREFERENCE_KEYS, keys(options)) ||
        throw(ArgumentError("check preferences accept only threads, repeat and quiet"))
    _validate_check_settings(options)
    isempty(options) || Preferences.set_preferences!(@__MODULE__,
        ("check_" * String(key) => value for (key, value) in options)...;
        export_prefs, force = true)
    return check_preferences()
end

"""
    reset_check_preferences!(keys::Symbol...; block_inheritance=false,
                             export_prefs=false)

Delete selected persistent check defaults from the active project and return
[`check_preferences`](@ref). With no keys, reset `threads`, `repeat` and `quiet`.
Unknown keys raise `ArgumentError` before writing. Other preference keys and
other packages' settings are preserved.

By default, delete local settings and allow defaults inherited from other Julia
environments or `Project.toml` to become visible. `block_inheritance=true` instead
uses Preferences.jl's clear markers to block inherited values at the selected
storage level. `export_prefs=true` selects `Project.toml`; otherwise select
`LocalPreferences.toml`. Resetting one level does not delete values at the other.

```julia
reset_check_preferences!(:threads) # inherit a shared value, if any
reset_check_preferences!(block_inheritance=true) # use collector defaults
```

This changes future checks only and does not require restarting Julia.
"""
function reset_check_preferences!(keys::Symbol...; block_inheritance::Bool = false,
        export_prefs::Bool = false)
    selected = isempty(keys) ? CHECK_PREFERENCE_KEYS : keys
    all(key -> key in CHECK_PREFERENCE_KEYS, selected) ||
        throw(ArgumentError("check preferences accept only threads, repeat and quiet"))
    Preferences.delete_preferences!(@__MODULE__,
        ("check_" * String(key) for key in selected)...;
        block_inheritance, export_prefs, force = true)
    return check_preferences()
end

"""
    PerfConfig(backend::Symbol; path=pwd(), kwargs...)
    PerfConfig(backend::Symbol, options)

Julia-native public configuration object for `@check`.

`PerfConfig` keeps the existing dictionary-based API available while giving
REPL, scripts, and Pluto notebooks a clearer object to pass around. Keyword
arguments are stored with symbolic keys and validated by `normalize_config`
just before a check runs. Explicit options override [`check_preferences`](@ref).
Construction does not read or write preferences or start a worker.

Example:

```julia
config = PerfConfig(:benchmark; path=pwd(), tags=[:local], samples=10)
result = @check config begin
    nothing
end begin
    sum(1:100)
end
```
"""
struct PerfConfig
    backend::Symbol
    options::Dict{Symbol, Any}

    function PerfConfig(backend::Symbol, options::Dict{Symbol, Any})
        return new(backend, copy(options))
    end
end

function PerfConfig(backend::Symbol; path = pwd(), kwargs...)
    options = Dict{Symbol, Any}(:path => path)
    for (key, value) in pairs(kwargs)
        options[Symbol(key)] = value
    end
    return PerfConfig(backend, options)
end

function PerfConfig(backend::Symbol, options::AbstractDict)
    normalized = Dict{Symbol, Any}()
    for (key, value) in pairs(options)
        key isa Symbol ||
            throw(ArgumentError("PerfConfig option keys must be Symbol values"))
        normalized[key] = value
    end
    return PerfConfig(backend, normalized)
end

"""
    to_dict(config::PerfConfig) -> Dict{Symbol, Any}

Return a copy of the public options stored in `config`.
"""
to_dict(config::PerfConfig) = copy(config.options)

Base.Dict(config::PerfConfig) = to_dict(config)

"""
    PackageVersionSpec(name, selector, versions, prefer_latest)
    PackageVersionSpec(pkgconf::Tuple)

Normalized representation of the `:pkgs` option accepted by `@check`.

The tuple form is `(name::String, selector::Symbol,
versions::Vector{VersionNumber}, prefer_latest::Bool)`. Supported selectors
are `:custom`, `:patches`, `:minor`, `:major`, and `:breaking`.
"""
struct PackageVersionSpec
    name::String
    selector::Symbol
    versions::Vector{VersionNumber}
    prefer_latest::Bool
end

"""
    RunTarget(spec, label, is_dev)

Internal description of one package target to run in an isolated worker.
Released versions use `is_dev == false`; local development targets created from
`:devops` use `is_dev == true`.
"""
struct RunTarget
    spec::PackageSpec
    label::String
    is_dev::Bool
end

"""
    RunMetadata

Structured metadata written next to cached performance outputs. It records the
backend, package version, tags, normalized config hash, result UUID, Julia
version, thread count, timestamp, and hardware identity used for cache lookup.
"""
struct RunMetadata
    backend::Symbol
    package::String
    version::String
    tags::Vector{Symbol}
    config_hash::String
    result_uuid::UUID
    julia_version::String
    threads::Int
    date::String
    hardware_id::String
end

"""
    CheckConfig

Validated internal configuration used by PerfChecker after merging backend
defaults with the public `Dict` passed to `@check`.

Users can keep passing dictionaries; `CheckConfig` exists to make required
fields and cache identity explicit before workers are launched.
`check_configuration` records the resolved shared defaults, their origins and
the effective configuration hash. It is copied into result qualification; the
origins themselves do not participate in cache identity.
"""
struct CheckConfig
    backend::Symbol
    options::Dict{Symbol, Any}
    path::String
    tags::Vector{Symbol}
    threads::Int
    track::String
    packages::Union{Nothing, PackageVersionSpec}
    devops::Any
    extra_pkgs::Any
    targets::Vector{String}
    repeat::Bool
    include_current::Bool
    config_hash::String
    check_configuration::Dict{String, Any}
end

function PackageVersionSpec(pkgconf::Tuple)
    length(pkgconf) == 4 ||
        throw(ArgumentError(":pkgs must be (name, selector, versions, prefer_latest)"))

    name, selector, versions, prefer_latest = pkgconf
    name isa AbstractString ||
        throw(ArgumentError(":pkgs first value must be a package name string"))
    selector isa Symbol ||
        throw(ArgumentError(":pkgs selector must be a Symbol"))
    selector in VERSION_SELECTORS ||
        throw(ArgumentError("unknown :pkgs selector $selector"))
    versions isa AbstractVector{VersionNumber} ||
        throw(ArgumentError(":pkgs versions must be a Vector{VersionNumber}"))
    prefer_latest isa Bool ||
        throw(ArgumentError(":pkgs prefer_latest must be Bool"))

    return PackageVersionSpec(String(name), selector, collect(versions), prefer_latest)
end

function normalize_symbols(value, key::Symbol; default = Symbol[])
    if value === nothing
        return collect(default)
    elseif value isa Symbol
        return [value]
    elseif value isa AbstractVector && all(x -> x isa Symbol, value)
        return Symbol.(value)
    else
        throw(ArgumentError("$key must be a Symbol or Vector{Symbol}"))
    end
end

function normalize_strings(value, key::Symbol; default = String[])
    if value === nothing
        return collect(default)
    elseif value isa AbstractString
        return [String(value)]
    elseif value isa AbstractVector && all(x -> x isa AbstractString, value)
        return String.(value)
    else
        throw(ArgumentError("$key must be a string or vector of strings"))
    end
end

"""
    normalize_config(backend::Symbol, config::Dict) -> CheckConfig

Merge backend defaults, runtime [`check_preferences`](@ref) and explicit user
options, validate shared PerfChecker options, and return a frozen `CheckConfig`.
Explicit options take precedence. Shared `threads`, `repeat` and `quiet` use the
same validation whether supplied explicitly or by Preferences.jl.

Required shared option:

- `:path`: environment directory copied for each worker.

Common optional options include `:tags`, `:threads`, `:track`, `:pkgs`,
`:devops`, `:extra_pkgs`, `:targets`, and `:repeat`.
"""
function normalize_config(backend::Symbol, config::Dict;
        preferences = check_preferences(), defaults = Dict{Symbol, Any}())
    _validate_check_settings(preferences)
    options = merge(Dict{Symbol, Any}(:threads => 1, :repeat => true, :quiet => false),
        default_options(Val(backend)), defaults, preferences, config)
    _validate_check_settings(options)
    options[:threads] = Int(options[:threads])
    check_configuration = Dict{String, Any}(
        "values" => Dict(String(key) => options[key] for key in CHECK_PREFERENCE_KEYS),
        "origins" => Dict(String(key) => haskey(config, key) ? "explicit" :
                                         haskey(preferences, key) ? "preferences" :
                                         "default"
        for key in CHECK_PREFERENCE_KEYS))

    haskey(options, :path) ||
        throw(ArgumentError("missing required :path option for @check $backend"))
    path = abspath(String(options[:path]))
    isdir(path) ||
        throw(ArgumentError(":path must point to an existing environment directory: $path"))

    tags = normalize_symbols(get(options, :tags, Symbol[:none]), :tags)
    threads = get(options, :threads, 1)
    track = String(get(options, :track, "none"))

    packages = haskey(options, :pkgs) ? PackageVersionSpec(options[:pkgs]) : nothing
    devops = get(options, :devops, nothing)
    extra_pkgs = get(options, :extra_pkgs, nothing)
    targets = normalize_strings(get(options, :targets, String[]), :targets)
    repeat = Bool(get(options, :repeat, true))
    include_current = Bool(get(options, :include_current, true))
    !include_current && packages === nothing && devops === nothing &&
        throw(ArgumentError(":include_current=false requires :pkgs or :devops"))
    option_pairs = sort!(
        [pair for pair in pairs(options)
         if first(pair) !== :prepared_environment];
        by = p -> string(first(p)))
    option_fingerprint = join(
        map(p -> string(first(p), "=", repr(last(p))), option_pairs), "|")
    # Profile caches from the earlier lexical source filter cannot certify the
    # new exact containment or allocation-evidence contract.
    backend in (:profile, :wall_profile, :profile_alloc) &&
        (option_fingerprint *= "|profile-source-contract=exact-containment-v1")
    config_hash = stable_uuid_string(
        join(string.([backend, path, tags, threads, track, option_fingerprint]), "|"))
    check_configuration["config_hash"] = config_hash

    return CheckConfig(
        backend, options, path, tags, Int(threads), track, packages, devops,
        extra_pkgs, targets, repeat, include_current, config_hash, check_configuration)
end

function normalize_config(config::PerfConfig; kwargs...)
    normalize_config(config.backend, to_dict(config); kwargs...)
end

normalize_config(config::CheckConfig) = config

function normalize_config(backend::Symbol, config::CheckConfig)
    backend == config.backend || throw(ArgumentError(
        "backend mismatch: requested $backend but CheckConfig uses $(config.backend)"))
    return config
end

function normalize_config(backend::Symbol, config::PerfConfig; kwargs...)
    backend == config.backend ||
        throw(ArgumentError(
            "backend mismatch: macro requested $backend but PerfConfig uses $(config.backend)"))
    return normalize_config(config; kwargs...)
end

function legacy_options(config::CheckConfig)
    options = copy(config.options)
    options[:path] = config.path
    options[:tags] = config.tags
    options[:threads] = config.threads
    options[:track] = config.track
    options[:targets] = config.targets
    options[:repeat] = config.repeat
    options[:include_current] = config.include_current
    config.packages === nothing ||
        (options[:pkgs] = (
            config.packages.name,
            config.packages.selector,
            config.packages.versions,
            config.packages.prefer_latest))
    config.devops === nothing || (options[:devops] = config.devops)
    config.extra_pkgs === nothing || (options[:extra_pkgs] = config.extra_pkgs)
    options[:config_hash] = config.config_hash
    return options
end

@testitem "Configuration contracts" tags=[:unit, :config] begin
    using PerfChecker

    cfg = PerfChecker.normalize_config(:benchmark,
        Dict(:path => @__DIR__, :tags => [:unit], :threads => 1))
    @test cfg.backend == :benchmark
    @test cfg.tags == [:unit]
    @test cfg.threads == 1
    @test cfg.path == abspath(@__DIR__)
    @test_throws ArgumentError PerfChecker.normalize_config(:benchmark, Dict())

    public_cfg = PerfConfig(:benchmark; path = @__DIR__, tags = [:ux], samples = 1)
    @test Dict(public_cfg)[:samples] == 1
    @test PerfChecker.normalize_config(public_cfg).backend == :benchmark
    @test_throws ArgumentError PerfChecker.normalize_config(:alloc, public_cfg)
    @test_throws ArgumentError PerfConfig(:benchmark, Dict("path" => @__DIR__))
    @test_throws ArgumentError PerfChecker.normalize_config(:benchmark,
        Dict(:path => @__DIR__, :include_current => false))
    prepared_cfg = PerfChecker.normalize_config(:benchmark,
        Dict(:path => @__DIR__, :tags => [:unit], :threads => 1,
            :prepared_environment => "internal-cache-path"))
    @test prepared_cfg.config_hash == cfg.config_hash
end
