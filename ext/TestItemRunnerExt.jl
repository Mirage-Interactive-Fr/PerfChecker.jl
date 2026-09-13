module TestItemRunnerExt
using PerfChecker, TestItemRunner

function input_fingerprints(root)
    result = Dict{String, String}()
    for (directory, subdirs, files) in walkdir(root; follow_symlinks = false)
        filter!(
            d -> !(d in (".git", ".lab", "node_modules", "results", "build", "compiled")) &&
                !islink(joinpath(directory, d)),
            subdirs)
        for file in files
            (endswith(file, ".jl") || file == "JuliaTestItems.toml") || continue
            full = joinpath(directory, file)
            islink(full) && continue
            result[replace(relpath(full, root), '\\' => '/')] = PerfChecker._sha256_file(full)
        end
    end
    result
end

function PerfChecker.discover_testitems(root::AbstractString = pwd();
        mode::Symbol = :performance, tags = Symbol[], exclude_tags = Symbol[])
    root = abspath(root)
    isdir(root) || throw(ArgumentError("test item root does not exist"))
    accept = PerfChecker.testitem_filter(mode; tags, exclude_tags)
    items = Dict{String, Any}[]
    # Public discovery/filter contract: false prevents item and setup evaluation.
    redirect_stdout(devnull) do
        TestItemRunner.run_tests(root;
            filter = item -> begin
                if accept(item)
                    file = replace(relpath(item.filename, root), '\\' => '/')
                    push!(items,
                        Dict("id" => PerfChecker._content_digest([file, item.name]),
                            "name" => item.name, "file" => file, "tags" => string.(item.tags),
                            "source_sha256" => PerfChecker._sha256_file(item.filename)))
                end
                false
            end)
    end
    allunique(item["id"] for item in items) ||
        throw(ArgumentError("duplicate test item names in one file cannot be selected unambiguously"))
    sort!(items; by = i -> (i["file"], i["name"]))
    Dict("schema_version" => "perfchecker-testitems/1", "root" => root,
        "items" => items, "executed" => false, "mode" => string(mode))
end

function PerfChecker.run_testitems(root::AbstractString = pwd(); ids = nothing,
        tags = Symbol[], exclude_tags = Symbol[],
        project::AbstractString = dirname(Base.active_project()),
        samples::Integer = 1, timeout::Real = 120, threads::Integer = 1,
        reports = nothing, cancellation::PerfChecker.CancellationToken = PerfChecker.CancellationToken())
    samples > 0 || throw(ArgumentError("samples must be positive"))
    listing = PerfChecker.discover_testitems(root; tags, exclude_tags)
    items = listing["items"]
    if ids !== nothing
        allunique(ids) || throw(ArgumentError("duplicate test item selection"))
        known = Set(item["id"] for item in items)
        all(id -> id in known, ids) || throw(ArgumentError("unknown or excluded test item"))
        filter!(item -> item["id"] in ids, items)
    end
    isempty(items) && throw(ArgumentError("no test items selected"))
    reports === nothing || !ispath(joinpath(reports, "testitems.json")) ||
        throw(ArgumentError("testitems report already exists"))
    results = Dict{String, Any}[]
    for item in items
        observations = Dict{String, Any}[]
        for sample in 1:samples
            before = input_fingerprints(listing["root"])
            environment = PerfChecker._environment_provenance(project)
            raw = PerfChecker._scenario_process(
                Dict("root" => listing["root"],
                    "filename" => joinpath(listing["root"], item["file"]),
                    "name" => item["name"], "source_sha256" => item["source_sha256"]);
                project, timeout, cancellation, threads, testitems = true)
            raw["environment_provenance"] = environment
            raw["input_fingerprints"] = before
            if before != input_fingerprints(listing["root"]) ||
               environment != PerfChecker._environment_provenance(project)
                raw["status"] = "invalid"
                raw["message"] = "test sources, discovery configuration or worker environment changed during execution"
            end
            push!(observations, merge(raw, Dict("sample" => sample)))
            get(raw, "status", "error") == "complete" || break
        end
        passed = length(observations) == samples && all(
            r -> get(r, "status", "") == "complete" &&
                get(r, "correctness", "") == "passed",
            observations)
        push!(results,
            Dict("item" => item, "samples" => observations,
                "status" => passed ? "validated" : "not_validated"))
        cancellation.requested[] && break
    end
    result = Dict("schema_version" => "perfchecker-testitem-run/1", "runs" => results,
        "scope" => "test_item_including_setup_imports_assertions_and_module_cleanup",
        "sampling" => "one fresh process per sample; no hidden warmup or repetition",
        "performance" => "not_compared", "root" => listing["root"],
        "passed" => length(results) == length(items) &&
                    all(r -> r["status"] == "validated", results))
    if reports !== nothing
        mkpath(reports)
        open(io -> PerfChecker.JSON.print(io, result, 2),
            joinpath(reports, "testitems.json"), "w")
    end
    result
end
end
