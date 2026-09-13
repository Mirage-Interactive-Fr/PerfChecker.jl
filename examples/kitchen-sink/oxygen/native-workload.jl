include(joinpath(@__DIR__, "service.jl"))
include(joinpath(@__DIR__, "../native/window.jl"))
case = EventService.request_case("heap", parse(Int, get(ENV, "PERFCHECKER_NATIVE_SIZE", "2048")))
run_native_window(case, parse(Int, get(ENV, "PERFCHECKER_NATIVE_REPETITIONS", "10")))
