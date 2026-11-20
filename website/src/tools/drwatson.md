# DrWatson

This small configuration cache exercises production followed by reuse:

From `examples/kitchen-sink` in the source checkout, run `julia setup.jl extras`. Then start Julia with `julia --project=.controller/extras` for the code below.

```julia
using PerfChecker, DrWatson
mktempdir() do directory
    calls = Ref(0)
    parameters = Dict("recipe"=>"cache_roundtrip", "revision"=>1)
    producer = p -> begin
        calls[] += 1
        Dict("parameters"=>p, "measurement_executed"=>false)
    end
    first_result, first_path = drwatson_produce_or_load(producer, parameters;
        directory, tag=false)
    second_result, second_path = drwatson_produce_or_load(producer, parameters;
        directory, tag=false)
    @assert first_result == second_result && first_path == second_path
    println((calls[], second_result["measurement_executed"]))
end
```

```@raw html
<p>Observed output: <strong><code>(1, false)</code></strong>. The producer ran once; the second call reused
the saved 6,784-byte cache. The <a href="../examples/tool-recipes/receipts.json">receipt</a>
retains the cache hash. This proves configuration reuse, without claiming a
new measurement or publishing a configuration cache as performance evidence.</p>
```

::: details Cache one measured package feature

From `examples/kitchen-sink`:

```sh
julia setup.jl extras
julia --project=.controller/extras drwatson.jl run datastructures
```

The supplied script uses `drwatson_parameters` and `drwatson_savename` on the
suite plan, then `drwatson_run_suite` for one latest-release heap feature.
It asserts `result["passed"]` before printing its cache filename.
Set `PERFCHECKER_FORCE=true` only when intentionally remeasuring. There is no
separately recorded measured package-cache run in this example.

:::
