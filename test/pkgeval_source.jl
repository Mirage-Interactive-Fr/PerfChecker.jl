@testitem "PkgEval source selection preserves registered and candidate provenance" begin
    using TOML, UUIDs
    include(joinpath(@__DIR__, "..", "qualification", "shared", "pkgeval_source.jl"))
    source = PkgEvalSource
    tree, newer_tree, revision = repeat("a", 40), repeat("b", 40), repeat("c", 40)
    versions = Dict("1.0.0" => Dict("git-tree-sha1" => tree),
        "1.0.1" => Dict("git-tree-sha1" => newer_tree),
        "1.1.0" => Dict("git-tree-sha1" => tree, "yanked" => true))
    selected = source.registered_source(versions)
    @test selected["source_kind"] == "registered"
    @test selected["version"] == "1.0.1"
    @test selected["registered_tree"] == newer_tree
    @test source.registered_source(versions; package_version = "1.0.0",
        expected_tree = tree)["registered_tree"] == tree
    @test_throws ArgumentError source.registered_source(versions; package_version = "1.1.0")
    @test_throws ArgumentError source.registered_source(versions; package_version = "2.0.0")
    @test_throws ArgumentError source.registered_source(versions; expected_tree = tree)
    @test_throws ArgumentError source.registered_source(Dict())
    @test_throws ArgumentError source.registered_source(
        Dict("1.0.0" => Dict("git-tree-sha1" => "not-a-tree")))
    arguments = source.package_arguments(selected)
    @test arguments == (; name = "PerfChecker", uuid = UUID(source.PACKAGE_UUID),
        version = v"1.0.1")
    @test !haskey(arguments, :url) && !haskey(arguments, :rev)

    commit = Dict("sha" => revision, "tree" => tree)
    project = Dict("name" => "PerfChecker", "uuid" => source.PACKAGE_UUID,
        "version" => "1.1.0")
    candidate = source.candidate_source(revision, commit, project)
    @test candidate["source_kind"] == "git_candidate"
    @test candidate["version"] == "1.1.0"
    @test candidate["candidate_revision"] == revision
    @test candidate["candidate_tree"] == tree
    @test !haskey(candidate, "registered_tree")
    # A TOML receipt preserves the selectors used by the evaluation job.
    restored = TOML.parse(sprint(io -> TOML.print(io, candidate; sorted = true)))
    arguments = source.package_arguments(restored)
    @test arguments == (; name = "PerfChecker", uuid = UUID(source.PACKAGE_UUID),
        url = source.PACKAGE_REPOSITORY, rev = revision)
    @test !haskey(arguments, :version)
    @test_throws ArgumentError source.candidate_source("main", commit, project)
    @test_throws ArgumentError source.candidate_source(uppercase(revision), commit, project)
    @test_throws ArgumentError source.candidate_source(revision,
        merge(commit, Dict("sha" => newer_tree)), project)
    @test_throws ArgumentError source.candidate_source(revision,
        merge(commit, Dict("tree" => "broken")), project)
    @test_throws ArgumentError source.candidate_source(revision, commit,
        merge(project, Dict("name" => "Other")))
    @test_throws ArgumentError source.candidate_source(revision, commit,
        merge(project, Dict("uuid" => "00000000-0000-0000-0000-000000000000")))
    @test_throws ArgumentError source.candidate_source(revision, commit,
        merge(project, Dict("version" => "not-a-version")))
    @test_throws ArgumentError source.candidate_source(revision, commit, project;
        package_version = "1.1.0")
    @test_throws ArgumentError source.candidate_source(revision, commit, project;
        expected_tree = tree)
    @test_throws ArgumentError source.package_arguments(
        merge(candidate, Dict("source_repository" => "https://example.org/other.git")))
    @test_throws ArgumentError source.package_arguments(
        merge(candidate, Dict("source_kind" => "unknown")))
    @test_throws ArgumentError source.package_arguments(
        merge(candidate, Dict("uuid" => "00000000-0000-0000-0000-000000000000")))
end
