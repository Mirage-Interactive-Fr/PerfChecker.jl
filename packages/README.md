# PerfChecker interfaces

These are independently installable Julia packages in the PerfChecker repository.
Each depends on the public PerfChecker engine. Loading the engine does not install
or load any of them. Interface sessions and jobs remain explicit; there is no
global active PerfChecker interface.

| Package | Use |
| --- | --- |
| PerfCheckerWeb | Oxygen Studio, HTTP routes and remote agents |
| PerfCheckerPluto | Notebook generation, reactive controls and Pluto launch |
| PerfCheckerMakie | Figures and plot recipes, with optional WGLMakie rendering |

During the RC, install the engine and selected interface from the candidate branch:

```julia
using Pkg
Pkg.add(Pkg.PackageSpec(name="PerfChecker", rev="release/v1.0.0-rc1"))
Pkg.add(Pkg.PackageSpec(
    url="https://github.com/Mirage-Interactive-Fr/PerfChecker.jl",
    rev="release/v1.0.0-rc1", subdir="packages/PerfCheckerWeb"))
using PerfChecker, PerfCheckerWeb
```

Replace the last directory with PerfCheckerPluto or PerfCheckerMakie as needed.
These packages await their first General registrations. Once registered, install
them by name with `Pkg.add`. The CLI and text REPL remain in
PerfChecker. The VS Code client uses the same versioned process protocol.

Use separate controller environments when interfaces require incompatible HTTP
versions. Workers continue to use their own environments; interface dependencies
do not belong in a measurement environment. See `../qualification/README.md` for
the shared test matrix and `../website/` for the autonomous DocumenterVitepress site.
