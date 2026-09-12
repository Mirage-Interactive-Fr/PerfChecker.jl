const MACHINE_PROFILE_SCHEMA = "perfchecker-machine-profile/1"
const MACHINE_ESTIMATE_SCHEMA = "perfchecker-machine-estimate/1"

"""
    machine_profile(; label="", limits=Dict())

Capture a specification fingerprint, independent of host name and transient CPU load.
This identifies a specification class, not a unique physical machine. Declare CI
CPU quotas, affinity and memory limits in `limits`; unknown limits remain unknown.
"""
function machine_profile(; label::AbstractString = "", limits::AbstractDict = Dict())
    info = HwInfo()
    specs = Dict{String, Any}("cpu" => info.machine, "architecture" => string(Sys.ARCH),
        "os" => string(Sys.KERNEL), "word_bits" => info.word,
        "physical_cores" => info.corecount[1], "logical_cpus" => info.corecount[2],
        "simd_bytes" => info.simdbytes, "memory_bytes" => Sys.total_memory(),
        "julia_threads" => Threads.nthreads(), "limits" => Dict(string(k) => v
        for (k, v) in limits))
    Dict("schema_version" => MACHINE_PROFILE_SCHEMA, "label" => String(label),
        "spec_id" => bytes2hex(SHA.sha256(_canonical_json(specs))), "specs" => specs,
        "julia_version" => string(VERSION), "limits_verified" => false)
end

function _machine_specs(profile)
    get(profile, "schema_version", "") == MACHINE_PROFILE_SCHEMA ||
        throw(ArgumentError("unsupported machine profile schema"))
    specs = profile["specs"]
    for key in ("architecture", "os", "cpu")
        value = get(specs, key, nothing)
        value isa AbstractString && !isempty(value) ||
            throw(ArgumentError("missing machine $key"))
    end
    specs
end

"Rank specification neighbours; a small distance is not performance equivalence."
function similar_machines(
        target::AbstractDict, profiles::AbstractVector; limit::Integer = 5)
    limit > 0 || throw(ArgumentError("limit must be positive"))
    target_specs = _machine_specs(target)
    rows = Dict{String, Any}[]
    for profile in profiles
        specs = _machine_specs(profile)
        all(get(target_specs, k, nothing) == get(specs, k, nothing)
        for k in ("architecture", "os", "word_bits")) || continue
        terms = Float64[]
        missing = String[]
        for key in (
            "physical_cores", "logical_cpus", "simd_bytes", "memory_bytes", "julia_threads")
            a, b = get(target_specs, key, nothing), get(specs, key, nothing)
            if a isa Real && b isa Real && isfinite(a) && isfinite(b) && a > 0 && b > 0
                push!(terms, abs(log(Float64(a) / Float64(b))))
            else
                push!(missing, key)
            end
        end
        isempty(terms) && continue
        push!(rows,
            Dict("spec_id" => profile["spec_id"], "label" => get(profile, "label", ""),
                "distance" => sum(terms) / length(terms) +
                              (target_specs["cpu"] == specs["cpu"] ? 0.0 : 1.0),
                "missing_features" => missing, "authority" => "specification_similarity_only"))
    end
    sort!(rows; by = r -> (r["distance"], r["spec_id"]))
    first(rows, min(limit, length(rows)))
end

function _calibration_times(values)
    values isa AbstractDict ||
        throw(ArgumentError("timings must be a workload-to-time map"))
    result = Dict{String, Float64}()
    for (key, value) in values
        value isa Real && !(value isa Bool) && isfinite(value) && value > 0 ||
            throw(ArgumentError("timing for $key must be finite and positive"))
        result[string(key)] = Float64(value)
    end
    result
end

"""
    estimate_performance(target, references, workload; neighbours=3,
                         min_calibrations=3, max_log_error=0.25)

Experimental calibrated nearest-neighbour transfer. Each record contains `machine`,
`context`, `calibration` (workload => positive seconds) and `measurements`.
Context must explicitly identify `suite_revision`, `environment`, `measurement`,
`unit`, and `resource_policy`; only equal contexts and OS/architecture are compared.
Fit a log time ratio on shared calibration workloads. Leave-one-workload-out error
rejects unstable transfers. Return a donor spread/error envelope, NOT a confidence
interval or a measured result. At least two independent machine labels are required.
Use only to prioritize actual measurements, never to qualify a CI performance gate.
"""
function estimate_performance(target::AbstractDict, references::AbstractVector,
        workload::AbstractString; neighbours::Integer = 3, min_calibrations::Integer = 3,
        max_log_error::Real = 0.25)
    neighbours >= 2 || throw(ArgumentError("at least two neighbours are required"))
    min_calibrations >= 3 ||
        throw(ArgumentError("at least three calibration workloads are required"))
    isfinite(max_log_error) && max_log_error > 0 ||
        throw(ArgumentError("invalid error limit"))
    context = target["context"]
    for key in ("suite_revision", "environment", "measurement", "unit", "resource_policy")
        value = get(context, key, nothing)
        value isa AbstractString && !isempty(value) ||
            throw(ArgumentError("explicit context.$key is required"))
    end
    target_machine = target["machine"]
    _machine_specs(target_machine)
    target_label = get(target_machine, "label", "")
    isempty(target_label) && throw(ArgumentError("target needs an explicit machine label"))
    calibration = _calibration_times(target["calibration"])
    haskey(calibration, workload) &&
        throw(ArgumentError("held-out workload must not be in calibration"))
    donors, rejected = Dict{String, Any}[], Dict{String, Any}[]
    seen = Set{String}()
    for reference in references
        machine = reference["machine"]
        label = String(get(machine, "label", ""))
        isempty(label) && throw(ArgumentError("reference needs an explicit machine label"))
        label in seen && throw(ArgumentError("duplicate reference machine label"))
        push!(seen, label)
        reason = if label == target_label
            "target machine cannot train its own prediction"
        elseif reference["context"] != context
            "measurement, code, environment or resource policy differs"
        elseif isempty(similar_machines(target_machine, [machine]))
            "incompatible OS or architecture"
        else
            ""
        end
        if !isempty(reason)
            push!(rejected, Dict("machine" => label, "reason" => reason))
            continue
        end
        times = _calibration_times(reference["calibration"])
        measurements = _calibration_times(reference["measurements"])
        shared = sort!(collect(intersect(keys(calibration), keys(times))))
        if !haskey(measurements, workload) || length(shared) < min_calibrations
            push!(rejected,
                Dict("machine" => label,
                    "reason" => "insufficient shared calibration or missing workload"))
            continue
        end
        ratios = [log(calibration[key] / times[key]) for key in shared]
        # Holding out each calibration workload tests transfer across workload shapes.
        error = maximum(abs(ratios[i] - _median(ratios[eachindex(ratios) .!= i]))
        for i in eachindex(ratios))
        if error > max_log_error
            push!(rejected,
                Dict(
                    "machine" => label, "reason" => "calibration transfer error too large",
                    "log_error" => error))
            continue
        end
        factor = exp(_median(ratios))
        estimate = measurements[String(workload)] * factor
        isfinite(estimate) && estimate > 0 ||
            throw(ArgumentError("transfer estimate overflow"))
        distance = only(similar_machines(target_machine, [machine]))["distance"]
        push!(donors,
            Dict("machine" => label, "spec_id" => machine["spec_id"],
                "estimate" => estimate, "scale" => factor, "log_error" => error,
                "distance" => distance, "calibrations" => shared))
    end
    sort!(donors; by = d -> (d["log_error"], d["distance"], d["machine"]))
    donors = first(donors, min(neighbours, length(donors)))
    enough = length(donors) >= 2
    Dict{String, Any}("schema_version" => MACHINE_ESTIMATE_SCHEMA,
        "status" => enough ? "estimated" : "insufficient_evidence",
        "authority" => "prediction_not_measurement", "ci_gate_eligible" => false,
        "workload" => String(workload), "context" => context,
        "target_machine" => target_label, "donors" => donors, "rejected" => rejected,
        "estimate" => enough ? _median(Float64[d["estimate"] for d in donors]) : nothing,
        "lower" => enough ? minimum(d["estimate"] * exp(-d["log_error"]) for d in donors) :
                   nothing,
        "upper" => enough ? maximum(d["estimate"] * exp(d["log_error"]) for d in donors) :
                   nothing,
        "interval_kind" => "donor_spread_with_calibration_error_not_confidence_interval",
        "external_validation" => "not_performed")
end
