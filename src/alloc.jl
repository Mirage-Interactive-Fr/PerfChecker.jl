prep(d::Dict, block::Expr, ::Val{:alloc}) = quote
    import Profile
    $block
    nothing
end

function default_options(::Val{:alloc})
    return Dict(:threads => 1, :targets => [], :track => "user", :repeat => true)
end

stop_before_post(::Val{:alloc}) = true

# Julia writes source.<pid>.mem next to the source, including sources outside
# the copied environment. Keep ownership separate from the measured result so
# exceptions and cancellation cannot lose the cleanup inventory.
struct AllocationSnapshot
    bytes::Vector{UInt8}
    mode::UInt
    modified::Float64
    changed::Float64
end

mutable struct AllocationArtifacts
    pid::Int
    roots::Vector{String}
    preserved::Dict{String, AllocationSnapshot}
    journal::String
end

# Canonicalise the existing parent because the trace itself may not exist yet.
# On Windows, short names and case aliases otherwise let cleanup restore one
# spelling and subsequently remove the same file under another spelling.
_allocation_path(file) = joinpath(realpath(dirname(file)), basename(file))

function _allocation_files(roots, pid)
    files = String[]
    suffix = ".$pid.mem"
    for root in unique(roots)
        isdir(root) || continue
        for (directory, _, names) in walkdir(root; follow_symlinks = false,
            onerror = error -> @debug("cannot inspect allocation artifacts",
                exception=error))
            for name in names
                endswith(name, suffix) || continue
                file = joinpath(directory, name)
                isfile(file) && !islink(file) && push!(files, _allocation_path(file))
            end
        end
    end
    unique(files)
end

function _allocation_roots(options, environments)
    roots = String[@__DIR__, Sys.STDLIB]
    append!(roots, abspath.(String.(environments)))
    haskey(options, :path) && push!(roots, abspath(String(options[:path])))
    for depot in DEPOT_PATH, directory in ("packages", "dev")
        push!(roots, joinpath(depot, directory))
    end
    for key in (:devops, :extra_devops)
        specs = get(options, key, nothing)
        specs === nothing && continue
        specs isa Tuple && (specs = first(specs))
        specs = specs isa AbstractVector ? specs : [specs]
        for spec in specs
            if spec isa PackageSpec && spec.path !== nothing
                push!(roots, abspath(spec.path))
            elseif spec isa NamedTuple && haskey(spec, :path)
                push!(roots, abspath(String(spec.path)))
            end
        end
    end
    for environment in environments
        for name in ("Project.toml", "Manifest.toml",
            "Manifest-v$(VERSION.major).$(VERSION.minor).toml")
            file = joinpath(environment, name)
            isfile(file) || continue
            document = TOML.parsefile(file)
            entries = name == "Project.toml" ? values(get(document, "sources", Dict())) :
                      Iterators.flatten(values(get(document, "deps", Dict())))
            for entry in entries
                entry isa AbstractDict && haskey(entry, "path") || continue
                push!(roots, abspath(environment, String(entry["path"])))
            end
        end
    end
    unique(realpath(root) for root in roots if isdir(root))
end

function _register_allocation_roots!(artifacts, roots)
    roots = unique(realpath(root) for root in roots if isdir(root))
    new_roots = filter(roots) do root
        !any(artifacts.roots) do previous
            relative = relpath(root, previous)
            relative == "." || !(first(splitpath(relative)) == ".." || isabspath(relative))
        end
    end
    for file in _allocation_files(new_roots, artifacts.pid)
        any(artifacts.roots) do root
            relative = relpath(file, root)
            !(first(splitpath(relative)) == ".." || isabspath(relative))
        end && continue
        haskey(artifacts.preserved, file) && continue
        original, info = read(file), stat(file)
        mode = UInt(info.mode & 0o777)
        artifacts.preserved[file] = AllocationSnapshot(
            original, mode, info.mtime, info.ctime)
        # A cleanup failure may outlive the controller stack. Retain the actual
        # bytes, not just a list of filenames, in the private worker inventory.
        open(artifacts.journal, "a") do io
            write(io, Int64(ncodeunits(file)))
            write(io, file)
            write(io, Int64(length(original)))
            write(io, original)
            write(io, UInt64(mode))
            write(io, Float64(info.mtime))
            write(io, Float64(info.ctime))
        end
    end
    append!(artifacts.roots, new_roots)
    artifacts
end

function _allocation_artifacts(worker, journal)
    AllocationArtifacts(Int(getpid(worker.proc)), String[],
        Dict{String, AllocationSnapshot}(), journal)
end

function _install_allocation_journal!(worker, artifacts)
    # This callback runs before ordinary include evaluates user code. The private
    # journal is also usable after a worker crashes; cleanup never queries it.
    remote_eval_wait(Main,
        worker,
        quote
            let journal = $(artifacts.journal), suffix = $(".$(artifacts.pid).mem"),
                seen = Set{String}(), gate = ReentrantLock()

                push!(Base.include_callbacks,
                    function (_, source)
                        file = joinpath(realpath(dirname(source)), basename(source)) * suffix
                        lock(gate) do
                            file in seen && return
                            push!(seen, file)
                            original = isfile(file) && !islink(file) ? read(file) : nothing
                            info = original === nothing ? nothing : stat(file)
                            mode = info === nothing ? UInt(0) : UInt(info.mode & 0o777)
                            open(journal, "a") do io
                                write(io, Int64(ncodeunits(file)))
                                write(io, file)
                                write(io,
                                    original === nothing ? Int64(-1) :
                                    Int64(length(original)))
                                original === nothing || write(io, original)
                                write(io, UInt64(mode))
                                write(io, info === nothing ? 0.0 : Float64(info.mtime))
                                write(io, info === nothing ? 0.0 : Float64(info.ctime))
                            end
                        end
                        nothing
                    end)
            end
        end)
    nothing
end

function _allocation_journal!(artifacts)
    paths = String[]
    isfile(artifacts.journal) || return paths
    open(artifacts.journal) do io
        while !eof(io)
            record = try
                length = read(io, Int64)
                0 < length <= 1_000_000 || error("invalid allocation journal path")
                file = String(read(io, length))
                count = read(io, Int64)
                original = count < 0 ? nothing : read(io, count)
                mode = UInt(read(io, UInt64))
                modified, changed = read(io, Float64), read(io, Float64)
                (file, original, mode, modified, changed)
            catch error
                # A killed worker may stop halfway through the append. The
                # callback has not evaluated that source yet; earlier complete
                # records and the pre-registered roots remain valid.
                error isa EOFError || rethrow()
                break
            end
            file, original, mode, modified, changed = record
            file = _allocation_path(file)
            push!(paths, file)
            original === nothing || get!(artifacts.preserved, file,
                AllocationSnapshot(original, mode, modified, changed))
        end
    end
    paths
end

function _cleanup_allocation_artifacts!(artifacts)
    paths = _allocation_journal!(artifacts)
    append!(paths, _allocation_files(artifacts.roots, artifacts.pid))
    append!(paths, keys(artifacts.preserved))
    failures = Any[]
    for file in unique(paths)
        islink(file) && continue
        try
            if haskey(artifacts.preserved, file)
                original = artifacts.preserved[file]
                isfile(file) && UInt(stat(file).mode & 0o777) != original.mode &&
                    chmod(file, original.mode)
                if !isfile(file) || read(file) != original.bytes
                    write(file, original.bytes)
                end
                chmod(file, original.mode)
            else
                rm(file; force = true)
            end
        catch error
            @warn "Could not clean allocation trace" file exception=error
            push!(failures, error)
        end
    end
    isempty(failures) || throw(CompositeException(failures))
    nothing
end

function _retain_allocation_inventory!(artifacts)
    open(joinpath(dirname(artifacts.journal), "allocation-inventory.toml"), "w") do io
        TOML.print(io,
            Dict("worker_pid" => artifacts.pid, "roots" => artifacts.roots,
                "journal" => basename(artifacts.journal)))
    end
    nothing
end

function check(d::Dict, block::Expr, ::Val{:alloc})
    j = haskey(d, :repeat) && d[:repeat] ? block : nothing

    quote
        $j
        Profile.clear_malloc_data()
        $block
        rmstuff = Base.loaded_modules_array()
        target_names = Set(Symbol.(String.($(d[:targets]))))
        targets = if isempty(target_names)
            rmstuff
        else
            filter(m -> nameof(m) in target_names, rmstuff)
        end
        return dirname.(filter(!isnothing, pathof.(targets))),
        dirname.(filter(!isnothing, pathof.(rmstuff)))
    end
end

function post(d::Dict, ::Val{:alloc})
    result = d[:check_result]
    artifacts = d[:allocation_artifacts]
    _allocation_journal!(artifacts)
    files = _allocation_files(result[1], artifacts.pid)
    # A reused PID can overwrite an old trace with this run's valid measurement.
    # Analyse the new bytes now, then restore the old bytes during cleanup.
    filter!(files) do file
        haskey(artifacts.preserved, file) || return true
        original, current = artifacts.preserved[file], stat(file)
        read(file) != original.bytes || current.mtime != original.modified ||
            current.ctime != original.changed
    end
    if isempty(files)
        throw(ErrorException("No allocation files found in $(d[:targets])"))
    end
    myallocs = analyze_malloc_files(files; skip_zeros = true)
    if isempty(myallocs)
        @warn "Allocation files do not contain non-zero allocation entries" targets=d[:targets]
    end
    return myallocs
end

function rm_malloc_files(paths)
    for file in unique(_malloc_files(paths))
        try
            rm(file; force = true)
        catch err
            @debug "failed to remove allocation tracking file" file exception=(
                err, catch_backtrace())
        end
    end
    return nothing
end

function _malloc_files(paths)
    files = String[]
    for path in paths
        path === nothing && continue
        strpath = String(path)
        if isdir(strpath)
            append!(files, find_malloc_files([strpath]))
        elseif isfile(strpath) && endswith(strpath, ".mem")
            push!(files, strpath)
        end
    end
    return files
end

function cleanup(d::Dict, ::Val{:alloc})
    artifacts = get(d, :allocation_artifacts, nothing)
    artifacts === nothing || _cleanup_allocation_artifacts!(artifacts)
    return nothing
end

function to_table(myallocs::Vector{MallocInfo})
    b = map(a -> a.bytes, Iterators.reverse(myallocs))
    r = round.(b / sum(b) * 100; digits = 2)
    f = map(first ∘ splitext ∘ first ∘ splitext,
        map(a -> a.filename, Iterators.reverse(myallocs)))
    l = map(a -> a.linenumber, Iterators.reverse(myallocs))
    Table(bytes = b, percentage = r, filename = f, line = l, filenames = f, linenumbers = l)
end

@testitem "Allocation artifacts" tags=[:unit, :allocations] begin
    import PerfChecker

    mktempdir() do dir
        memfile = joinpath(dir, "dummy.jl.123.mem")
        write(memfile, "1 1\n")
        @test isfile(memfile)
        PerfChecker.rm_malloc_files([dir])
        @test !isfile(memfile)
    end
end
