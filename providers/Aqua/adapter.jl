import Aqua

function _analyze_scenario(::Val{:aqua}, case, options)
    name = get(options, "package", "")
    occursin(r"^[A-Za-z][A-Za-z_0-9]*$", name) ||
        return Dict(
            "status" => "unavailable", "message" => "a named package is required for Aqua")
    owner = Module(gensym(:AquaTarget))
    Base.eval(owner, Expr(:import, Expr(:., Symbol(name))))
    target = getfield(owner, Symbol(name))
    checks = get(options, "aqua", Dict())
    supported = Set(["ambiguities", "unbound_args", "undefined_exports", "project_extras",
        "stale_deps", "deps_compat", "piracies", "persistent_tasks"])
    all(k -> k in supported && checks[k] isa Bool, keys(checks)) ||
        throw(ArgumentError("Aqua overrides must be documented boolean checks"))
    keywords = (Symbol(k) => v for (k, v) in checks)
    try
        Base.invokelatest(Aqua.test_all, target; keywords...)
        return Dict{String, Any}("status" => "complete", "quality" => "passed",
            "checks" => checks, "defaults" => "Aqua.test_all for recorded tool version")
    catch error
        # An infrastructure or API error does not establish a package quality failure.
        nameof(typeof(error)) == :TestSetException || rethrow()
        return Dict{String, Any}("status" => "complete", "quality" => "failed",
            "checks" => checks, "findings" => [_analyzer_finding(
                "quality.aqua", sprint(showerror, error))])
    end
end
