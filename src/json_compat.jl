"""Parse JSON into ordinary dictionaries on every supported JSON.jl major."""
function _json_parse(source)
    return JSON.parse(source; dicttype = Dict{String, Any})
end

"""Read JSON without retaining a memory-mapped handle to the source file."""
function _json_parsefile(path::AbstractString)
    return open(path, "r") do io
        _json_parse(io)
    end
end

# Older TOML readers return Vector{Union{}} for an empty array. JSON 1 treats
# that bottom element type as a Pair vector and encodes it as an object. Keep
# the container roles explicit when converting worker requests back to JSON.
_json_plain_value(value) = value
function _json_plain_value(value::AbstractDict)
    Dict(
        key => _json_plain_value(item) for (key, item) in value)
end
_json_plain_value(value::AbstractVector) = Any[_json_plain_value(item) for item in value]

@testitem "JSON compatibility layer" tags=[:unit, :json] begin
    using PerfChecker

    mktempdir() do dir
        path = joinpath(dir, "nested.json")
        write(path, """{"outer":{"value":1}}""")
        parsed = PerfChecker._json_parsefile(path)
        @test parsed isa Dict{String, Any}
        @test parsed["outer"] isa Dict{String, Any}
        @test parsed["outer"]["value"] == 1
    end
end
