@testitem "External providers stop their owned process tree before returning" tags=[
    :unit, :protocol] begin
    using PerfChecker
    using Logging

    function alive(pid)
        if Sys.iswindows()
            output = read(ignorestatus(`tasklist /FI $("PID eq $pid") /FO CSV /NH`), String)
            return occursin(",\"$pid\",", output)
        end
        state = strip(read(ignorestatus(`ps -p $pid -o stat=`), String))
        return !isempty(state) && !startswith(state, "Z")
    end

    function stop_fixture(pid)
        if Sys.iswindows()
            run(ignorestatus(`taskkill /PID $pid /T /F`))
        else
            ccall(:kill, Cint, (Cint, Cint), pid, 9)
        end
    end

    mktempdir() do root
        unrelated = run(
            pipeline(ignorestatus(`$(Base.julia_cmd()) --startup-file=no -e 'sleep(120)'`);
                stdout = devnull, stderr = devnull);
            wait = false)
        unrelated_pid = getpid(unrelated)
        owned = Int[]
        ready_seconds = 3.0
        preserved_trace = joinpath(root, "unrelated.mem")
        write(preserved_trace, "existing allocation trace\n")
        try
            modes = [:interrupt, :timeout, :runtime_interrupt, :invalid_result]
            Sys.iswindows() || append!(modes,
                [:invalid_inherited_output, :runtime_inherited_output])
            Sys.iswindows() && append!(modes,
                [:native_owner_exit, :invalid_native_result, :invalid_native_intermediate])
            Sys.iswindows() || push!(modes, :forced_interrupt)
            if network_isolation_capabilities(; probe = true)["supported"]
                push!(modes, :network_interrupt)
                Sys.iswindows() || push!(modes, :network_inherited_output)
            end
            for mode in modes
                directory = joinpath(root, string(mode))
                mkpath(directory)
                pid_file = joinpath(directory, "provider.pid")
                child_file = joinpath(directory, "child.pid")
                child_ready = joinpath(directory, "child.ready")
                grandchild_file = joinpath(directory, "grandchild.pid")
                grandchild_ready = joinpath(directory, "grandchild.ready")
                output_file = joinpath(directory, "output.path")
                identity_file = joinpath(directory, "provider.identity.json")
                late_file = joinpath(directory, "late")
                resisting_file = joinpath(directory, "resisting.pid")
                resisting_ready = joinpath(directory, "resisting.ready")
                resisting_command = ["sh",
                    "-c",
                    "trap '' TERM; printf ready >\"\$PERFCHECKER_FORCE_READY\"; exec sleep 120"]
                inherited_output = mode in (:invalid_inherited_output,
                    :runtime_inherited_output, :network_inherited_output)
                grandchild_code = (mode === :forced_interrupt ?
                                   """
resisting = run(pipeline(ignorestatus(addenv(Cmd($(repr(resisting_command))), "PERFCHECKER_FORCE_READY" => $(repr(resisting_ready))));
    stdin=devnull, stdout=devnull, stderr=devnull); wait=false)
write($(repr(resisting_file)), string(getpid(resisting)))
timedwait(() -> isfile($(repr(resisting_ready))), 60; pollint=0.01) == :ok || error("resisting child did not start")
""" : "") *
                                  "write($(repr(grandchild_ready)), \"ready\"); sleep(120)"
                grandchild_script = joinpath(directory, "grandchild.jl")
                child_script = joinpath(directory, "child.jl")
                julia = joinpath(Sys.BINDIR, Base.julia_exename())
                write(grandchild_script, grandchild_code)
                child_code = """
                    grandchild = run(pipeline(ignorestatus(Cmd($(repr([julia, "--startup-file=no", grandchild_script]))));
                        stdin = devnull, stdout = devnull, stderr = devnull); wait = false)
                    write($(repr(grandchild_file)), string(getpid(grandchild)))
                    timedwait(() -> isfile($(repr(grandchild_ready))), 60; pollint = 0.01) == :ok || error("grandchild did not start")
                    write($(repr(child_ready)), "ready")
                    sleep(120)
                    """
                write(child_script, child_code)
                provider = joinpath(directory, "provider.jl")
                write(provider,
                    """
        child = run(pipeline(ignorestatus(Cmd($(repr([julia, "--startup-file=no", child_script]))));
            stdin = devnull, stdout = $(inherited_output ? "stdout" : "devnull"), stderr = $(inherited_output ? "stderr" : "devnull")); wait = false)
        write($(repr(child_file)), string(getpid(child)))
        timedwait(() -> isfile($(repr(child_ready))), 60; pollint = 0.01) == :ok || error("child did not start")
        output = get(ENV, "PERFCHECKER_OUTPUT", $(repr(joinpath(directory, "runtime-output.json"))))
        write(output, $(repr("{\"incomplete\":true}")))
        write($(repr(output_file)), output)
        write($(repr(pid_file)), string(getpid()))
        $(mode === :invalid_result || inherited_output ? "exit(0)" : "")
        sleep(120)
        write($(repr(late_file)), "must not execute")
        """)
                provider_command = [julia, "--startup-file=no", provider]
                if mode in (:native_owner_exit, :invalid_native_result,
                    :invalid_native_intermediate)
                    # Julia/libuv itself owns a Windows Job Object. A native
                    # provider must also be cleaned up when that protection is absent.
                    powershell_quote(value) = "'" * replace(value, "'" => "''") * "'"
                    if mode === :invalid_native_intermediate
                        child_script = joinpath(directory, "child.ps1")
                        arguments = Base.escape_microsoft_c_args(
                            "--startup-file=no", grandchild_script)
                        write(child_script,
                            """
            \$ErrorActionPreference = 'Stop'
            \$grandchild = Start-Process -FilePath $(powershell_quote(julia)) -ArgumentList $(powershell_quote(arguments)) -NoNewWindow -PassThru -RedirectStandardOutput $(powershell_quote(joinpath(directory, "grandchild.stdout"))) -RedirectStandardError $(powershell_quote(joinpath(directory, "grandchild.stderr")))
            [IO.File]::WriteAllText($(powershell_quote(grandchild_file)), \$grandchild.Id.ToString())
            \$deadline = [DateTime]::UtcNow.AddSeconds(60)
            while (-not (Test-Path -LiteralPath $(powershell_quote(grandchild_ready)))) {
                if ([DateTime]::UtcNow -gt \$deadline) { throw 'grandchild did not start' }
                Start-Sleep -Milliseconds 10
            }
            [IO.File]::WriteAllText($(powershell_quote(child_ready)), 'ready')
            exit 0
            """)
                    end
                    child_arguments = mode === :invalid_native_intermediate ?
                                      ["-NoLogo", "-NoProfile", "-NonInteractive",
                        "-ExecutionPolicy", "Bypass", "-File", child_script] :
                                      ["--startup-file=no", child_script]
                    child_executable = mode === :invalid_native_intermediate ?
                                       "powershell.exe" : julia
                    arguments = Base.escape_microsoft_c_args(child_arguments...)
                    provider = joinpath(directory, "provider.ps1")
                    write(provider,
                        """
            \$ErrorActionPreference = 'Stop'
            \$child = Start-Process -FilePath $(powershell_quote(child_executable)) -ArgumentList $(powershell_quote(arguments)) -NoNewWindow -PassThru -RedirectStandardOutput $(powershell_quote(joinpath(directory, "child.stdout"))) -RedirectStandardError $(powershell_quote(joinpath(directory, "child.stderr")))
            [IO.File]::WriteAllText($(powershell_quote(child_file)), \$child.Id.ToString())
            \$deadline = [DateTime]::UtcNow.AddSeconds(60)
            while (-not (Test-Path -LiteralPath $(powershell_quote(child_ready)))) {
                if ([DateTime]::UtcNow -gt \$deadline) { throw 'child did not start' }
                Start-Sleep -Milliseconds 10
            }
            [IO.File]::WriteAllText(\$env:PERFCHECKER_OUTPUT, '{"incomplete":true}')
            [IO.File]::WriteAllText($(powershell_quote(output_file)), \$env:PERFCHECKER_OUTPUT)
            [IO.File]::WriteAllText($(powershell_quote(identity_file)), ('{"pid":' + \$PID.ToString() + ',"creation_ticks":' + [Diagnostics.Process]::GetCurrentProcess().StartTime.ToUniversalTime().Ticks.ToString() + '}'))
            [IO.File]::WriteAllText($(powershell_quote(pid_file)), \$PID.ToString())
            exit 0
            """)
                    provider_command = ["powershell.exe", "-NoLogo", "-NoProfile",
                        "-NonInteractive", "-ExecutionPolicy", "Bypass", "-File", provider]
                end
                parent_exits = mode in (:invalid_result, :invalid_native_result,
                    :invalid_native_intermediate, :native_owner_exit,
                    :invalid_inherited_output, :runtime_inherited_output,
                    :network_inherited_output)
                source = read(provider)
                failure = Ref{Any}(nothing)
                spec = ExternalCommandSpec(mode, "julia-provider",
                    provider_command;
                    directory, timeout_seconds = mode === :timeout ?
                                                 max(8, 2 * ready_seconds + 2) : 120)
                result = Ref{Any}(nothing)
                owner_tree = Ref{Any}(nothing)
                cleanup_gate = Channel{Nothing}(1)
                owner_ready = Ref(false)
                started = time()
                log_buffer = IOBuffer()
                task = with_logger(SimpleLogger(log_buffer, Logging.Warn)) do
                    @async try
                        result[] = if mode === :native_owner_exit
                            output = IOBuffer()
                            errors = IOBuffer()
                            owner_tree[] = PerfChecker._spawn_owned_process(
                                addenv(Cmd(spec.command),
                                    "PERFCHECKER_OUTPUT" => joinpath(
                                        directory, "native-output.json"));
                                stdout = output, stderr = errors)
                            try
                                timedwait(() -> process_exited(owner_tree[].process),
                                    60; pollint = 0.02) == :ok ||
                                    error("native provider did not exit")
                                owner_ready[] = true
                                take!(cleanup_gate) # The test observes the exited root and live descendants first.
                                PerfChecker._stop_owned_process(owner_tree[])
                            finally
                                PerfChecker._cleanup_owned_process(owner_tree[],
                                    (() -> close(output), () -> close(errors)), nothing)
                            end
                            nothing
                        elseif mode in (:runtime_interrupt, :runtime_inherited_output)
                            PerfChecker._runtime_process(spec.command, 120)
                        elseif mode in (:network_interrupt, :network_inherited_output)
                            measure_isolated_network_command(spec.command;
                                directory, timeout_seconds = 120)
                        else
                            run_external_command(spec)
                        end
                    catch error
                        failure[] = error
                    end
                end
                try
                    @test timedwait(() -> isfile(pid_file) || istaskdone(task), 60;
                        pollint = 0.02) == :ok
                    @test isfile(pid_file)
                    isfile(pid_file) || error("provider fixture stopped before ready: " *
                          (failure[] === nothing ? string(result[].diagnostics) :
                           sprint(showerror, failure[])))
                    mode === :interrupt && (ready_seconds = time() - started)
                    provider_pid = parse(Int, read(pid_file, String))
                    child_pid = parse(Int, read(child_file, String))
                    grandchild_pid = parse(Int, read(grandchild_file, String))
                    append!(owned, [provider_pid, child_pid, grandchild_pid])
                    if !parent_exits
                        @test alive(provider_pid)
                        @test alive(child_pid)
                        @test alive(grandchild_pid)
                    end
                    @test alive(unrelated_pid)
                    @info "Owned command fixture ready" mode provider_pid child_pid grandchild_pid
                    if mode === :native_owner_exit
                        @test timedwait(() -> owner_ready[] || istaskdone(task), 60;
                            pollint = 0.02) == :ok
                        @test owner_ready[]
                        @test !alive(provider_pid)
                        @test alive(child_pid)
                        @test alive(grandchild_pid)
                        identity = PerfChecker._json_parsefile(identity_file)
                        @test identity["pid"] == provider_pid
                        @test identity["creation_ticks"] > 0
                        @info "Native provider exited before owned cleanup" identity
                        put!(cleanup_gate, nothing)
                    end
                    temporary_output = read(output_file, String)
                    parent_exits || @test isfile(temporary_output)
                    if mode !== :timeout && !parent_exits
                        schedule(task, InterruptException(); error = true)
                    end
                    @test timedwait(() -> istaskdone(task), 30; pollint = 0.02) == :ok
                    if mode === :native_owner_exit
                        @test failure[] === nothing
                    elseif mode in (:runtime_inherited_output, :network_inherited_output)
                        @test failure[] === nothing
                        @test result[].exit_code == 0
                        mode === :runtime_inherited_output && @test !result[].timed_out
                    elseif parent_exits
                        @test !alive(provider_pid) # Exit must precede the cleanup oracle.
                        mode === :invalid_native_intermediate && @test !alive(child_pid)
                        @test failure[] isa ArgumentError
                        @test occursin("unsupported provider result schema",
                            sprint(showerror, failure[]))
                    elseif mode !== :timeout
                        @test failure[] isa InterruptException
                        @test result[] === nothing
                    else
                        @test failure[] === nothing
                        @test !bundle_passed(result[])
                        @test occursin("timed out", result[].diagnostics[1]["message"])
                    end
                    # These assertions precede harness teardown, which cannot turn a leaked provider into a pass.
                    @test timedwait(
                        () -> !alive(provider_pid) && !alive(child_pid) &&
                                  !alive(grandchild_pid),
                        2;
                        pollint = 0.02) == :ok
                    @test !alive(provider_pid)
                    @test !alive(child_pid)
                    @test !alive(grandchild_pid)
                    mode in (:runtime_interrupt, :network_interrupt, :native_owner_exit,
                        :runtime_inherited_output, :network_inherited_output) ||
                        @test !ispath(temporary_output)
                    @test !isfile(late_file)
                    @test alive(unrelated_pid)
                    @test read(provider) == source
                    @test read(preserved_trace, String) == "existing allocation trace\n"
                    if mode === :forced_interrupt
                        @test !alive(parse(Int, read(resisting_file, String)))
                        @test occursin(
                            "required forced termination", String(take!(log_buffer)))
                    end
                finally
                    # Only recorded PIDs belonging to this fixture may be stopped after a failing regression.
                    for file in (pid_file, child_file, grandchild_file, resisting_file)
                        if isfile(file)
                            pid = parse(Int, read(file, String))
                            alive(pid) && stop_fixture(pid)
                        end
                    end
                    if !istaskdone(task)
                        schedule(task, InterruptException(); error = true)
                        timedwait(() -> istaskdone(task), 5; pollint = 0.02)
                    end
                end
            end
            if !Sys.iswindows()
                foreign = PerfChecker._OwnedProcessTree(
                    unrelated, Int(unrelated_pid), false)
                @test_throws ErrorException PerfChecker._signal_owned_group(
                    foreign, Base.SIGTERM)
                @test alive(unrelated_pid)
            end
        finally
            for pid in owned
                alive(pid) && stop_fixture(pid)
            end
            process_running(unrelated) && kill(unrelated)
            wait(unrelated)
            close(unrelated)
        end
    end

    if Sys.iswindows()
        mktempdir() do root
            directory = joinpath(root, "workspace 雪 with spaces")
            mkpath(directory)
            provider = joinpath(directory, "streams 雪.jl")
            payload_size = 1024 * 1024
            write(provider, """
                for _ in 1:256
                    write(stdout, repeat("x", 4096))
                    write(stderr, repeat("y", 4096))
                end
                println(stdout, ENV["PERFCHECKER_FIXTURE_VALUE"])
                println(stdout, pwd())
                println(stderr, repr(ARGS))
                exit(7)
                """)
            julia = joinpath(Sys.BINDIR, Base.julia_exename())
            arguments = ["雪 space", "quote\" and slash\\", "\$literal"]
            value = "fixture 雪 \"quoted\" \$literal"
            command = Cmd([julia, "--startup-file=no", provider, arguments...];
                dir = directory, env = Dict("PERFCHECKER_FIXTURE_VALUE" => value))
            output, errors = IOBuffer(), IOBuffer()
            tree = PerfChecker._spawn_owned_process(
                command; stdout = output, stderr = errors)
            try
                @test timedwait(() -> process_exited(tree.process), 60; pollint = 0.02) ==
                      :ok
                PerfChecker._stop_owned_process(tree)
                text = String(take!(output))
                error_text = String(take!(errors))
                @test startswith(text, repeat("x", payload_size))
                @test occursin(value, text)
                @test occursin(directory, text)
                @test startswith(error_text, repeat("y", payload_size))
                @test occursin(repr(arguments), error_text)
                @test tree.process.exitcode == 7
                @test !success(tree.process)
                @test tree.stopped
                @test tree.process.handle == C_NULL
                @test tree.process.job == C_NULL
                @test all(istaskdone, tree.process.pumps)
            finally
                PerfChecker._cleanup_owned_process(tree,
                    (() -> close(output), () -> close(errors)), nothing)
            end

            missing = joinpath(root, "not-an-executable.exe")
            @test_throws ErrorException PerfChecker._spawn_owned_process(Cmd([missing]);
                stdout = devnull, stderr = devnull)
            bad_directory = joinpath(root, "absent directory")
            failed = Cmd([julia, "--startup-file=no", "-e", "exit(0)"];
                dir = bad_directory)
            function handle_count()
                count = Ref{UInt32}(0)
                current = ccall((:GetCurrentProcess, "kernel32"), stdcall, Ptr{Cvoid}, ())
                @test ccall((:GetProcessHandleCount, "kernel32"), stdcall, Cint,
                    (Ptr{Cvoid}, Ref{UInt32}), current, count) != 0
                count[]
            end
            @test_throws ErrorException PerfChecker._spawn_owned_process(failed;
                stdout = devnull, stderr = devnull)
            sleep(0.1) # Retire libuv pipe close callbacks before comparing OS handles.
            before = handle_count()
            for _ in 1:10
                @test_throws ErrorException PerfChecker._spawn_owned_process(failed;
                    stdout = devnull, stderr = devnull)
                sleep(0.02)
            end
            sleep(0.1)
            @test handle_count() <= before + 2
        end
    end

    primary = InterruptException()
    caught = @test_logs (:error, "Owned command cleanup failed") begin
        try
            PerfChecker._cleanup_owned_process(nothing,
                (() -> error("controlled cleanup failure"),), primary)
            nothing
        catch error
            error
        end
    end
    @test caught isa CompositeException
    @test caught.exceptions[1] === primary
    @test occursin("controlled cleanup failure", sprint(showerror, caught.exceptions[2]))
end

@testitem "External provider cleanup failures prevent complete bundle publication" tags=[
    :unit, :protocol] begin
    using PerfChecker

    if Sys.iswindows() || ccall(:geteuid, Cuint, ()) == 0
        @test_skip false # Directory unlink permissions need a non-root POSIX host.
    else
        mktempdir() do root
            temporary = joinpath(root, "readonly-results")
            mkpath(temporary)
            bundles = joinpath(root, "bundles")
            provider = joinpath(root, "provider.jl")
            payload = PerfChecker.JSON.json(Dict(
                "schema_version" => "perfchecker-provider-result/1",
                "suite" => "cleanup", "case_id" => "readonly",
                "runtime" => Dict("language" => "fixture"),
                "measurement_definitions" => [Dict("id" => "custom.work/v1",
                    "metric" => "custom.work", "unit" => "1")],
                "observations" => [Dict("metric" => "custom.work", "value" => 42,
                    "unit" => "1", "measurement_definition" => "custom.work/v1")]))
            write(provider, """
                write(ENV["PERFCHECKER_OUTPUT"], $(repr(payload)))
                chmod(dirname(ENV["PERFCHECKER_OUTPUT"]), 0o555)
                """)
            julia = joinpath(Sys.BINDIR, Base.julia_exename())
            code = "using PerfChecker; spec = ExternalCommandSpec(:readonly, \"fixture\", " *
                   repr([julia, "--startup-file=no", provider]) * "); " *
                   "run_external_command(spec; bundle_root=" * repr(bundles) *
                   ", strict=true)"
            command = addenv(
                Cmd([julia, "--startup-file=no",
                    "--project=$(Base.active_project())", "-e", code]),
                "TMPDIR" => temporary)
            log = IOBuffer()
            try
                process = run(pipeline(ignorestatus(command); stdout = log, stderr = log))
                @test !success(process)
                message = String(take!(log))
                @test occursin("Owned command cleanup failed", message)
                @test occursin("provider result file remained after cleanup", message)
                files = readdir(temporary; join = true)
                @test length(files) == 1
                @test PerfChecker._json_parsefile(only(files))["schema_version"] ==
                      "perfchecker-provider-result/1"
                @test !isdir(bundles) || isempty(readdir(bundles))
            finally
                chmod(temporary, 0o700)
                close(log)
            end
        end
    end
end
