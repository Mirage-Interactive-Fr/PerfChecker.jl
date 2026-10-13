# Supposition

Freeze generated cases before timing, then replay identical inputs across releases. This small fixture checks integer increment/reversal, rather than package performance.

From `examples/kitchen-sink` in the source checkout, run `julia setup.jl extras`. Then start Julia with `julia --project=.controller/extras` for the code below.

```julia
using PerfChecker, Supposition, Random
mktempdir() do directory
    path = joinpath(directory, "supposition.json")
    Random.seed!(42)
    freeze_supposition_corpus(path, Supposition.Data.Integers(0,10); count=4,
        encode=x -> Dict("value"=>x), metadata=Dict("task_rng_seed"=>42))
    cases = read_property_corpus(path)["cases"]
    replay = [x["value"] + 1 for x in cases]
    @assert all(replay[i] - 1 == cases[i]["value"] for i in eachindex(cases))
    println(replay)
end
```

```@raw html
<p>The <a href="../examples/tool-recipes/supposition-corpus.json">actual frozen corpus</a> and <a href="../examples/tool-recipes/receipts.json">generation/replay receipt</a> retain <strong>7, 7, 1, 6</strong>, replayed as <strong>8, 8, 2, 7</strong>, with <strong>4 checks passed</strong>. This does not claim discovery of a failing property.</p>
```

Supposition uses the explicitly seeded task RNG and requires 64-bit Julia. Use PropCheck or a compatible saved corpus on 32-bit Julia. Preserve the file rather than assuming generator versions reproduce the same values.

::: details Real heap workload

From `examples/kitchen-sink`, prepare `julia setup.jl extras`. The supplied `corpus.jl freeze` / `corpus.jl replay` applies this pattern to 20 heap inputs with the real heap oracle. No separate 20-case package receipt is claimed here. Generation remains outside the timed operation.

:::
