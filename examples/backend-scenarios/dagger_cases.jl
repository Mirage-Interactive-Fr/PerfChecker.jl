module DaggerCases
using Dagger
function reduction(parameters)
    n = get(parameters, "n", 4096)
    n isa Integer && n >= 2 || error("n must be at least two")
    prepare = () -> (chunks = [collect(1:(n ÷ 2)), collect((n ÷ 2 + 1):n)],
        tasks = Any[], expected = n * (n + 1) ÷ 2)
    operation = function (state)
        for chunk in state.chunks
            push!(state.tasks, Dagger.spawn(sum, chunk))
        end
        combined = Dagger.spawn(+, state.tasks...)
        push!(state.tasks, combined)
        fetch(combined)
    end
    cleanup = function (state)
        # Drain every scheduled task even if one of the fetches failed.
        for task in state.tasks
            try
                wait(task)
            catch
            end
        end
        empty!(state.tasks)
    end
    (prepare = prepare, operation = operation,
        verify = (state, result) -> result == state.expected, cleanup = cleanup)
end
end
