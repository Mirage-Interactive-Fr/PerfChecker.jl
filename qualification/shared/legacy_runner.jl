using TestItemRunner
TestItemRunner.run_tests(@__DIR__; filter = ti -> ti.name == "Feature and software suites")
