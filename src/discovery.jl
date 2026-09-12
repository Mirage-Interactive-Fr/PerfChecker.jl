import JuliaSyntax
import YAML

const DISCOVERY_SCHEMA = "perfchecker-discovery/1"

function _discovery_files(root)
    paths = String[]
    for (directory, subdirs, files) in walkdir(root; follow_symlinks = false)
        filter!(
            name -> !(name in (
                ".git", ".lab", "node_modules", "results", "build", "compiled")) &&
                !islink(joinpath(directory, name)),
            subdirs)
        for file in files
            path = joinpath(directory, file)
            islink(path) && continue
            (endswith(file, ".jl") || file == "scenarios.toml" ||
             occursin(r"\.ya?ml$", file) && basename(directory) == "workflows") &&
                push!(paths, path)
        end
    end
    return sort!(paths)
end

function _discovery_warning(file, message; line = 0)
    Dict{String, Any}(
        "file" => file, "line" => line, "message" => message)
end

function _scan_test_file!(candidates, fixtures, warnings, path, root)
    text = read(path, String)
    tree = try
        JuliaSyntax.parseall(JuliaSyntax.SyntaxNode, text; filename = path)
    catch error
        push!(warnings, _discovery_warning(relpath(path, root), sprint(showerror, error)))
        return
    end
    ordinal = Ref(0)
    file_fixtures = String[]
    function visit(node, contexts)
        kind = JuliaSyntax.kind(node)
        # Only macros, calls and string literals need their source. Copying every
        # subtree repeatedly makes discovery allocate with syntax nesting depth.
        source = kind in (
            JuliaSyntax.K"macrocall", JuliaSyntax.K"call", JuliaSyntax.K"string") ?
                 String(JuliaSyntax.sourcetext(node)) : ""
        line = kind in (JuliaSyntax.K"macrocall", JuliaSyntax.K"call") ?
               first(JuliaSyntax.source_location(node)) : 0
        if kind == JuliaSyntax.K"macrocall"
            macro_match = match(
                r"^(?:Test\.|TestItems\.)?@(testset|testitem|test|test_throws|check)\b",
                strip(source))
            if macro_match !== nothing
                name = macro_match.captures[1]
                if name in ("testset", "testitem")
                    label = match(r"@(?:testset|testitem)\s+\"([^\"]+)\"", source)
                    contexts = [contexts; label === nothing ? name : label.captures[1]]
                    if label === nothing
                        push!(warnings,
                            _discovery_warning(relpath(path, root),
                                "dynamic test label or parameterized test scope; expansion is not executed"; line))
                    end
                else
                    ordinal[] += 1
                    relative = replace(relpath(path, root), '\\' => '/')
                    id = "$relative/test-$(ordinal[])"
                    expression = strip(replace(
                        source, r"^(?:Test\.)?@(?:test|test_throws|check)\s*" => ""))
                    operation, oracle = expression, ""
                    equality = match(r"^(.+?)\s*(==|≈|≃)\s*(.+)$"s, expression)
                    if equality !== nothing
                        operation = strip(equality.captures[1])
                        oracle = expression
                    end
                    missing = ["preparation and reset", "result verification",
                        "repeatability and cleanup"]
                    name == "test_throws" && push!(
                        missing, "exception-path workload must be explicitly selected")
                    name == "check" &&
                        push!(missing, "freeze generated inputs before measurement")
                    push!(candidates,
                        Dict{String, Any}("id" => id, "status" => "proposed",
                            "origin" => Dict("file" => relative, "line" => line,
                                "test_context" => contexts), "operation_candidate" => operation,
                            "oracle_candidate" => oracle, "missing" => missing,
                            "fixtures" => file_fixtures,
                            "definition_sha256" => bytes2hex(SHA.sha256(source))))
                end
            elseif occursin(r"@(eval|generated)\b", source)
                push!(warnings,
                    _discovery_warning(relpath(path, root),
                        "generated code is not expanded during discovery"; line))
            end
        elseif kind == JuliaSyntax.K"call" &&
               occursin(r"^(?:Base\.)?include\s*\(", strip(source))
            literal = match(r"include\s*\(\s*\"([^\"\$]+)\"\s*\)", source)
            if literal === nothing
                push!(warnings,
                    _discovery_warning(relpath(path, root),
                        "dynamic include is not resolved"; line))
            end
        end
        # Record only literal local file references. Never read outside the requested root.
        if kind == JuliaSyntax.K"string" && !occursin('$', source)
            value = try
                Meta.parse(source)
            catch
                nothing
            end
            if value isa String
                candidate = normpath(joinpath(dirname(path), value))
                relative = relpath(candidate, root)
                if !startswith(relative, "..") && isfile(candidate) && !islink(candidate) &&
                   !startswith(relpath(realpath(candidate), realpath(root)), "..")
                    fixtures[replace(relative, '\\' => '/')] = _sha256_file(candidate)
                    push!(file_fixtures, replace(relative, '\\' => '/'))
                end
            end
        end
        for child in something(JuliaSyntax.children(node), ())
            visit(child, contexts)
        end
    end
    visit(tree, String[])
end

function _scan_ci(path, root, warnings)
    data = try
        YAML.load_file(path)
    catch error
        push!(warnings, _discovery_warning(relpath(path, root), sprint(showerror, error)))
        return Dict{String, Any}[]
    end
    data isa AbstractDict || return Dict{String, Any}[]
    configurations = Dict{String, Any}[]
    for (name, job) in get(data, "jobs", Dict())
        job isa AbstractDict || continue
        if haskey(job, "uses")
            push!(warnings,
                _discovery_warning(relpath(path, root),
                    "reusable workflow for job $name is not resolved"))
        end
        strategy = get(job, "strategy", Dict())
        matrix = strategy isa AbstractDict ? get(strategy, "matrix", Dict()) : Dict()
        if !(matrix isa AbstractDict) || occursin(r"\$\{\{", string(matrix))
            push!(warnings,
                _discovery_warning(
                    relpath(path, root), "dynamic matrix for job $name is not evaluated"))
            continue
        end
        rows = Dict{String, Any}[Dict()]
        for axis in sort!(String.(filter(
            k -> !(k in ("include", "exclude")), collect(keys(matrix)))))
            values = matrix[axis]
            if !(values isa AbstractVector)
                push!(warnings,
                    _discovery_warning(
                        relpath(path, root), "unsupported matrix axis $axis in $name"))
                empty!(rows)
                break
            end
            if length(rows) * length(values) > 256
                push!(warnings,
                    _discovery_warning(
                        relpath(path, root), "matrix $name exceeds 256 configurations"))
                empty!(rows)
                break
            end
            rows = [merge(row, Dict(axis => value)) for row in rows for value in values]
        end
        original = deepcopy(rows)
        for exclusion in get(matrix, "exclude", Any[])
            exclusion isa AbstractDict || continue
            filter!(row -> !all(get(row, string(k), nothing) == v for (k, v) in exclusion),
                rows)
        end
        for inclusion in get(matrix, "include", Any[])
            inclusion isa AbstractDict || continue
            included = Dict{String, Any}(string(k) => v for (k, v) in inclusion)
            compatible = findall(
                row -> all(!haskey(row, k) || row[k] == v for (k, v) in included), original)
            matched = false
            for row in rows
                if any(base -> all(get(row, k, nothing) == v for (k, v) in base),
                    original[compatible])
                    merge!(row, included)
                    matched = true
                end
            end
            matched || push!(rows, included)
        end
        push!(configurations,
            Dict("file" => replace(relpath(path, root), '\\' => '/'),
                "job" => string(name), "runner" => get(job, "runs-on", "unresolved"),
                "configurations" => rows, "status" => "candidate_environments"))
    end
    return configurations
end

"Discover test-derived proposals and explicit catalogs without executing target code or CI commands."
function discover(root::AbstractString = pwd(); previous = nothing)
    root = abspath(root)
    isdir(root) || throw(ArgumentError("discovery root does not exist"))
    candidates, active, warnings, ci = (Dict{String, Any}[] for _ in 1:4)
    fixtures = Dict{String, Any}()
    fingerprints = Dict{String, Any}()
    for path in _discovery_files(root)
        relative = replace(relpath(path, root), '\\' => '/')
        fingerprints[relative] = _sha256_file(path)
        if basename(path) == "scenarios.toml"
            try
                catalog = load_scenario_catalog(path)
                for spec in catalog.scenarios
                    references = [spec.source; spec.fixtures]
                    if any(p -> startswith(relpath(realpath(p), realpath(root)), ".."),
                        references)
                        push!(warnings,
                            _discovery_warning(relative,
                                "catalog references outside the discovery root are not inspected"))
                        continue
                    end
                    push!(active,
                        merge(_scenario_dict(spec),
                            Dict("status" => "declared",
                                "catalog" => relative, "input_fingerprints" => _scenario_fingerprints(spec))))
                end
            catch error
                push!(warnings, _discovery_warning(relative, sprint(showerror, error)))
            end
        elseif endswith(path, ".jl")
            _scan_test_file!(candidates, fixtures, warnings, path, root)
        else
            append!(ci, _scan_ci(path, root, warnings))
        end
    end
    merge!(fingerprints, fixtures)
    corpora = Dict{String, Any}[]
    for declaration in active
        for (path, digest) in declaration["input_fingerprints"]
            fingerprints[replace(relpath(path, root), '\\' => '/')] = digest
            path in declaration["fixtures"] &&
                (fixtures[replace(relpath(path, root), '\\' => '/')] = digest)
        end
    end
    for relative in sort!(collect(keys(fixtures)))
        endswith(lowercase(relative), ".json") || continue
        path = joinpath(root, relative)
        if filesize(path) > 5_000_000
            push!(warnings,
                _discovery_warning(relative,
                    "large JSON fixture fingerprinted; corpus metadata not parsed"))
            continue
        end
        payload = try
            _json_parsefile(path)
        catch
            nothing
        end
        payload isa AbstractDict || continue
        get(payload, "schema_version", "") == "perfchecker-property-corpus/1" || continue
        valid = get(payload, "count", -1) == length(get(payload, "cases", Any[]))
        push!(corpora,
            Dict("file" => relative, "sha256" => fixtures[relative],
                "count" => get(payload, "count", -1), "status" => valid ? "frozen" :
                                                                  "invalid"))
        valid || push!(warnings,
            _discovery_warning(relative, "frozen corpus count does not match its cases"))
    end
    changes = Dict{String, Any}[]
    if previous !== nothing
        previous = previous isa AbstractString ? _json_parsefile(previous) : previous
        get(previous, "schema_version", "") == DISCOVERY_SCHEMA ||
            throw(ArgumentError("unsupported discovery baseline"))
        old = get(previous, "fingerprints", Dict())
        for path in sort!(collect(union(keys(old), keys(fingerprints))))
            get(old, path, nothing) == get(fingerprints, path, nothing) && continue
            push!(changes,
                Dict("file" => path,
                    "status" => !haskey(old, path) ? "added" :
                                !haskey(fingerprints, path) ? "removed" : "changed",
                    "affected_candidates" => unique([c["id"]
                                                     for c in vcat(
                                                             get(previous,
                                                                 "candidates", Any[]),
                                                             candidates)
                                                     if c["origin"]["file"] == path ||
                        path in get(c, "fixtures", String[])]),
                    "affected_declared" => unique([d["id"] * "/" * d["implementation"]
                                                   for d in vcat(
                                                           get(previous,
                                                               "declared", Any[]),
                                                           active)
                                                   if any(
                        p -> replace(relpath(p, root), '\\' => '/') == path,
                        keys(d["input_fingerprints"]))])))
        end
    end
    return Dict{String, Any}("schema_version" => DISCOVERY_SCHEMA, "root" => root,
        "declared" => active, "candidates" => candidates, "fixtures" => fixtures, "corpora" => corpora,
        "ci" => ci, "warnings" => warnings, "fingerprints" => fingerprints, "changes" => changes,
        "analyzers" => diagnostic_capabilities())
end
