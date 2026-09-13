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
