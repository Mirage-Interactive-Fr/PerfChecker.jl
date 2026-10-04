module BackendCases
using Random, Distributed

# The same operation is specialized for ordinary or device arrays.
affine!(state) = (state.output .= muladd.(2.0f0, state.input, 1.0f0); state.output)
function threaded!(state)
    Threads.@threads for i in eachindex(state.input)
        state.output[i] = muladd(2.0f0, state.input[i], 1.0f0)
    end
    state.output
end

function affine(parameters)
    backend = get(parameters, "backend", "cpu")
    n = get(parameters, "n", 4096)
    backend in ("cpu", "threads", "cuda") || error("unsupported example backend")
    cuda = backend == "cuda" ? Base.require(Main, :CUDA) : nothing
    availability = () -> (
        available = cuda === nothing || Base.invokelatest(cuda.functional),
        reason = "CUDA runtime/device is unavailable")
    prepare = function ()
        input = rand(MersenneTwister(42), Float32, n)
        if cuda !== nothing
            input = Base.invokelatest(cuda.cu, input)
        end
        output = similar(input)
        cuda === nothing || Base.invokelatest(cuda.synchronize)
        (input = input, output = output)
    end
    synchronize = (state, result) -> (cuda === nothing ||
        Base.invokelatest(cuda.synchronize);
    nothing)
    cleanup = function (state)
        if cuda !== nothing
            Base.invokelatest(cuda.unsafe_free!, state.input)
            Base.invokelatest(cuda.unsafe_free!, state.output)
        end
        nothing
    end
    (availability = availability, prepare = prepare,
        operation = backend == "threads" ? threaded! : affine!, synchronize = synchronize,
        verify = (state, result) -> Array(result) ==
                                    muladd.(2.0f0, Array(state.input), 1.0f0), cleanup = cleanup)
end

function distributed_sum(parameters)
    n = get(parameters, "n", 4096)
    prepare = function ()
        workers = addprocs(2; exeflags = `--startup-file=no --threads=1`)
        try
            input = collect(1:n)
            (workers = workers, chunks = [input[1:(n ÷ 2)], input[(n ÷ 2 + 1):end]],
                expected = sum(input))
        catch
            rmprocs(workers)
            rethrow()
        end
    end
    operation = state -> sum(fetch.([remotecall(sum, worker, chunk)
                                     for (worker, chunk) in zip(state.workers, state.chunks)]))
    (prepare = prepare, operation = operation,
        verify = (state, result) -> result == state.expected,
        cleanup = state -> rmprocs(state.workers))
end
end
