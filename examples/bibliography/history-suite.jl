using PerfChecker, TOML

const HISTORY_VERSIONS = v"0.1.0", v"0.2.0", v"0.2.5", v"0.2.10", v"0.2.15",
v"0.2.20", v"0.3.0", v"0.3.1", v"0.4.0"

function history_sources()
    sources = TOML.parsefile(joinpath(@__DIR__, "sources.toml"))
    upstream = load_software_suite(joinpath(@__DIR__, "suite.jl"))
    package = only(filter(package -> package.package == "Bibliography", upstream.packages))
    function revision(name, version)
        strip(read(
            `git -C $(joinpath(@__DIR__, ".sources", name)) rev-parse $("v$(version)^{commit}")`,
            String))
    end
    records = Dict{String, Any}[]
    for version in HISTORY_VERSIONS
        # The upstream fixture pairs 0.2.10 with BibParser 0.1.9, whose
        # DataStructures 0.17 constraint conflicts with Bibliography's 0.18.
        # 0.1.10 is the next tagged parser and accepts DataStructures 0.18.
        pins = version == v"0.2.10" ?
               [(name = "BibInternal", version = v"0.2.4"),
            (name = "BibParser", version = v"0.1.10")] : package.release_pins[version]
        dependencies = [Dict("name" => pin.name, "version" => string(pin.version),
                            "url" => sources[pin.name]["url"], "revision" => revision(
                                pin.name, pin.version))
                        for pin in pins]
        push!(records,
            Dict("version" => string(version), "url" => sources["Bibliography"]["url"],
                "revision" => revision("Bibliography", version), "dependencies" => dependencies))
    end
    return package, records
end

function build_suite()
    upstream, records = history_sources()
    candidates = [SuiteCandidate(record["version"], record["revision"];
                      source = upstream.source, compatibility_version = VersionNumber(record["version"]),
                      dependencies = [(name = dependency["name"],
                                          url = dependency["url"],
                                          rev = dependency["revision"])
                                      for dependency in record["dependencies"]])
                  for record in records]
    features = filter(feature -> feature.backend == :benchmark, upstream.features)
    package = PackageSuite("Bibliography"; source = upstream.source,
        worker_environment = worker_environment(upstream), versions = VersionNumber[],
        include_dev = false, features, candidates)
    comparisons = [ComparisonPolicy("history-$(feature.id)"; package = "Bibliography",
                       feature = string(feature.id), baselines = ["0.1.0"],
                       candidates = string.(collect(HISTORY_VERSIONS)[2:end]))
                   for feature in features if feature.id != :read_and_filter]
    return SoftwareSuite(:bibliography, [package]; comparisons,
        description = "Nine Git-tagged Bibliography versions with pinned dependency revisions")
end
