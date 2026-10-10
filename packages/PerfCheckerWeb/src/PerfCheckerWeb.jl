"""
Oxygen interfaces for PerfChecker: evidence routes, Studio and native test items.
Load this package explicitly and use the exported PerfChecker entry points.
Starting a server requires `serve_suite` or an explicit Oxygen server call;
importing the package alone does not listen on a port.
"""
module PerfCheckerWeb

using Dates
using HTTP
using JSON
using Oxygen
using PerfChecker
using TestItemRunner
export serve_suite, register_oxygen_routes!, register_testitem_routes!,
       studio_token_authenticator, run_studio_agent
import TestItems: @testitem
using TOML

include("studio.jl")
include("advisor_setup.jl")
include("investigations.jl")
include("testitems.jl")

"""
    register_oxygen_routes!(provider::Function; prefix="/perfchecker/v1")

Register read-only capabilities, suite and run-list routes on Oxygen's current
router and return the router. Each request to `/suite` or `/runs` calls `provider()`
and serializes its suite result. Registration does not call the provider or start
an HTTP listener; any effects of the provider are the caller's responsibility.
Load `PerfCheckerWeb` before calling this method.
"""
function PerfChecker.register_oxygen_routes!(provider::Function;
        prefix::AbstractString = "/perfchecker/v1")
    api = Oxygen.router(String(prefix); tags = ["PerfChecker"])
    Oxygen.get(api("/capabilities")) do
        Oxygen.json(Dict(
            "schema_version" => "perfchecker-capabilities/1",
            "read_only" => true,
            "resources" => ["suite", "runs"]))
    end
    Oxygen.get(api("/suite")) do
        Oxygen.json(PerfChecker.suite_dict(provider()))
    end
    Oxygen.get(api("/runs")) do
        Oxygen.json(PerfChecker.suite_dict(provider())["runs"])
    end
    return api
end

"""
    register_oxygen_routes!(result::SoftwareSuiteResult; prefix="/perfchecker/v1")

Register a fixed suite result through the provider overload and return its Oxygen
router. Requests serialize the saved result without rerunning its measurements.
This method does not start a server.
"""
function PerfChecker.register_oxygen_routes!(result::PerfChecker.SoftwareSuiteResult;
        kwargs...)
    return PerfChecker.register_oxygen_routes!(() -> result; kwargs...)
end

"""
    register_oxygen_routes!(bundle::RunBundle; prefix="/perfchecker/v1")

Register read-only routes for a saved bundle and return the Oxygen router.
Routes expose its manifest, measurement definitions, observations, diagnostics,
artifacts and derived advice, comparisons, plots and queries. They do not rerun
the measured workload. Registration does not start an HTTP listener.
"""
function PerfChecker.register_oxygen_routes!(bundle::PerfChecker.RunBundle;
        prefix::AbstractString = "/perfchecker/v1")
    api = Oxygen.router(String(prefix); tags = ["PerfChecker bundles"])
    Oxygen.get(api("/capabilities")) do
        Oxygen.json(Dict(
            "schema_version" => "perfchecker-capabilities/1",
            "read_only" => true,
            "resources" => ["manifest", "measurement-definitions", "observations",
                "diagnostics", "artifacts", "version-comparison", "plots", "query",
                "agent-evidence"]))
    end
    Oxygen.get(api("/manifest")) do
        Oxygen.json(bundle.manifest)
    end
    Oxygen.get(api("/measurement-definitions")) do
        Oxygen.json(bundle.measurement_definitions)
    end
    Oxygen.get(api("/observations")) do
        Oxygen.json(bundle.observations)
    end
    Oxygen.get(api("/diagnostics")) do
        Oxygen.json(bundle.diagnostics)
    end
    Oxygen.get(api("/advice")) do
        Oxygen.json(PerfChecker.advise(bundle))
    end
    Oxygen.get(api("/artifacts")) do
        Oxygen.json(bundle.artifacts)
    end
    Oxygen.get(api("/version-comparison")) do
        Oxygen.json(PerfChecker.version_comparison_dict(
            PerfChecker.compare_suite_versions(bundle)))
    end
    Oxygen.get(api("/plots")) do
        Oxygen.json(Dict("schema_version" => "perfchecker-plot-catalog/1",
            "run_id" => bundle.manifest["run_id"],
            "plots" => PerfChecker.plot_catalog(bundle)))
    end
    Oxygen.get(api("/plot-data")) do request
        params = Oxygen.queryparams(request)
        version = get(params, "version", "")
        top = try
            parse(Int, get(params, "top", "40"))
        catch
            40
        end
        try
            plot = PerfChecker.performance_plot(bundle, get(params, "plot", "");
                version = isempty(version) ? nothing : version, top = clamp(top, 1, 200))
            Oxygen.json(PerfChecker.performance_plot_dict(plot))
        catch error
            Oxygen.json(
                Dict("error" => first(sprint(showerror, error), 1_000)); status = 400)
        end
    end
    Oxygen.get(api("/plot")) do request
        params = Oxygen.queryparams(request)
        version = get(params, "version", "")
        top = try
            parse(Int, get(params, "top", "40"))
        catch
            40
        end
        try
            plot = PerfChecker.performance_plot(bundle, get(params, "plot", "");
                version = isempty(version) ? nothing : version, top = clamp(top, 1, 200))
            applicable(PerfChecker.performance_plot_html, plot) || return Oxygen.json(
                Dict("error" => "WGLMakie is not loaded in this controller"); status = 501)
            Oxygen.html(PerfChecker.performance_plot_html(plot);
                headers = ["Cache-Control" => "private, max-age=60",
                    "X-Content-Type-Options" => "nosniff"])
        catch error
            Oxygen.json(Dict("error" => first(sprint(showerror, error), 1_000));
                status = 400)
        end
    end
    _register_query_routes!(api, request -> bundle)
    return api
end

function _query_request_payload(request; max_bytes::Integer = 65_536)
    length(request.body) <= max_bytes || throw(ArgumentError(
        "query body exceeds $(max_bytes) bytes"))
    payload = PerfChecker._json_parse(String(request.body))
    payload isa AbstractDict || throw(ArgumentError("query body must be a JSON object"))
    return payload
end

function _bounded_query(payload; max_records::Integer = 5_000)
    query = PerfChecker.performance_query(payload)
    limit = query.limit == 0 ? Int(max_records) : min(query.limit, Int(max_records))
    return PerfChecker.PerformanceQuery(; id = query.id, resources = query.resources,
        predicates = query.predicates, order_by = query.order_by, limit)
end

function _register_query_routes!(api, bundle_provider)
    Oxygen.post(api("/query")) do request
        try
            payload = _query_request_payload(request)
            bundle = bundle_provider(request)
            bundle === nothing && return Oxygen.json(Dict("error" => "unknown run");
                status = 404)
            query_payload = get(payload, "query", payload)
            return Oxygen.json(PerfChecker.query_bundle(bundle,
                _bounded_query(query_payload)))
        catch error
            return Oxygen.json(Dict("error" => first(sprint(showerror, error), 1_000));
                status = 400)
        end
    end
    Oxygen.post(api("/agent-evidence")) do request
        try
            payload = _query_request_payload(request)
            bundle = bundle_provider(request)
            bundle === nothing && return Oxygen.json(Dict("error" => "unknown run");
                status = 404)
            query_payload = get(payload, "query", payload)
            return Oxygen.json(PerfChecker.agent_evidence(bundle,
                _bounded_query(query_payload)))
        catch error
            return Oxygen.json(Dict("error" => first(sprint(showerror, error), 1_000));
                status = 400)
        end
    end
end

function _public_manifests(store::String)
    manifests = PerfChecker.list_run_bundles(store; recursive = true)
    return [Dict(key => value for (key, value) in pairs(manifest)
            if key != "bundle_path") for manifest in manifests],
    manifests
end

function _bundle_by_id(store::String, id::AbstractString)
    _, manifests = _public_manifests(store)
    index = findfirst(item -> get(item, "run_id", "") == id, manifests)
    index === nothing && return nothing
    return PerfChecker.read_run_bundle(manifests[index]["bundle_path"])
end

function _register_result_routes!(api, store::String)
    Oxygen.get(api("/advice")) do request
        bundle = _bundle_by_id(store, String(get(Oxygen.queryparams(request), "id", "")))
        bundle === nothing &&
            return Oxygen.json(Dict("error" => "unknown run"); status = 404)
        Oxygen.json(PerfChecker.advise(bundle))
    end
    handler = function (request)
        id = get(Oxygen.queryparams(request), "id", "")
        public, _ = _public_manifests(store)
        isempty(id) && return Oxygen.json(public)
        bundle = _bundle_by_id(store, id)
        bundle === nothing &&
            return Oxygen.json(Dict("error" => "unknown run"); status = 404)
        return Oxygen.json(PerfChecker.bundle_dict(bundle))
    end
    Oxygen.get(handler, api("/results"))
    Oxygen.get(handler, api("/runs"))
    Oxygen.get(api("/version-comparison")) do request
        id = get(Oxygen.queryparams(request), "id", "")
        bundle = _bundle_by_id(store, id)
        bundle === nothing &&
            return Oxygen.json(Dict("error" => "unknown run"); status = 404)
        return Oxygen.json(PerfChecker.version_comparison_dict(
            PerfChecker.compare_suite_versions(bundle)))
    end
    Oxygen.get(api("/plots")) do request
        id = get(Oxygen.queryparams(request), "id", "")
        bundle = _bundle_by_id(store, id)
        bundle === nothing &&
            return Oxygen.json(Dict("error" => "unknown run"); status = 404)
        return Oxygen.json(Dict("schema_version" => "perfchecker-plot-catalog/1",
            "run_id" => id, "plots" => PerfChecker.plot_catalog(bundle)))
    end
    Oxygen.get(api("/plot-data")) do request
        params = Oxygen.queryparams(request)
        bundle = _bundle_by_id(store, get(params, "id", ""))
        bundle === nothing &&
            return Oxygen.json(Dict("error" => "unknown run"); status = 404)
        plot_id = get(params, "plot", "")
        version = get(params, "version", "")
        top = try
            parse(Int, get(params, "top", "40"))
        catch
            40
        end
        try
            plot = PerfChecker.performance_plot(bundle, plot_id;
                version = isempty(version) ? nothing : version, top = clamp(top, 1, 200))
            return Oxygen.json(PerfChecker.performance_plot_dict(plot))
        catch error
            return Oxygen.json(Dict("error" => first(sprint(showerror, error), 1_000));
                status = 400)
        end
    end
    Oxygen.get(api("/plot")) do request
        params = Oxygen.queryparams(request)
        bundle = _bundle_by_id(store, get(params, "id", ""))
        bundle === nothing &&
            return Oxygen.json(Dict("error" => "unknown run"); status = 404)
        plot_id = get(params, "plot", "")
        version = get(params, "version", "")
        top = try
            parse(Int, get(params, "top", "40"))
        catch
            40
        end
        try
            plot = PerfChecker.performance_plot(bundle, plot_id;
                version = isempty(version) ? nothing : version, top = clamp(top, 1, 200))
            applicable(PerfChecker.performance_plot_html, plot) || return Oxygen.json(
                Dict("error" => "WGLMakie is not loaded in this controller"); status = 501)
            return Oxygen.html(PerfChecker.performance_plot_html(plot);
                headers = ["Cache-Control" => "private, max-age=60",
                    "X-Content-Type-Options" => "nosniff"])
        catch error
            return Oxygen.json(Dict("error" => first(sprint(showerror, error), 1_000));
                status = 400)
        end
    end
    _register_query_routes!(
        api, request -> begin
            payload = try
                PerfChecker._json_parse(String(request.body))
            catch
                Dict{String, Any}()
            end
            _bundle_by_id(store, String(get(payload, "id", "")))
        end)
end

"""
    register_oxygen_routes!(root::AbstractString; prefix="/perfchecker/v1",
                            allow_ingest=false, max_ingest_bytes=10*1024*1024)

Register a saved-bundle browser and evidence routes, and return the Oxygen router.
`root` is resolved from the working directory and must exist unless
`allow_ingest=true`, which creates it. Reading saved results does not rerun them.

With ingestion enabled, `POST /ingest` writes a supplied bundle under `root` and
returns HTTP 201. Invalid input returns 400; a body larger than the positive
`max_ingest_bytes` limit returns 413. These routes do not add authentication.
Registration starts no listener and cannot enforce its bind address; use the
loopback restriction in `serve_suite(root; allow_ingest=true)` when hosting them.
"""
function PerfChecker.register_oxygen_routes!(root::AbstractString;
        prefix::AbstractString = "/perfchecker/v1", allow_ingest::Bool = false,
        max_ingest_bytes::Integer = 10 * 1024 * 1024)
    max_ingest_bytes > 0 || throw(ArgumentError("max_ingest_bytes must be positive"))
    store = abspath(String(root))
    allow_ingest ? mkpath(store) :
    isdir(store) || throw(ArgumentError("bundle store does not exist: $store"))
    api = Oxygen.router(String(prefix); tags = ["PerfChecker bundle store"])
    _register_studio_assets!(api)
    Oxygen.get(api("/")) do
        _studio_response(String(prefix); writable = false)
    end
    Oxygen.get(api("/capabilities")) do
        Oxygen.json(Dict(
            "schema_version" => "perfchecker-capabilities/1",
            "read_only" => !allow_ingest,
            "resources" => allow_ingest ?
                           ["results", "version-comparison", "plots", "query",
                "agent-evidence", "ingest"] :
                           ["results", "version-comparison", "plots", "query",
                "agent-evidence"],
            "protocol" => "perfchecker-run-bundle/1"))
    end
    _register_result_routes!(api, store)
    if allow_ingest
        Oxygen.post(api("/ingest")) do request
            length(request.body) <= max_ingest_bytes || return Oxygen.json(
                Dict("error" => "ingest body exceeds $max_ingest_bytes bytes"); status = 413)
            try
                payload = PerfChecker._json_parse(String(request.body))
                payload isa AbstractDict || throw(ArgumentError(
                    "ingest body must be a JSON object"))
                bundle = PerfChecker._provider_result(payload)
                destination = joinpath(store, "run-$(bundle.manifest["run_id"])")
                PerfChecker.write_run_bundle(bundle, destination)
                return Oxygen.json(
                    PerfChecker.bundle_dict(bundle; include_records = false);
                    status = 201)
            catch error
                return Oxygen.json(
                    Dict("error" => first(sprint(showerror, error), 1_000)); status = 400)
            end
        end
    end
    return api
end

"""
    register_oxygen_routes!(suite::SoftwareSuite; profile=:quick,
        prefix="/perfchecker/v1", version_provider=get_pkg_versions,
        overrides=Dict{Symbol,Any}(), executor=PerfChecker._default_suite_executor,
        reports_root=joinpath(pwd(), "perfchecker-results"), max_concurrent=1,
        authenticator=nothing, authorizer=PerfCheckerWeb._default_studio_authorizer,
        lease_seconds=300, max_agent_attempts=3, session_hours=8, secure_cookies=false)

Register the interactive Studio, suite planning, job, saved-result and agent
routes, and return the Oxygen router. `reports_root` is made absolute and created;
persisted sessions, agents and compatible jobs are restored. Restored local jobs
can resume immediately, even though this function starts no HTTP listener.

`version_provider`, `overrides` and `executor` configure planning and execution;
`max_concurrent` limits active local jobs. `authenticator` maps a bearer token to
an identity or `nothing`; `authorizer` checks that identity's requested action.
`lease_seconds`, `max_agent_attempts`, `session_hours` and `secure_cookies` control
agent leases and browser sessions. These options belong to this suite overload,
not to the read-only bundle/provider routes. Use `serve_suite(suite; ...)` to
apply the hosted Studio's remote-control guard and start a listener.
"""
function PerfChecker.register_oxygen_routes!(suite::PerfChecker.SoftwareSuite;
        profile::Symbol = :quick, prefix::AbstractString = "/perfchecker/v1",
        version_provider = PerfChecker.get_pkg_versions,
        overrides::AbstractDict = Dict{Symbol, Any}(),
        executor = PerfChecker._default_suite_executor,
        reports_root::AbstractString = joinpath(pwd(), "perfchecker-results"),
        max_concurrent::Integer = 1, authenticator = nothing,
        authorizer = _default_studio_authorizer, lease_seconds::Integer = 300,
        max_agent_attempts::Integer = 3, session_hours::Integer = 8,
        secure_cookies::Bool = false)
    return _register_suite_workspace!(suite; profile, prefix = String(prefix),
        version_provider, overrides, executor,
        reports_root = abspath(String(reports_root)), max_concurrent = Int(max_concurrent),
        authenticator, authorizer, lease_seconds = Int(lease_seconds),
        max_agent_attempts = Int(max_agent_attempts), session_hours = Int(session_hours),
        secure_cookies)
end

"""
    serve_suite(provider::Function; host="127.0.0.1", port=8080, async=false,
                prefix="/perfchecker/v1", kwargs...)

Register a result provider's read-only routes, then return `Oxygen.serve`'s result.
`prefix` configures the routes; additional keywords go only to `Oxygen.serve`.
The default call serves on loopback and blocks according to Oxygen's server
lifetime; `async=true` requests Oxygen's asynchronous mode. This overload adds
neither authentication nor a remote-host restriction. Provider requests can have
the effects described by `register_oxygen_routes!(provider)`.
"""
function PerfChecker.serve_suite(provider::Function; host::AbstractString = "127.0.0.1",
        port::Integer = 8080, async::Bool = false,
        prefix::AbstractString = "/perfchecker/v1", kwargs...)
    PerfChecker.register_oxygen_routes!(provider; prefix)
    return Oxygen.serve(; host = String(host), port = Int(port), async, kwargs...)
end

"""
    serve_suite(result::SoftwareSuiteResult; host="127.0.0.1", port=8080,
                async=false, prefix="/perfchecker/v1", kwargs...)

Serve a fixed suite result through the provider overload and return Oxygen's
server result. Keywords follow that overload; serving does not remeasure the
result. Load `PerfCheckerWeb` to enable this method.
"""
function PerfChecker.serve_suite(result::PerfChecker.SoftwareSuiteResult; kwargs...)
    return PerfChecker.serve_suite(() -> result; kwargs...)
end

"""
    serve_suite(bundle::RunBundle; host="127.0.0.1", port=8080, async=false,
                prefix="/perfchecker/v1", kwargs...)

Register a saved bundle's read-only evidence routes, start Oxygen and return its
server result. `prefix` goes to route registration; other keywords go only to
`Oxygen.serve`. The default listener is loopback and `async=false`; this overload
does not enforce loopback or install authentication. It does not rerun the
bundle's measured workload.
"""
function PerfChecker.serve_suite(bundle::PerfChecker.RunBundle;
        host::AbstractString = "127.0.0.1", port::Integer = 8080,
        async::Bool = false, prefix::AbstractString = "/perfchecker/v1", kwargs...)
    PerfChecker.register_oxygen_routes!(bundle; prefix)
    return Oxygen.serve(; host = String(host), port = Int(port), async, kwargs...)
end

"""
    serve_suite(root::AbstractString; host="127.0.0.1", port=8080, async=false,
                prefix="/perfchecker/v1", allow_ingest=false, kwargs...)

Serve a saved-bundle directory and return Oxygen's server result. Ingestion is
off by default. `allow_ingest=true` permits writes and requires `host` to be
`127.0.0.1`, `localhost` or `::1`; a remote host raises `ArgumentError` before
registration. Read-only hosting adds no remote-host or authentication guard.

Additional keywords are forwarded to **both** directory route registration and
`Oxygen.serve`, so they must be accepted by both APIs. To configure route-only
or server-only options separately, call `register_oxygen_routes!(root; ...)`
followed by `Oxygen.serve(; ...)`, with an appropriate bind address.

```julia
using PerfChecker, PerfCheckerWeb
serve_suite("perf/results"; port=8080, async=true) # existing bundle directory
```
"""
function PerfChecker.serve_suite(root::AbstractString;
        host::AbstractString = "127.0.0.1", port::Integer = 8080,
        async::Bool = false, prefix::AbstractString = "/perfchecker/v1",
        allow_ingest::Bool = false, kwargs...)
    normalized_host = lowercase(String(host))
    loopback = normalized_host in ("127.0.0.1", "localhost", "::1")
    allow_ingest && !loopback &&
        throw(ArgumentError(
            "unauthenticated bundle ingestion is restricted to loopback"))
    PerfChecker.register_oxygen_routes!(root; prefix, allow_ingest, kwargs...)
    return Oxygen.serve(; host = String(host), port = Int(port), async, kwargs...)
end

"""
    serve_suite(suite::SoftwareSuite; host="127.0.0.1", port=8080, async=false,
                prefix="/perfchecker/v1", allow_remote_control=false,
                authenticator=nothing, kwargs...)

Register the interactive Studio and start Oxygen, returning its server result.
A non-loopback host requires **both** `allow_remote_control=true` and a supplied
`authenticator`; otherwise throw `ArgumentError` before registration. The caller
must also arrange suitable network exposure and transport security.

Additional keywords go only to `register_oxygen_routes!(suite; ...)`, including
its job, authorization and session options. Oxygen receives only `host`, `port`
and `async`. Registration creates/restores the workspace and can resume persisted
local jobs before the listener starts. The remote-control guard applies to this
overload, not to every form of `serve_suite`.
"""
function PerfChecker.serve_suite(suite::PerfChecker.SoftwareSuite;
        host::AbstractString = "127.0.0.1", port::Integer = 8080,
        async::Bool = false, prefix::AbstractString = "/perfchecker/v1",
        allow_remote_control::Bool = false, authenticator = nothing, kwargs...)
    normalized_host = lowercase(String(host))
    loopback = normalized_host in ("127.0.0.1", "localhost", "::1")
    loopback || (allow_remote_control && authenticator !== nothing) ||
        throw(ArgumentError(
            "remote performance control requires allow_remote_control=true and an authenticator"))
    PerfChecker.register_oxygen_routes!(suite; prefix, authenticator, kwargs...)
    return Oxygen.serve(; host = String(host), port = Int(port), async)
end

@testitem "Oxygen latest protocol stack" tags=[:oxygen_latest, :oxygen, :http2, :json] begin
    using HTTP
    using Oxygen, PerfCheckerWeb
    using PerfChecker
    using WGLMakie

    bundle = PerfChecker.RunBundle(
        Dict{String, Any}(
            "schema_version" => PerfChecker.RUN_BUNDLE_SCHEMA,
            "run_id" => "oxygen-latest", "suite" => "oxygen-latest",
            "state" => "complete"),
        [Dict{String, Any}(
            "id" => "julia.wall.time/oxygen-latest-v1",
            "metric" => "julia.wall.time", "unit" => "s")],
        [Dict{String, Any}(
            "metric" => "julia.wall.time", "case_id" => "oxygen/smoke",
            "target_id" => "dev", "version" => "dev", "value" => 1.0,
            "unit" => "s",
            "measurement_definition" => "julia.wall.time/oxygen-latest-v1",
            "comparison_key" => "oxygen/smoke::julia.wall.time/oxygen-latest-v1",
            "attributes" => Dict("package" => "PerfChecker",
                "feature" => "oxygen-smoke", "version" => "dev",
                "target_kind" => "dev"))],
        Dict{String, Any}[], Dict{String, Any}[])

    Oxygen.resetstate()
    register_oxygen_routes!(bundle; prefix = "/test/perfchecker/oxygen-latest")
    response = Oxygen.internalrequest(
        HTTP.Request("GET", "/test/perfchecker/oxygen-latest/manifest"))
    @test response.status == 200
    @test PerfChecker._json_parse(String(response.body))["run_id"] == "oxygen-latest"

    query = Oxygen.internalrequest(HTTP.Request("POST",
        "/test/perfchecker/oxygen-latest/query",
        ["Content-Type" => "application/json"],
        """{"resources":["observations"],"limit":1}"""))
    @test query.status == 200
    parsed = PerfChecker._json_parse(String(query.body))
    @test parsed["schema_version"] == "perfchecker-query-result/1"
    @test length(parsed["observations"]) == 1

    plots_response = Oxygen.internalrequest(
        HTTP.Request("GET", "/test/perfchecker/oxygen-latest/plots"))
    plot_id = first(PerfChecker._json_parse(String(plots_response.body))["plots"])["id"]
    plot_response = Oxygen.internalrequest(HTTP.Request("GET",
        "/test/perfchecker/oxygen-latest/plot?plot=$plot_id"))
    @test plot_response.status == 200
    @test occursin("canvas", lowercase(String(plot_response.body)))
    Oxygen.resetstate()
end

end
