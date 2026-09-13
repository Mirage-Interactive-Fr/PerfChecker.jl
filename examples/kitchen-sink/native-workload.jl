include(joinpath(@__DIR__, "src/PerfCheckerKitchenSink.jl"))
include(joinpath(@__DIR__, "native/window.jl"))
case = PerfCheckerKitchenSink.event_case(Dict("kind" => "heap",
    "n" => parse(Int, get(ENV, "PERFCHECKER_NATIVE_SIZE", "2048"))))
run_native_window(case, parse(Int, get(ENV, "PERFCHECKER_NATIVE_REPETITIONS", "10")))
