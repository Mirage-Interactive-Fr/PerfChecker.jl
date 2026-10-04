using Downloads, SHA
Sys.islinux() || error("Prepare the native tools in Linux/WSL")
root = joinpath(@__DIR__, ".controller/native")
mkpath(root)
target = joinpath(root, "valgrind-julia-$(VERSION).supp")
url = "https://raw.githubusercontent.com/JuliaLang/julia/v$(VERSION)/contrib/valgrind-julia.supp"
Downloads.download(url, target)
println("Julia runtime suppressions: ", target)
println("Source: ", url)
println("SHA256: ", bytes2hex(sha256(read(target))))
compiler = Sys.which("cc")
if compiler !== nothing
    source = joinpath(@__DIR__, "native/callgrind-window.c")
    library = joinpath(root, "callgrind-window.so")
    run(`$compiler -shared -fPIC -O2 $source -o $library`)
    println("Callgrind warm-workload control: ", library)
else
    println("No C compiler found: Callgrind will retain whole-process scope")
end
