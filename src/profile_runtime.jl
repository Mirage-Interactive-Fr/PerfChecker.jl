# Shared by the controller and dependency-light measurement workers.
module PerfCheckerProfileRuntime

const ALLOCATION_PROFILE_SCHEMA = "perfchecker-allocation-profile/1"

function normalize_source(path)
    Sys.iswindows() ? lowercase(normpath(abspath(path))) :
    normpath(abspath(path))
end

function within_root(path, root)
    relative = try
        relpath(normalize_source(path), normalize_source(root))
    catch error
        error isa ArgumentError || rethrow()
        return false
    end
    !isabspath(relative) && first(splitpath(relative)) != ".."
end

function usable_source(source)
    !isempty(source) && !(source in ("none", "REPL", "string")) &&
        !startswith(source, "REPL[")
end
function source_in_roots(source, roots)
    usable_source(source) &&
        any(root -> within_root(source, root), roots)
end

function allocation_source_positions(stack, roots)
    findall(stack) do frame
        !frame.from_c && frame.line > 0 && source_in_roots(String(frame.file), roots)
    end
end

function allocation_sample_totals(grouped)
    (
        sum(item -> Int64(first(item)), values(grouped); init = Int64(0)),
        sum(item -> Int64(last(item)), values(grouped); init = Int64(0)))
end

function allocation_summary(; total_bytes, total_allocations, sampled_allocations,
        retained_allocations, source_allocations, retained_bytes, sample_rate,
        profile_evaluations, weight_semantics)
    all(value -> value isa Integer && value >= 0,
        (total_bytes, total_allocations, sampled_allocations,
            retained_allocations, source_allocations)) ||
        throw(ArgumentError("allocation counters must be nonnegative integers"))
    0 <= retained_allocations <= source_allocations <= sampled_allocations ||
        throw(ArgumentError("allocation sample counters are inconsistent"))
    isfinite(retained_bytes) && retained_bytes >= 0 ||
        throw(ArgumentError("sampled allocation bytes must be finite and nonnegative"))
    isfinite(sample_rate) && 0 < sample_rate <= 1 ||
        throw(ArgumentError("allocation sample_rate must be in (0, 1]"))
    profile_evaluations isa Integer && profile_evaluations > 0 ||
        throw(ArgumentError("allocation profile_evaluations must be positive"))
    status, message = if retained_allocations > 0
        "complete",
        retained_bytes == 0 ?
        "Allocation stacks have zero sampled byte weight; their event counts remain available." :
        "Allocation stacks were captured."
    elseif sampled_allocations == 0
        if total_bytes == 0 && total_allocations == 0
            "zero_allocations",
            "The independent operation measurements allocated zero Julia bytes and objects; no allocation stacks were captured."
        else
            "no_samples",
            "No allocation events were sampled despite nonzero independently measured totals. Increase sample_rate or profile_repetitions; missing stacks do not mean zero allocations."
        end
    elseif source_allocations > 0
        "outside_target_scope",
        "Sampled allocations had no source frames in the selected targets. Check targets; the independent totals cover the whole operation."
    else
        "unattributed_samples",
        "Allocation events were sampled without usable source locations. The independent totals remain available, but no source attribution is possible."
    end
    retained_allocations == 0 && retained_bytes != 0 &&
        throw(ArgumentError("allocation bytes require retained samples"))
    Dict{String, Any}(
        "schema_version" => ALLOCATION_PROFILE_SCHEMA,
        "status" => status, "message" => message,
        "total_bytes" => total_bytes, "total_allocations" => total_allocations,
        "total_measurement_evaluations" => 2,
        "bytes_measurement_evaluations" => 1,
        "count_measurement_evaluations" => 1,
        "total_semantics" => "bytes and allocation count from two separate operation evaluations; not inferred from samples",
        "sampled_allocations" => sampled_allocations,
        "retained_allocations" => retained_allocations,
        "source_allocations" => source_allocations,
        "retained_sampled_bytes" => retained_bytes,
        "sample_rate" => sample_rate, "profile_evaluations" => profile_evaluations,
        "weight_semantics" => weight_semantics)
end

end
