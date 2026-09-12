using PerfCheckerQualification, TOML

root = normpath(joinpath(@__DIR__, "../.."))
plan = TOML.parsefile(get(
    ENV, "PERFCHECKER_PLAN", joinpath(root, ".qualification/plan.toml")))
receipts = Dict{String, Any}[]
for lane in plan["lanes"]
    folder = joinpath(root, ".qualification/results", lane["id"])
    receipt = TOML.parsefile(joinpath(folder, "receipt.toml"))
    for environment in receipt["environments"], (_, record) in environment
        record isa AbstractDict || continue
        name = record["file"]
        basename(name) == name || error("Evidence must remain inside its lane")
        file_digest(joinpath(folder, name)) == record["sha256"] ||
            error("Altered environment evidence")
    end
    push!(receipts, receipt)
end
result = validate_receipts(plan, receipts; require_full = "--publish" in ARGS)
if "--publish" in ARGS
    site = joinpath(root, "website/build/site")
    docs = only(filter(r -> haskey(r, "site_sha256"), receipts))
    tree_digest(site) == docs["site_sha256"] ||
        error("Site differs from the tested artifact")
end
write_toml(joinpath(root, ".qualification/collection.toml"), result)
println(result["publishable"] ? "Full collection qualified" :
        "Impacted components passed; publication is not qualified")
