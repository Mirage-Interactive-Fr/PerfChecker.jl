using TestItemRunner
@run_package_tests filter = ti -> !(:perf_only in ti.tags)
