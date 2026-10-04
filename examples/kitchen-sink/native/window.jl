const CALLGRIND_CLIENT = get(ENV, "PERFCHECKER_CALLGRIND_CLIENT", "")
function native_window(enabled::Bool)
    isempty(CALLGRIND_CLIENT) && return
    if enabled
        ccall((:perfchecker_callgrind_start, CALLGRIND_CLIENT), Cvoid, ())
    else
        ccall((:perfchecker_callgrind_stop, CALLGRIND_CLIENT), Cvoid, ())
    end
    nothing
end
function checked_native_operations(case, repetitions)
    for _ in 1:repetitions
        state = case.prepare()
        @assert case.verify(state, case.operation(state))
    end
end
function run_native_window(case, repetitions)
    checked_native_operations(case, 1)
    native_window(false)
    native_window(true)
    try
        checked_native_operations(case, repetitions)
    finally
        native_window(false)
    end
    println("WORKLOAD_ORACLE_PASSED")
end
