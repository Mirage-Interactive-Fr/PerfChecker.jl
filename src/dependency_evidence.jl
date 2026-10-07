const DEPENDENCY_EVIDENCE_SCHEMA = "perfchecker-dependency-evidence/1"

"""
    NativeDependencyEvidence(phase, packages, artifact_files, loaded_libraries, warnings)

Group a named capture phase with resolved package records, declared artifact
binding files, observed current-process libraries and warnings. Use
[`dependency_evidence`](@ref) to collect it and
[`dependency_evidence_dict`](@ref) for transport. Declared artifacts and loaded
libraries are distinct evidence; this type does not assert that every declared
artifact was installed or loaded, nor cover child processes or services.
"""
struct NativeDependencyEvidence
    phase::String
    packages::Vector{Dict{String, Any}}
    artifact_files::Vector{Dict{String, Any}}
    loaded_libraries::Vector{Dict{String, Any}}
    warnings::Vector{String}
end

function _property(info, name::Symbol, default = nothing)
    return hasproperty(info, name) ? getproperty(info, name) : default
end

function _dependency_package_record(uuid, info)
    path = _property(info, :source, _property(info, :path, nothing))
    path = path === nothing ? nothing : String(path)
    artifact_path = path === nothing ? nothing : joinpath(path, "Artifacts.toml")
    return Dict{String, Any}(
        "kind" => endswith(String(_property(info, :name, "")), "_jll") ?
                  "jll_wrapper" : "julia_package",
        "state" => "resolved",
        "uuid" => string(uuid),
        "name" => String(_property(info, :name, "unknown")),
        "version" => string(_property(info, :version, "unknown")),
        "tree_hash" => string(_property(info, :tree_hash, "unknown")),
        "is_direct_dependency" => Bool(_property(info, :is_direct_dep, false)),
        "is_tracking_path" => Bool(_property(info, :is_tracking_path, false)),
        "is_tracking_repo" => Bool(_property(info, :is_tracking_repo, false)),
        "source_path" => path,
        "artifacts_file" => artifact_path !== nothing && isfile(artifact_path) ?
                            artifact_path : nothing)
end

"""
    package_dependency_inventory()

Return `(records, warnings)` from the active environment's `Pkg.dependencies()`.
Records are sorted by package name and UUID and retain version/tree identity,
tracking origin, source path, direct-dependency status and an existing
`Artifacts.toml` path. JLL wrappers are labelled separately from Julia packages.
If Pkg inventory fails, return an empty collection and a bounded error warning.
No package is loaded, installed or resolved by this function.
"""
function package_dependency_inventory()
    records = Dict{String, Any}[]
    warnings = String[]
    dependencies = try
        Pkg.dependencies()
    catch error
        push!(warnings,
            "Pkg dependency inventory unavailable: " *
            first(sprint(showerror, error), 500))
        Dict()
    end
    for (uuid, info) in dependencies
        push!(records, _dependency_package_record(uuid, info))
    end
    sort!(records; by = record -> (String(record["name"]), String(record["uuid"])))
    return records, warnings
end

function _artifact_file_records(packages)
    records = Dict{String, Any}[]
    for package in packages
        path = get(package, "artifacts_file", nothing)
        path isa AbstractString && isfile(path) || continue
        parsed = try
            TOML.parsefile(path)
        catch
            Dict{String, Any}()
        end
        push!(records,
            Dict{String, Any}(
                "kind" => "artifact_binding_file", "state" => "declared",
                "package_uuid" => package["uuid"], "package" => package["name"],
                "path" => path, "sha256" => bytes2hex(SHA.sha256(read(path))),
                "binding_names" => sort!(String.(collect(keys(parsed)))),
                "binding_count" => length(parsed),
                "warning" => "bindings may be platform-selective or overridden at runtime"))
    end
    return records
end

function _library_record(path::AbstractString; digest::Bool)
    normalized = abspath(String(path))
    exists = isfile(normalized)
    sha = if digest && exists
        try
            bytes2hex(SHA.sha256(read(normalized)))
        catch
            nothing
        end
    else
        nothing
    end
    return Dict{String, Any}(
        "kind" => "native_image", "state" => "observed",
        "path" => normalized, "filename" => basename(normalized),
        "exists" => exists, "size_bytes" => exists ? filesize(normalized) : nothing,
        "sha256" => sha, "format" => lowercase(splitext(normalized)[2]),
        "architecture" => string(Sys.ARCH), "sensitivity" => "internal",
        "symbolization" => "not_inspected")
end

"""
    loaded_library_inventory(; digest=false)

Return `(libraries, warnings)` for unique `Libdl.dllist()` entries, sorted by
path. Each record includes absolute path, filename, existence, optional size,
architecture and optional SHA-256. With `digest=true`, read existing library
files to hash them; failed hashes remain `nothing`. Inspection failures become
bounded warnings. Paths may reveal local installation information.
This does not load libraries or inspect symbols, child processes or native heaps.
"""
function loaded_library_inventory(; digest::Bool = false)
    libraries = Dict{String, Any}[]
    warnings = String[]
    for library in unique!(String.(Libdl.dllist()))
        isempty(library) && continue
        try
            push!(libraries, _library_record(library; digest))
        catch error
            push!(warnings,
                "could not inspect $(basename(library)): " *
                first(sprint(showerror, error), 300))
        end
    end
    sort!(libraries; by = record -> lowercase(String(record["path"])))
    return libraries, warnings
end

"""
    dependency_evidence(; phase="snapshot", hash_libraries=false)

Return [`NativeDependencyEvidence`](@ref) combining active Pkg inventory,
declared artifact bindings and currently loaded libraries. `phase` is an
arbitrary caller label; `hash_libraries=true` opts into reading library bytes.
Artifact binding files are always read and hashed when present; platform
selection and runtime overrides prevent interpreting declarations as loads.
Warnings explicitly record that child processes and services are outside scope.
No dependency is installed and no report is written.
"""
function dependency_evidence(; phase::AbstractString = "snapshot",
        hash_libraries::Bool = false)
    packages, package_warnings = package_dependency_inventory()
    libraries, library_warnings = loaded_library_inventory(; digest = hash_libraries)
    return NativeDependencyEvidence(String(phase), packages,
        _artifact_file_records(packages), libraries,
        vcat(package_warnings, library_warnings,
            ["loaded-library evidence covers this process only; child processes and services require runner collectors"]))
end

"""
    dependency_evidence_dict(evidence::NativeDependencyEvidence)

Return `perfchecker-dependency-evidence/1` with the capture phase, package,
artifact/library records, warnings and explicit coverage flags. `captured_at`
is the UTC conversion time; it is not a retained timestamp of every observation.
Nested records are retained and no new inventory or file export is performed.
"""
function dependency_evidence_dict(evidence::NativeDependencyEvidence)
    return Dict{String, Any}(
        "schema_version" => DEPENDENCY_EVIDENCE_SCHEMA,
        "captured_at" => string(Dates.now(Dates.UTC)),
        "phase" => evidence.phase,
        "packages" => evidence.packages,
        "artifact_files" => evidence.artifact_files,
        "loaded_libraries" => evidence.loaded_libraries,
        "warnings" => evidence.warnings,
        "coverage" => Dict("declared_packages" => true,
            "declared_artifact_bindings" => true,
            "loaded_current_process" => true,
            "child_process_tree" => false, "services" => false,
            "native_heap" => false))
end

@testitem "Native dependency evidence" tags=[:unit, :native, :protocol] begin
    using PerfChecker

    packages, warnings = package_dependency_inventory()
    @test packages isa Vector{Dict{String, Any}}
    @test warnings isa Vector{String}
    @test any(record -> record["name"] == "PerfChecker", packages)
    libraries, library_warnings = loaded_library_inventory()
    @test !isempty(libraries)
    @test all(record -> record["state"] == "observed", libraries)
    @test library_warnings isa Vector{String}
    payload = dependency_evidence_dict(dependency_evidence(; phase = "after_import"))
    @test payload["schema_version"] == "perfchecker-dependency-evidence/1"
    @test payload["phase"] == "after_import"
    @test !payload["coverage"]["child_process_tree"]
end
