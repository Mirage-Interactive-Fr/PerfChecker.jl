# Windows Job Objects retain ownership when a provider or intermediary exits.
# The child is assigned while suspended; it cannot spawn outside the owned job.
# https://learn.microsoft.com/en-us/windows/win32/procthread/job-objects
struct _WindowsStartupInfo
    size::UInt32
    reserved::Ptr{UInt16}
    desktop::Ptr{UInt16}
    title::Ptr{UInt16}
    position_size::NTuple{7, UInt32}
    flags::UInt32
    show_window::UInt16
    reserved_size::UInt16
    reserved_bytes::Ptr{UInt8}
    input::Ptr{Cvoid}
    output::Ptr{Cvoid}
    error::Ptr{Cvoid}
end

struct _WindowsStartupInfoEx
    startup::_WindowsStartupInfo
    attributes::Ptr{Cvoid}
end

struct _WindowsProcessInformation
    process::Ptr{Cvoid}
    thread::Ptr{Cvoid}
    pid::UInt32
    thread_id::UInt32
end

struct _WindowsJobLimits
    process_time::Int64
    job_time::Int64
    flags::UInt32
    minimum_working_set::UInt
    maximum_working_set::UInt
    active_limit::UInt32
    affinity::UInt
    priority::UInt32
    scheduling::UInt32
    io_counters::NTuple{6, UInt64}
    memory_limits::NTuple{4, UInt}
end

struct _WindowsJobAccounting
    times::NTuple{4, Int64}
    page_faults::UInt32
    total::UInt32
    active::UInt32
    terminated::UInt32
end

mutable struct _WindowsOwnedProcess
    handle::Ptr{Cvoid}
    job::Ptr{Cvoid}
    pid::Int
    exitcode::Int64
    readers::Vector{Base.PipeEndpoint}
    pumps::Vector{Task}
end

_windows_wide(value::AbstractString) = push!(transcode(UInt16, String(value)), 0)

function _windows_environment(command::Cmd)
    command.env === nothing && return nothing
    entries = Dict{String, String}()
    for entry in command.env
        occursin('\0', entry) && throw(ArgumentError("provider environment contains NUL"))
        separator = findfirst(==('='), entry)
        separator === nothing &&
            throw(ArgumentError("provider environment entry has no value"))
        entries[uppercase(entry[1:prevind(entry, separator)])] = entry
    end
    # Preserve the essential variables that Julia/libuv supplies for Cmd(env=...).
    for name in ("HOMEDRIVE", "HOMEPATH", "LOGONSERVER", "PATH", "SYSTEMDRIVE",
        "SYSTEMROOT", "TEMP", "USERDOMAIN", "USERNAME", "USERPROFILE", "WINDIR")
        haskey(entries, name) || !haskey(ENV, name) ||
            (entries[name] = name * "=" * ENV[name])
    end
    return entries
end

function _windows_application(command::Cmd, environment)
    program = first(command.exec)
    directory = isempty(command.dir) ? pwd() : abspath(command.dir)
    directories = if occursin('/', program) || occursin('\\', program)
        [directory]
    else
        entry = environment === nothing ? "PATH=" * get(ENV, "PATH", "") :
                get(environment, "PATH", "PATH=")
        vcat([directory], split(entry[6:end], ';'; keepempty = false))
    end
    suffixes = isempty(splitext(program)[2]) ? ("", ".com", ".exe") : ("",)
    for base in directories, suffix in suffixes
        candidate = abspath(joinpath(directory, base, program * suffix))
        isfile(candidate) && return candidate
    end
    error("provider executable is unavailable")
end

function _windows_require(result, operation)
    result != 0 && return nothing
    code = ccall((:GetLastError, "kernel32"), stdcall, UInt32, ())
    error("$operation failed with Windows error $code")
end

function _windows_close(handle)
    handle == C_NULL && return nothing
    _windows_require(
        ccall((:CloseHandle, "kernel32"), stdcall, Cint,
            (Ptr{Cvoid},), handle),
        "CloseHandle")
end

function _windows_attempt!(errors, action)
    try
        action()
    catch error
        push!(errors, error)
    end
end

function _windows_inherited_handle(handle)
    current = ccall((:GetCurrentProcess, "kernel32"), stdcall, Ptr{Cvoid}, ())
    duplicate = Ref{Ptr{Cvoid}}(C_NULL)
    _windows_require(
        ccall((:DuplicateHandle, "kernel32"), stdcall, Cint,
            (Ptr{Cvoid}, Ptr{Cvoid}, Ptr{Cvoid}, Ref{Ptr{Cvoid}}, UInt32, Cint, UInt32),
            current, handle, current, duplicate, 0, 1, 2),
        "DuplicateHandle")
    return duplicate[]
end

function _windows_active_processes(process::_WindowsOwnedProcess)
    process.job == C_NULL && return 0
    info = Ref(_WindowsJobAccounting(ntuple(_ -> Int64(0), 4), 0, 0, 0, 0))
    _windows_require(
        ccall((:QueryInformationJobObject, "kernel32"), stdcall, Cint,
            (Ptr{Cvoid}, Cint, Ref{_WindowsJobAccounting}, UInt32, Ptr{UInt32}),
            process.job, 1, info, sizeof(_WindowsJobAccounting), C_NULL),
        "QueryInformationJobObject")
    return info[].active
end

function Base.process_running(process::_WindowsOwnedProcess)
    process.handle == C_NULL && return false
    status = ccall((:WaitForSingleObject, "kernel32"), stdcall, UInt32,
        (Ptr{Cvoid}, UInt32), process.handle, 0)
    status == 0 && return false
    status == 0x102 && return true
    _windows_require(0, "WaitForSingleObject")
end

Base.process_exited(process::_WindowsOwnedProcess) = !process_running(process)
Base.getpid(process::_WindowsOwnedProcess) = process.pid

function Base.wait(process::_WindowsOwnedProcess)
    while process_running(process)
        sleep(0.01)
    end
    if process.handle != C_NULL
        status = Ref{UInt32}(0)
        _windows_require(
            ccall((:GetExitCodeProcess, "kernel32"), stdcall, Cint,
                (Ptr{Cvoid}, Ref{UInt32}), process.handle, status),
            "GetExitCodeProcess")
        process.exitcode = Int64(status[])
    end
    return process
end

Base.success(process::_WindowsOwnedProcess) = (wait(process); process.exitcode == 0)

function Base.close(process::_WindowsOwnedProcess)
    errors = Any[]
    for name in (:handle, :job)
        handle = getproperty(process, name)
        handle == C_NULL && continue
        try
            _windows_close(handle)
            setproperty!(process, name, C_NULL)
        catch error
            push!(errors, error)
        end
    end
    for reader in process.readers
        try
            isopen(reader) && close(reader)
        catch error
            push!(errors, error)
        end
    end
    isempty(errors) || throw(CompositeException(errors))
    return nothing
end

function _stop_windows_owned_process(process::_WindowsOwnedProcess)
    errors = Any[]
    try
        if _windows_active_processes(process) > 0
            @warn "Owned Windows provider required forced termination; waiting for its private job"
            _windows_require(
                ccall((:TerminateJobObject, "kernel32"), stdcall, Cint,
                    (Ptr{Cvoid}, UInt32), process.job, 1),
                "TerminateJobObject")
        end
        timedwait(() -> process_exited(process), 5; pollint = 0.01) == :ok ||
            error("owned Windows provider did not exit after shutdown")
        wait(process)
        # Release the leader reference before waiting for all job references to retire.
        _windows_close(process.handle)
        process.handle = C_NULL
        timedwait(() -> _windows_active_processes(process) == 0, 5;
            pollint = 0.01) == :ok ||
            error("owned Windows provider descendants did not exit after shutdown")
        for pump in process.pumps
            timedwait(() -> istaskdone(pump), 5; pollint = 0.01) == :ok ||
                error("owned Windows provider output did not finish draining")
            wait(pump)
        end
    catch error
        push!(errors, error)
    finally
        # KILL_ON_JOB_CLOSE is also the fallback for a failed shutdown.
        _windows_attempt!(errors, () -> close(process))
    end
    if !isempty(errors)
        @error "Owned Windows provider shutdown failed" failures=[sprint(showerror, error)
                                                                  for error in errors]
        throw(CompositeException(errors))
    end
    return nothing
end

function _spawn_windows_owned_process(command::Cmd; stdout, stderr)
    job = C_NULL
    info = Ref(_WindowsProcessInformation(C_NULL, C_NULL, 0, 0))
    pipes = Base.PipeEndpoint[]
    inherited = Ptr{Cvoid}[]
    attribute_storage = UInt8[]
    attributes_ready = false
    job_assigned = false
    try
        isempty(command.exec) && throw(ArgumentError("provider command is empty"))
        any(argument -> occursin('\0', argument), command.exec) &&
            throw(ArgumentError("provider command contains NUL"))
        occursin('\0', command.dir) &&
            throw(ArgumentError("provider directory contains NUL"))
        environment_entries = _windows_environment(command)
        application = _windows_wide(_windows_application(command, environment_entries))
        job = ccall((:CreateJobObjectW, "kernel32"), stdcall, Ptr{Cvoid},
            (Ptr{Cvoid}, Ptr{UInt16}), C_NULL, C_NULL)
        _windows_require(job != C_NULL, "CreateJobObjectW")
        limits = Ref(_WindowsJobLimits(0, 0, 0x2000, 0, 0, 0, 0, 0, 0,
            ntuple(_ -> UInt64(0), 6), ntuple(_ -> UInt(0), 4)))
        _windows_require(
            ccall((:SetInformationJobObject, "kernel32"), stdcall, Cint,
                (Ptr{Cvoid}, Cint, Ref{_WindowsJobLimits}, UInt32),
                job, 9, limits, sizeof(_WindowsJobLimits)),
            "SetInformationJobObject")
        # Only these three handles may be inherited, including during concurrent spawns.
        Base.iolock_begin()
        setup_error = nothing
        try
            null_path = _windows_wide("NUL")
            input = ccall((:CreateFileW, "kernel32"), stdcall, Ptr{Cvoid},
                (Ptr{UInt16}, UInt32, UInt32, Ptr{Cvoid}, UInt32, UInt32, Ptr{Cvoid}),
                null_path, 0x80000000, 3, C_NULL, 3, 0x80, C_NULL)
            _windows_require(input != Ptr{Cvoid}(typemax(UInt)), "CreateFileW(NUL)")
            try
                push!(inherited, _windows_inherited_handle(input))
            finally
                _windows_close(input)
            end
            for _ in 1:2
                reader, writer = Base.link_pipe(true, false)
                endpoint = Base.PipeEndpoint(reader)
                push!(pipes, endpoint)
                try
                    push!(inherited, _windows_inherited_handle(writer))
                finally
                    _windows_close(writer)
                end
            end
            required = Ref{Csize_t}(0)
            ccall((:InitializeProcThreadAttributeList, "kernel32"), stdcall, Cint,
                (Ptr{Cvoid}, UInt32, UInt32, Ref{Csize_t}), C_NULL, 1, 0, required)
            required[] > 0 || error("Windows process handle-list size is unavailable")
            resize!(attribute_storage, required[])
            _windows_require(
                ccall((:InitializeProcThreadAttributeList, "kernel32"),
                    stdcall, Cint, (Ptr{UInt8}, UInt32, UInt32, Ref{Csize_t}),
                    attribute_storage, 1, 0, required),
                "InitializeProcThreadAttributeList")
            attributes_ready = true
            _windows_require(
                ccall((:UpdateProcThreadAttribute, "kernel32"),
                    stdcall, Cint,
                    (Ptr{UInt8}, UInt32, UInt, Ptr{Ptr{Cvoid}},
                        Csize_t, Ptr{Cvoid}, Ptr{Csize_t}),
                    attribute_storage, 0, 0x20002, inherited,
                    sizeof(Ptr{Cvoid}) * length(inherited), C_NULL, C_NULL),
                "UpdateProcThreadAttribute(HANDLE_LIST)")
            startup = Ref(_WindowsStartupInfoEx(
                _WindowsStartupInfo(sizeof(_WindowsStartupInfoEx),
                    C_NULL, C_NULL, C_NULL, ntuple(_ -> UInt32(0), 7),
                    0x100, 0, 0, C_NULL, inherited...), pointer(attribute_storage)))
            line = _windows_wide(command.flags &
                                 Base.UV_PROCESS_WINDOWS_VERBATIM_ARGUMENTS != 0 ?
                                 join(command.exec, ' ') :
                                 Base.escape_microsoft_c_args(command.exec...))
            environment = environment_entries === nothing ? UInt16[] :
                          _windows_wide(join(
                [environment_entries[name]
                 for name in sort(collect(keys(environment_entries)))],
                '\0') * '\0')
            directory = isempty(command.dir) ? UInt16[] : _windows_wide(command.dir)
            flags = UInt32(0x00000400 | 0x00080000 | 0x00000004) # Unicode, extended, suspended.
            command.flags & Base.UV_PROCESS_WINDOWS_HIDE != 0 && (flags |= 0x08000000)
            GC.@preserve inherited attribute_storage begin
                _windows_require(
                    ccall((:CreateProcessW, "kernel32"), stdcall, Cint,
                        (Ptr{UInt16}, Ptr{UInt16}, Ptr{Cvoid}, Ptr{Cvoid}, Cint, UInt32,
                            Ptr{UInt16}, Ptr{UInt16}, Ref{_WindowsStartupInfoEx},
                            Ref{_WindowsProcessInformation}),
                        application, line, C_NULL, C_NULL, 1, flags,
                        isempty(environment) ? C_NULL : environment,
                        isempty(directory) ? C_NULL : directory, startup, info),
                    "CreateProcessW")
            end
            _windows_require(
                ccall((:AssignProcessToJobObject, "kernel32"), stdcall, Cint,
                    (Ptr{Cvoid}, Ptr{Cvoid}), job, info[].process),
                "AssignProcessToJobObject")
            job_assigned = true
            result = ccall((:ResumeThread, "kernel32"), stdcall, UInt32,
                (Ptr{Cvoid},), info[].thread)
            _windows_require(result != typemax(UInt32), "ResumeThread")
        catch error
            setup_error = error
            rethrow()
        finally
            cleanup_errors = Any[]
            try
                if attributes_ready
                    _windows_attempt!(cleanup_errors,
                        () -> GC.@preserve attribute_storage ccall(
                            (:DeleteProcThreadAttributeList, "kernel32"), stdcall, Cvoid,
                            (Ptr{UInt8},), attribute_storage))
                end
                for handle in inherited
                    _windows_attempt!(cleanup_errors, () -> _windows_close(handle))
                end
                _windows_attempt!(cleanup_errors, () -> _windows_close(info[].thread))
            finally
                Base.iolock_end()
            end
            if !isempty(cleanup_errors)
                setup_error === nothing || pushfirst!(cleanup_errors, setup_error)
                @error "Owned Windows spawn resource cleanup failed" failures=[sprint(
                                                                                   showerror,
                                                                                   error)
                                                                               for error in cleanup_errors]
                throw(CompositeException(cleanup_errors))
            end
        end
        pumps = Task[]
        for (reader, output) in zip(pipes, (stdout, stderr))
            push!(pumps, @async while !eof(reader)
                write(output, readavailable(reader))
            end)
        end
        return _WindowsOwnedProcess(info[].process, job, Int(info[].pid), -1, pipes, pumps)
    catch primary
        errors = Any[]
        if info[].process != C_NULL
            _windows_attempt!(errors,
                () -> _windows_require(
                    job_assigned ?
                    ccall((:TerminateJobObject, "kernel32"), stdcall, Cint,
                        (Ptr{Cvoid}, UInt32), job, 1) :
                    ccall((:TerminateProcess, "kernel32"), stdcall, Cint,
                        (Ptr{Cvoid}, UInt32), info[].process, 1),
                    "Terminate failed provider setup"))
            _windows_attempt!(errors,
                () -> begin
                    status = ccall((:WaitForSingleObject, "kernel32"), stdcall, UInt32,
                        (Ptr{Cvoid}, UInt32), info[].process, 5000)
                    status == 0 || error("provider setup process did not finish shutdown")
                end)
            _windows_attempt!(errors, () -> _windows_close(info[].process))
        end
        _windows_attempt!(errors, () -> _windows_close(job))
        for pipe in pipes
            _windows_attempt!(errors, () -> close(pipe))
        end
        if !isempty(errors)
            @error "Owned Windows provider setup cleanup failed" failures=[sprint(
                                                                               showerror,
                                                                               error)
                                                                           for error in errors]
            pushfirst!(errors, primary)
            throw(CompositeException(errors))
        end
        rethrow(primary)
    end
end
