"""
    write_property_corpus(path, cases; producer="manual", metadata=Dict(), force=false)

Persist JSON-compatible property-generated cases before benchmarking them. The
result is a frozen input artifact: generation and shrinking do not run in
the timed worker. Return the absolute destination path, creating parents and
writing schema `perfchecker-property-corpus/1`, producer, UTC creation time,
case count, metadata with string keys and the cases. Existing files raise
`ArgumentError` unless `force=true`. Cases and metadata must be JSON-compatible;
serialization and filesystem errors propagate.

```jldoctest
julia> mktempdir() do directory
           path = write_property_corpus(joinpath(directory, "inputs.json"), [[1, 2], [3]]);
           read_property_corpus(path)["count"]
       end
2
```
"""
function write_property_corpus(path::AbstractString, cases::AbstractVector;
        producer::AbstractString = "manual", metadata::AbstractDict = Dict(),
        force::Bool = false)
    target = abspath(String(path))
    isfile(target) && !force &&
        throw(ArgumentError(
            "$target already exists; pass force=true to replace the frozen corpus"))
    payload = Dict{String, Any}(
        "schema_version" => "perfchecker-property-corpus/1",
        "producer" => String(producer),
        "created_at" => string(Dates.now(Dates.UTC)),
        "count" => length(cases),
        "metadata" => Dict(string(key) => value for (key, value) in pairs(metadata)),
        "cases" => collect(cases))
    mkpath(dirname(target))
    open(target, "w") do io
        JSON.print(io, payload, 2)
    end
    return target
end

"""
    read_property_corpus(path)

Read a frozen property corpus and return its JSON dictionary, including `cases`
and generation metadata. Reject missing files, unsupported schemas and a count
that disagrees with the stored cases. No generator or shrinking code is run.
"""
function read_property_corpus(path::AbstractString)
    source = abspath(String(path))
    isfile(source) || throw(ArgumentError("property corpus does not exist: $source"))
    payload = _json_parsefile(source)
    get(payload, "schema_version", nothing) == "perfchecker-property-corpus/1" ||
        throw(ArgumentError("unsupported property corpus schema in $source"))
    get(payload, "count", -1) == length(get(payload, "cases", Any[])) ||
        throw(ArgumentError("property corpus count does not match its cases in $source"))
    return payload
end

"""
    freeze_supposition_corpus(path, possibility; count=100, tries=100_000,
                              encode=identity, metadata=Dict(), force=false)

Load `Supposition` to enable this extension. Sample the possibility, encode the
cases as JSON-compatible values and persist them for later reproducible replay.
Return the corpus path; a positive count is required and existing files need
`force=true`. Replay uses saved inputs rather than resampling the generator.

Generation with the published Supposition backend requires 64-bit Julia.
On 32-bit Julia, use `freeze_propcheck_corpus` or replay a saved corpus with
`read_property_corpus`. Loading Supposition itself on 32-bit Julia can fail
before this API is reached because of an upstream dependency defect.
"""
function freeze_supposition_corpus(path::AbstractString, possibility; kwargs...)
    _require_supposition_runtime()
    throw(ArgumentError("Load Supposition on 64-bit Julia to enable this corpus backend"))
end

function _require_supposition_runtime()
    Sys.WORD_SIZE == 64 || throw(ArgumentError(
        "Supposition corpus generation requires 64-bit Julia; on 32-bit Julia use freeze_propcheck_corpus or read_property_corpus to replay saved inputs (upstream Supposition issue #76)"))
    return nothing
end
