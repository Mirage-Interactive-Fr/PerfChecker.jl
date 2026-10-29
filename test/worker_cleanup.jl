@testitem "Terminated workers release their connections" tags=[:unit, :worker_cleanup] begin
    using PerfChecker
    for _ in 1:6
        worker = PerfChecker.Worker(; exeflags = ["--threads=1", "--gcthreads=1"])
        @test PerfChecker.remote_eval_fetch(Main, worker, :(1 + 1)) == 2
        report = PerfChecker.safe_stop(worker)
        @test report.complete
        @test report.process_exited
        @test report.exitcode == 0
        @test report.termsignal == 0
        @test report.tasks_done
        @test report.pending_replies == 0
        @test isempty(report.errors)
        @test isempty(worker.expected_replies)
        @test all(entry -> istaskdone(last(entry)), worker.state.tasks)
        @test all(entry -> !istaskfailed(last(entry)), worker.state.tasks)
        running = Base.process_running(worker.proc)
        @test !running
        @test !isopen(worker.stdout)
        @test !isopen(worker.stderr)
        @test !isopen(worker.current_socket)
        repeated = PerfChecker.safe_stop(worker)
        @test repeated.complete
        @test repeated.pid == report.pid
        @test repeated.exitcode == report.exitcode
        @test repeated.termsignal == report.termsignal
        @test !isopen(worker.stdout)
    end
end

@testitem "Worker qualification rejects an abnormal reaped exit" tags=[
    :integration, :worker_cleanup, :check_shutdown] begin
    using PerfChecker

    worker = PerfChecker.Worker(; exeflags = ["--threads=1", "--gcthreads=1"])
    pid = Int(getpid(worker.proc))
    failure = nothing
    try
        # Registration completes by a real RPC before shutdown invokes exit.
        @test PerfChecker.remote_eval_fetch(Main, worker, quote
            atexit(() -> exit(17))
            :registered
        end) === :registered
        failure = try
            PerfChecker.safe_stop(worker)
            nothing
        catch error
            error
        end
        @test failure isa PerfChecker.WorkerShutdownFailure
        report = failure.report
        @test report.pid == pid
        @test report.complete
        @test report.process_exited
        @test report.exitcode == 17
        @test report.termsignal == 0
        @test report.tasks_done
        @test report.pending_replies == 0
        @test report.socket_closed
        @test report.stdout_closed
        @test report.stderr_closed
        @test isempty(worker.expected_replies)
        @test all(entry -> istaskdone(last(entry)), worker.state.tasks)
        running = Base.process_running(worker.proc)
        @test !running
        # Repetition must not reinterpret an already reaped abnormal process as
        # a new successful zero exit merely because its handles are closed.
        repeated = try
            PerfChecker.safe_stop(worker)
            nothing
        catch error
            error
        end
        @test repeated isa PerfChecker.WorkerShutdownFailure
        @test repeated.report.exitcode == 17
        @test repeated.report.termsignal == 0
        Sys.islinux() && @test !ispath("/proc/$pid")
    finally
        if Base.process_running(worker.proc)
            # Only this test's real child may need emergency cleanup on failure.
            kill(worker.proc, Base.SIGKILL)
            wait(worker.proc)
        end
        try
            PerfChecker.safe_stop(worker)
        catch error
            error isa PerfChecker.WorkerShutdownFailure || rethrow()
        end
    end
end

@testitem "Worker shutdown does not hide an incomplete deadline" tags=[
    :integration, :worker_cleanup, :check_shutdown] begin
    using PerfChecker
    import Malt

    worker = PerfChecker.Worker(; exeflags = ["--threads=1", "--gcthreads=1"])
    pid = Int(getpid(worker.proc))
    try
        @test PerfChecker.remote_eval_fetch(Main, worker, :(getpid())) == pid
        failure = try
            PerfChecker.safe_stop(worker; timeout = 0)
            nothing
        catch error
            error
        end
        @test failure isa Malt.ShutdownIncompleteException
        @test failure.report.pid == pid
        @test !failure.report.complete
        running = Base.process_running(worker.proc)
        @test running
    finally
        report = PerfChecker.safe_stop(worker)
        @test report.complete
        @test report.exitcode == 0
        @test report.termsignal == 0
        @test report.tasks_done
        @test report.pending_replies == 0
        @test isempty(report.errors)
        @test isempty(worker.expected_replies)
        @test all(entry -> istaskdone(last(entry)), worker.state.tasks)
        Sys.islinux() && @test !ispath("/proc/$pid")
    end
end
