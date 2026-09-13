using PerfChecker, TOML

const EXAMPLE_SOURCES = joinpath(@__DIR__, ".sources")
for (name, spec) in TOML.parsefile(joinpath(@__DIR__, "sources.toml"))
    source = joinpath(EXAMPLE_SOURCES, name)
    isdir(source) || error("Run examples/bibliography/setup.jl first")
    strip(read(`git -C $source rev-parse HEAD`, String)) == spec["revision"] ||
        error("The $name example revision changed")
end

# Keep the upstream builder intact in its own namespace.
module PinnedBibliographySuite
const SOURCES = joinpath(@__DIR__, ".sources")
withenv("BIBINTERNAL_PATH" => joinpath(SOURCES, "BibInternal"),
    "BIBPARSER_PATH" => joinpath(SOURCES, "BibParser"),
    "BIBLIOGRAPHY_PATH" => joinpath(SOURCES, "Bibliography")) do
    include(joinpath(SOURCES, "Bibliography/perf/suite.jl"))
end
end

function build_suite()
    suite = PinnedBibliographySuite.build_suite()
    for package in suite.packages, feature in package.features
        if feature.backend in (:profile, :wall_profile)
            # These seven workloads read their prepared inputs. A continuous
            # sampling window avoids restarting the timer for microsecond calls.
            # Timing/allocation collectors retain their fresh-state policy.
            feature.options[:state_policy] = :reuse
        end
    end
    return suite
end
