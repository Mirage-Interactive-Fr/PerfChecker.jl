@testitem "Terminated workers release their connections" tags=[:unit, :worker_cleanup] begin
    using PerfChecker
    for _ in 1:6
        worker = PerfChecker.Worker(; exeflags = ["--threads=1", "--gcthreads=1"])
        @test PerfChecker.remote_eval_fetch(Main, worker, :(1 + 1)) == 2
        PerfChecker.safe_stop(worker)
        @test !Base.process_running(worker.proc)
        @test !isopen(worker.stdout)
        @test !isopen(worker.stderr)
        @test !isopen(worker.current_socket)
        PerfChecker.safe_stop(worker)
        @test !isopen(worker.stdout)
    end
end
