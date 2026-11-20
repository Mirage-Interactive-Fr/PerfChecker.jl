# Aqua

Check package quality separately from an operation benchmark.

From `examples/kitchen-sink` in the source checkout, run `julia setup.jl analyzers`. Then start Julia with `julia --project=.controller/analyzers` for the code below.

```julia
using PerfChecker
source = Base.find_package("DataStructures")
quality = diagnose(ScenarioCatalog(dirname(dirname(source)), ScenarioSpec[]);
    project=dirname(Base.active_project()), tools=[:aqua], threads=1,
    timeout=180, reports="results/quality")
display(only(quality["records"]))
```

```@raw html
<p>The <a href="../examples/real-packages/datastructures-diagnostics/additional.json">recorded receipt</a> contains Aqua <strong>0.8.16</strong>, <code>status=complete</code>, <strong><code>quality=failed</code></strong>, with unbound type parameters in <code>DefaultDictBase</code>, <code>DefaultDict</code> and <code>DefaultOrderedDict</code>.</p>
```

Execution completion does not mean the package passed its quality checks. Aqua analyzes the installed package, once per package, rather than only the selected operation.
