module PortableKernelCases
using KernelAbstractions, Random

@kernel function affine_kernel!(output, input)
    i = @index(Global, Linear)
    output[i] = muladd(2.0f0, input[i], 1.0f0)
end

function affine(parameters)
    selected = get(parameters, "backend", "cpu")
    selected in ("cpu", "cuda") || error("unsupported kernel backend")
    cuda = selected == "cuda" ? Base.require(Main, :CUDA) : nothing
    n = get(parameters, "n", 4096)
    n isa Integer && n > 0 || error("n must be positive")
    prepare = function ()
        input = rand(MersenneTwister(42), Float32, n)
        cuda === nothing || (input = Base.invokelatest(cuda.cu, input))
        output = similar(input)
        backend = get_backend(input)
        synchronize(backend)
        (input = input, output = output, backend = backend,
            kernel = affine_kernel!(backend, 64))
    end
    operation = state -> (state.kernel(
        state.output, state.input; ndrange = length(state.input));
    state.output)
    cleanup = function (state)
        synchronize(state.backend)
        if cuda !== nothing
            Base.invokelatest(cuda.unsafe_free!, state.input)
            Base.invokelatest(cuda.unsafe_free!, state.output)
        end
    end
    (
        availability = () -> (
            available = cuda === nothing || Base.invokelatest(cuda.functional),
            reason = "CUDA runtime/device unavailable"),
        prepare = prepare, operation = operation,
        synchronize = (state, result) -> synchronize(state.backend),
        verify = (state, result) -> Array(result) ==
                                    muladd.(2.0f0, Array(state.input), 1.0f0), cleanup = cleanup)
end
end
