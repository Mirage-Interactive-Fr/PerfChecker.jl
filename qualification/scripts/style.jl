using JuliaFormatter

root = normpath(joinpath(@__DIR__, "../.."))
files = split(
    read(`git -C $root ls-files --cached --others --exclude-standard -- "*.jl"`, String),
    '\n'; keepempty = false)
unformatted = String[]
for relative in sort!(unique(files))
    path = joinpath(root, relative)
    isfile(path) || continue
    JuliaFormatter.format_file(path; overwrite = false) || push!(unformatted, relative)
end
isempty(unformatted) || error("Julia formatting differs: " * join(unformatted, ", "))
println("Julia source formatting passed")
