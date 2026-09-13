# Choose an interface

All interfaces read the same saved runs; none of them changes what a measurement means.

- Run one item while editing — [VS Code](vscode.md)
- Select workloads and versions in a browser — [Web interface (Oxygen)](web-studio.md)
- Work from a terminal — [REPL](repl-pluto.md)
- Keep an editable notebook — [Pluto](repl-pluto.md)
- Explore or export measured plots — [Makie](visualization.md)
- Put saved measurements in your own docs — [Documenter](documentation.md)

## Which package supplies it

- **PerfChecker** — Julia API, command line, text REPL.
- **PerfCheckerWeb** — Oxygen studio and HTTP endpoints.
- **PerfCheckerPluto** — notebook controls and Pluto launch.
- **PerfCheckerMakie** — Makie figures; WGLMakie adds interactive HTML.
- **VS Code extension** — Testing view, commands, investigation panel.

Load the package that supplies the interface. If two interfaces need conflicting dependencies, put them in separate environments and open the same saved run in each.

See [Installation](../guide/installation.md) for what to add.

```@raw html
<a id="What-to-have-ready"></a>
<a id="Which-package-supplies-each-interface?"></a>
```
