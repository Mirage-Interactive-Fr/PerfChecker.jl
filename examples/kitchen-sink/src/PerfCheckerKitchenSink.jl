module PerfCheckerKitchenSink
using DataStructures
using Random

export events, drain_heap, drain_vector, count_events, recent_events, event_case

# Select the public constructor once, outside measurement. Older releases used
# a lowercase function for the same min-heap operation.
const make_minheap = isdefined(DataStructures, :BinaryMinHeap) ?
    DataStructures.BinaryMinHeap : DataStructures.binary_minheap

"Generate immutable (priority, unique id, category) events from a fixed seed."
function events(n::Integer = 2048; seed::Integer = 42)
    n >= 0 || throw(ArgumentError("event count must be nonnegative"))
    rng = Random.Xoshiro(seed)
    return [(rand(rng, 1:max(n, 1)), i, rand(rng, 1:16)) for i in 1:n]
end

"Build and drain a binary heap; input generation is outside this operation."
function drain_heap(input)
    queue = make_minheap(input)
    output = similar(input, 0)
    sizehint!(output, length(input))
    while !isempty(queue)
        push!(output, pop!(queue))
    end
    return output
end

"A deliberately simple sorted-vector queue with the same output as drain_heap."
function drain_vector(input)
    queue = sort(input)
    output = similar(input, 0)
    sizehint!(output, length(input))
    while !isempty(queue)
        push!(output, popfirst!(queue))
    end
    return output
end

"Count categories using an Accumulator and return an ordinary dictionary."
count_events(input) = Dict(counter(event[3] for event in input))

"Retain the last 64 events in arrival order using a circular buffer."
function recent_events(input)
    buffer = CircularBuffer{eltype(input)}(64)
    append!(buffer, input)
    return collect(buffer)
end

"One oracle-bearing lifecycle shared by correctness tests, scenarios and suite workers."
function event_case(parameters)
    n = Int(get(parameters, "n", 2048))
    input = events(n; seed = Int(get(parameters, "seed", 42)))
    kind = String(get(parameters, "kind", "heap"))
    operation = kind == "heap" ? drain_heap : kind == "vector" ? drain_vector :
                kind == "counter" ? count_events : kind == "buffer" ? recent_events :
                throw(ArgumentError("Choose heap, vector, counter or buffer"))
    expected = if kind in ("heap", "vector")
        sort(input)
    elseif kind == "counter"
        Dict(category => count(e -> e[3] == category, input) for category in unique(e[3] for e in input))
    else
        input[max(1, length(input) - 63):end]
    end
    return (prepare = () -> copy(input), operation = operation,
        verify = (state, result) -> result == expected && state == input)
end
end
