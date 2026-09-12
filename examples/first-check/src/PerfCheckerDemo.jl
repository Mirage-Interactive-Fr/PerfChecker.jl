module PerfCheckerDemo
export parse_total

"Parse comma-separated integers and return their sum; an empty input has sum zero."
function parse_total(text::AbstractString)
    isempty(text) && return 0
    return sum(token -> parse(Int, strip(token)), split(text, ','))
end
end
