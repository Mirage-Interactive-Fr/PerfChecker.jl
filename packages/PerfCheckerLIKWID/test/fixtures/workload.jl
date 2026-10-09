using CounterFixture
function record(phase)
    path = get(ENV, "COUNTER_LIFECYCLE_FILE", "")
    isempty(path) || open(io -> println(io, phase), path, "a")
end
perf_setup() = (record("prepare"); [1, 2, 3, 4])
perf_workload(state) = (record("operation"); CounterFixture.sum_squares(state))
perf_synchronize(state, result) = record("synchronize")
function perf_oracle(state, result)
    (record("oracle");
    result == 30 &&
        get(ENV, "COUNTER_ORACLE_FALSE", "false") != "true")
end
perf_cleanup(state) = record("cleanup")
