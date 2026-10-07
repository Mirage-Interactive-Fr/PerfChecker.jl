"""
    table_to_csv(table::Table, path::String)

Write a `TypedTables.Table` to `path`, creating the parent directory if needed.
Return `CSV.write`'s destination result; an existing file is replaced with the
table's column header and rows. This exports supplied table values without unit
conversion, bundle metadata or integrity protection. Serialization/filesystem
errors propagate; no workload is run.
"""
function table_to_csv(t::Table, path::String)
    mkpath(dirname(path))
    CSV.write(path, t)
end

"""
    csv_to_table(path::String) -> Table

Read a CSV file into a `TypedTables.Table`, using CSV's default column type
inference. Return the table; file/parser errors propagate. CSV does not retain
run-bundle provenance, qualification or measurement definitions, so loading a
table alone does not establish comparison compatibility.
"""
csv_to_table(path::String) = CSV.read(path, Table)

"""
    check_to_metadata_csv(backend, pkg, version, tags; metadata="")

Compatibility wrapper for the legacy metadata format. New runs use structured
metadata with result UUIDs and config hashes. Return `(flattened_parameters,
uuid_seed)` for backend, package/version and tags. With a nonempty `metadata`
**path**, append the parameters/UUID row unless it is already present, creating
parents when needed. With the default empty path, no file is written.
This is legacy cache metadata, not a measurement table or modern run bundle.
"""
function check_to_metadata_csv(
        x::Symbol, pkg::AbstractString, version, tags::Vector{Symbol}; metadata = "")
    check_to_metadata(x, pkg, version, tags; metadata)
end

@testitem "CSV round trip" tags=[:unit, :reporting] begin
    using PerfChecker

    mktempdir() do dir
        path = joinpath(dir, "nested", "result.csv")
        original = PerfChecker.Table(times = [1.0, 2.0], allocs = [1, 2])
        table_to_csv(original, path)
        restored = csv_to_table(path)
        @test restored.times == original.times
        @test restored.allocs == original.allocs
    end
end
