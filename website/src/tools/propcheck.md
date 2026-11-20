# PropCheck

Freeze generated cases before timing, then replay identical inputs across releases. This small fixture checks integer increment/reversal, rather than package performance.

From `examples/kitchen-sink` in the source checkout, run `julia setup.jl extras`. Then start Julia with `julia --project=.controller/extras` for the code below.

```julia
using PerfChecker, PropCheck, Random
mktempdir() do directory
    path = joinpath(directory, "propcheck.json")
    freeze_propcheck_corpus(path, PropCheck.itype(Int8); count=4, seed=42,
        encode=x -> Dict("value"=>Int(x)))
    cases = read_property_corpus(path)["cases"]
    replay = [x["value"] + 1 for x in cases]
    @assert all(replay[i] - 1 == cases[i]["value"] for i in eachindex(cases))
    println(replay)
end
```

```@raw html
<p>The <a href="../examples/tool-recipes/propcheck-corpus.json">actual frozen corpus</a> and <a href="../examples/tool-recipes/receipts.json">generation/replay receipt</a> retain <strong>−95, 115, 122, −76</strong>, replayed as <strong>−94, 116, 123, −75</strong>, with <strong>4 checks passed</strong>. This does not claim discovery of a failing property.</p>
```

PropCheck uses an adapter-owned seeded RNG. Preserve the file rather than assuming generator versions reproduce the same values.

::: details Real heap workload

From `examples/kitchen-sink`, prepare `julia setup.jl extras`. The supplied `corpus.jl freeze` / `corpus.jl replay` applies this pattern to 20 heap inputs with the real heap oracle. No separate 20-case package receipt is claimed here. Generation remains outside the timed operation.

:::
