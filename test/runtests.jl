using TestItemRunner

profile = get(ENV, "PERFCHECKER_TEST_PROFILE", "full")
selected_tags = Set(Symbol.(filter(!isempty,
    split(get(ENV, "PERFCHECKER_TEST_TAGS", ""), ','))))
isolated_tags = Set([:oxygen_latest, :wgl])

function selected_testitem(testitem)
    relative = relpath(testitem.filename, dirname(@__DIR__))
    first(splitpath(relative)) in ("src", "ext", "test") || return false
    tags = Set(testitem.tags)
    isempty(selected_tags) && return isempty(isolated_tags ∩ tags)
    requested_isolated = selected_tags ∩ isolated_tags
    if isempty(requested_isolated)
        return isempty(isolated_tags ∩ tags) && !isempty(selected_tags ∩ tags)
    end
    return !isempty(requested_isolated ∩ tags)
end

@run_package_tests filter = ti -> (
    (profile == "full" || :historical ∉ ti.tags) &&
    selected_testitem(ti))
