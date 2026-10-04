module SharedCases
using Random
using SharedScenarioDemo

function sorting(parameters)
    n = Int(get(parameters, "n", 1000))
    seed = Int(get(parameters, "seed", 42))
    method = get(parameters, "method", "inplace")
    original = rand(Random.Xoshiro(seed), n)
    expected = sort(original)
    operation = method == "inplace" ? sort_buffer! : sorted_copy
    return (prepare = () -> copy(original), operation = operation,
        verify = (state, result) -> result == expected &&
            (method == "inplace" ? result === state : state == original))
end

function asynchronous(parameters)
    return (prepare = () -> Ref(0),
        operation = state -> (@async begin
            yield()
            state[] = 42
            42
        end),
        synchronize = (state, task) -> wait(task),
        verify = (state, task) -> istaskdone(task) && fetch(task) == 42 && state[] == 42)
end
end
