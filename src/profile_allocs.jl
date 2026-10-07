prep(d::Dict, block::Expr, ::Val{:profile_alloc}) = quote
    import Profile
    $block
    nothing
end

function default_options(::Val{:profile_alloc})
    return Dict(:threads => 1, :targets => [], :track => "none", :repeat => true,
        :sample_rate => 1.0, :profile_repetitions => 1,
        :max_profile_stacks => 50_000)
end

function check(d::Dict, block::Expr, ::Val{:profile_alloc})
    warmup = get(d, :repeat, true) ? block : nothing
    fresh = get(d, :fresh_feature, false)
    if fresh
        setup = _fresh_feature_setup(d)
        warmup = quote
            $setup
            SharedScenarioRuntime.once(_perfchecker_shared_case)
        end
    end
    sample_rate = Float64(get(d, :sample_rate, 1.0))
    0.0 < sample_rate <= 1.0 ||
        throw(ArgumentError(":sample_rate must be in the interval (0, 1]"))
    repetitions = Int(get(d, :profile_repetitions, 1))
    repetitions > 0 || throw(ArgumentError(":profile_repetitions must be positive"))
    max_stacks = Int(get(d, :max_profile_stacks, 50_000))
    max_stacks > 1 || throw(ArgumentError(":max_profile_stacks must be greater than one"))
    target_names = String.(get(d, :targets, String[]))
    runtime = joinpath(@__DIR__, "profile_runtime.jl")
    byte_count = fresh ?
                 :(total_bytes = $(_fresh_profile_evaluation(:(Base.@allocated SharedScenarioRuntime.operation!(_perfchecker_evaluation))))) :
                 :(total_bytes = Base.@allocated $block)
    alloc_count = fresh ?
                  :(total_allocs = $(_fresh_profile_evaluation(:(Base.@allocations SharedScenarioRuntime.operation!(_perfchecker_evaluation))))) :
                  :(total_allocs = Base.@allocations $block)
    profiled = fresh ?
               _fresh_profile_evaluation(:(Profile.Allocs.@profile sample_rate=$sample_rate SharedScenarioRuntime.operation!(_perfchecker_evaluation))) :
               nothing
    collection = if fresh
        quote
            for _ in 1:($repetitions)
                $profiled
            end
        end
    else
        quote
            Profile.Allocs.@profile sample_rate=$sample_rate begin
                for _ in 1:($repetitions)
                    $block
                end
            end
        end
    end
    return quote
        isdefined(Main, :PerfCheckerProfileRuntime) || include($runtime)
        $warmup
        target_names = Set(Symbol.($target_names))
        loaded = Base.loaded_modules_array()
        targets = isempty(target_names) ? loaded :
                  filter(module_value -> nameof(module_value) in target_names, loaded)
        target_roots = String[]
        for module_value in targets
            source = pathof(module_value)
            source === nothing || push!(target_roots, dirname(abspath(source)))
        end
        isempty(target_roots) &&
            error("No loaded allocation target found in $(collect(target_names))")
        $byte_count
        $alloc_count
        Profile.Allocs.clear()
        $collection
        allocation_results = Profile.Allocs.fetch()
        grouped = Dict{Tuple{String, Int, Tuple{Vararg{String}}}, Tuple{Int64, Int64}}()
        # Malt evaluates this expression at Main's top level. Mutating a Ref
        # keeps the loop counter valid without changing the workload's scope.
        source_allocs = Ref(Int64(0))
        for allocation in allocation_results.allocs
            any(
                candidate -> !candidate.from_c && candidate.line > 0 &&
                                 PerfCheckerProfileRuntime.usable_source(String(candidate.file)),
                allocation.stacktrace) && (source_allocs[] += 1)
            target_positions = PerfCheckerProfileRuntime.allocation_source_positions(
                allocation.stacktrace, target_roots)
            isempty(target_positions) && continue
            site = allocation.stacktrace[first(target_positions)]
            root_position = last(target_positions)
            frames = reverse(allocation.stacktrace[1:root_position])
            stack = String[]
            for candidate in frames
                candidate.line > 0 || continue
                source = String(candidate.file)
                isempty(source) && continue
                source_parts = split(replace(normpath(source), '\\' => '/'), '/')
                short_source = join(last(source_parts, min(length(source_parts), 3)), '/')
                push!(stack, "$(candidate.func) ($short_source:$(candidate.line))")
            end
            isempty(stack) && continue
            key = (abspath(String(site.file)), Int(site.line), Tuple(stack))
            bytes, count = get(grouped, key, (Int64(0), Int64(0)))
            grouped[key] = (bytes + Int64(allocation.size), count + 1)
        end
        sampled_bytes, sampled_allocs = PerfCheckerProfileRuntime.allocation_sample_totals(grouped)
        byte_scale = sampled_bytes == 0 ? 0.0 : Float64(total_bytes) / sampled_bytes
        alloc_scale = sampled_allocs == 0 ? 0.0 : Float64(total_allocs) / sampled_allocs
        ordered = sort!(
            collect(grouped); by = item -> (
                -last(item)[1], first(item)[1], first(item)[2]))
        keep = length(ordered) > $max_stacks ? $max_stacks - 1 : length(ordered)
        output = $ProfileAllocSite[(bytes = values[1] * byte_scale,
                                       allocs = values[2] * alloc_scale,
                                       filename = key[1], line = key[2], stack = collect(key[3]))
                                   for (key, values) in first(ordered, keep)]
        if length(ordered) > $max_stacks
            remainder_bytes = sum(item -> last(item)[1],
                ordered[($max_stacks):end]; init = Int64(0)) * byte_scale
            remainder_allocs = sum(item -> last(item)[2],
                ordered[($max_stacks):end]; init = Int64(0)) * alloc_scale
            push!(output,
                (bytes = remainder_bytes, allocs = remainder_allocs,
                    filename = "[other]", line = 0,
                    stack = ["Other sampled allocation stacks"]))
        end
        summary = PerfCheckerProfileRuntime.allocation_summary(
            total_bytes = total_bytes, total_allocations = total_allocs,
            sampled_allocations = length(allocation_results.allocs),
            source_allocations = source_allocs[], retained_allocations = sampled_allocs,
            retained_bytes = sampled_bytes, sample_rate = $sample_rate,
            profile_evaluations = $repetitions,
            weight_semantics = "independent whole-operation totals apportioned over retained stacks; estimates, not exact target totals")
        (sites = output, summary = summary)
    end
end

post(d::Dict, ::Val{:profile_alloc}) = d[:check_result].sites

const ProfileAllocSite = @NamedTuple{
    bytes::Float64, allocs::Float64, filename::String, line::Int,
    stack::Vector{String}}

function to_table(records::Vector{ProfileAllocSite})
    return Table(
        bytes = [record.bytes for record in records],
        allocs = [record.allocs for record in records],
        filename = [record.filename for record in records],
        line = [record.line for record in records],
        stack = [record.stack for record in records])
end

to_table(capture::NamedTuple{(:sites, :summary)}) = to_table(capture.sites)

_allocation_cache_path(path) = path * ".allocation-profile.toml"

function _write_allocation_cache(path, table, summary)
    document = Dict(
        "schema_version" => PerfCheckerProfileRuntime.ALLOCATION_PROFILE_SCHEMA,
        "result_uuid" => splitext(basename(path))[1], "summary" => summary,
        "sites" => [Dict(string(key) => value for (key, value) in pairs(row))
                    for row in table])
    mkpath(dirname(path))
    temporary, io = mktemp(dirname(path))
    try
        TOML.print(io, document)
        close(io)
        mv(temporary, _allocation_cache_path(path); force = true)
    finally
        close(io)
        rm(temporary; force = true)
    end
    nothing
end

function _read_allocation_cache(path)
    sidecar = _allocation_cache_path(path)
    isfile(sidecar) || return nothing
    try
        document = TOML.parsefile(sidecar)
        document["schema_version"] == PerfCheckerProfileRuntime.ALLOCATION_PROFILE_SCHEMA ||
            return nothing
        document["result_uuid"] == splitext(basename(path))[1] || return nothing
        summary = document["summary"]
        expected = PerfCheckerProfileRuntime.allocation_summary(
            total_bytes = summary["total_bytes"],
            total_allocations = summary["total_allocations"],
            sampled_allocations = summary["sampled_allocations"],
            retained_allocations = summary["retained_allocations"],
            source_allocations = summary["source_allocations"],
            retained_bytes = summary["retained_sampled_bytes"],
            sample_rate = summary["sample_rate"],
            profile_evaluations = summary["profile_evaluations"],
            weight_semantics = summary["weight_semantics"])
        summary == expected || return nothing
        sites = ProfileAllocSite[(bytes = Float64(row["bytes"]),
                                     allocs = Float64(row["allocs"]), filename = String(row["filename"]),
                                     line = Int(row["line"]), stack = String.(row["stack"]))
                                 for row in document["sites"]]
        all(
            row -> isfinite(row.bytes) && row.bytes >= 0 &&
                       isfinite(row.allocs) && row.allocs >= 0,
            sites) || return nothing
        isempty(sites) == (summary["retained_allocations"] == 0) || return nothing
        (sites = sites, summary = summary)
    catch error
        error isa InterruptException && rethrow()
        # A stale or partial cache is a miss, never evidence of zero allocations.
        nothing
    end
end

@testitem "Profile allocation records" tags=[:unit, :allocations, :profile_alloc] begin
    using PerfChecker

    records = PerfChecker.ProfileAllocSite[
        (bytes = 64.0, allocs = 2.0, filename = "src/demo.jl", line = 12,
        stack = ["demo (src/demo.jl:12)"])]
    table = PerfChecker.to_table(records)
    @test table.bytes == [64.0]
    @test table.allocs == [2.0]
    @test table.filename == ["src/demo.jl"]
    @test table.stack == [["demo (src/demo.jl:12)"]]
    @test PerfChecker.default_options(Val(:profile_alloc))[:track] == "none"
end
