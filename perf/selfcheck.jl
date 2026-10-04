# Lightweight, repeatable self-measurement. Run with --project=<PerfChecker checkout>.
using PerfChecker
using SHA

mktempdir() do root
    mkpath(joinpath(root, "src"))
    source = join(["f$i(x) = sum(abs2, x) + $i" for i in 1:2000], "\n") *
             "\nusing Test\n@testset \"sample\" begin\n@test f1([1,2]) == 6\nend\n"
    write(joinpath(root, "src", "fixture.jl"), source)
    for _ in 1:2
        discover(root)
    end
    samples = [@timed discover(root) for _ in 1:7]
    @assert all(length(sample.value["candidates"]) == 1 for sample in samples)
    println(PerfChecker._canonical_json(Dict(
        "schema_version" => "perfchecker-selfcheck/1", "julia" => string(VERSION),
        "fixture_sha256" => bytes2hex(sha256(source)),
        "operation" => "static discovery of 2000 functions and one assertion",
        "bytes" => [s.bytes for s in samples], "seconds" => [s.time for s in samples],
        "oracle" => "one assertion discovered in every sample")))
end
