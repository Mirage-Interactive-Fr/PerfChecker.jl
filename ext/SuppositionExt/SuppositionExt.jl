module SuppositionExt

using PerfChecker
using Supposition

function PerfChecker.freeze_supposition_corpus(path::AbstractString,
        possibility::Supposition.Data.Possibility;
        count::Integer = 100, tries::Integer = 100_000, encode::Function = identity,
        metadata::AbstractDict = Dict(), force::Bool = false)
    PerfChecker._require_supposition_runtime()
    count > 0 || throw(ArgumentError("corpus count must be positive"))
    cases = Supposition.example(possibility, count; tries)
    encoded = map(encode, cases)
    details = Dict{String, Any}(string(key) => value for (key, value) in pairs(metadata))
    details["generator_type"] = string(typeof(possibility))
    details["tries_per_case"] = tries
    return PerfChecker.write_property_corpus(path, encoded;
        producer = "Supposition.jl", metadata = details, force)
end

end
