@testitem "Live callback measurements preserve actual samples lifecycle and qualification" tags=[:unit, :shared_scenarios] begin
    using PerfChecker
    prepared, verified, cleaned = Ref(0), Ref(0), Ref(0)
    case = (; prepare = () -> (prepared[] += 1; [3, 1, 2]),
        operation = values -> sort!(values),
        verify = (values, result) -> (verified[] += 1; result === values && values == [1, 2, 3]),
        cleanup = values -> (cleaned[] += 1; nothing))
    bundles = run_scenario(case; id="live_sort", samples=2,
        qualification=(; workload="test sorting"), qualification_limits="test eval context may lack file provenance")
    @test length(bundles) == 1
    bundle = only(bundles)
    raw = bundle.manifest["scenario_evidence"]
    @test raw["status"] == "complete"
    @test raw["correctness"] == "passed"
    @test length(raw["samples"]) == 2
    @test all(sample["time"] > 0 for sample in raw["samples"])
    @test count(row -> row["metric"] == "julia.wall.time", bundle.observations) == 2
    @test prepared[] == verified[] == cleaned[] >= 2
    @test bundle.manifest["live_qualification"]["scope"] == "in-process;not-isolated"
    @test all(occursin("live-inprocess", definition["context"]["measurement"])
        for definition in bundle.measurement_definitions)
    bad = merge(case, (; verify=(values,result)->false))
    failed = only(run_scenario(bad; id="failed_oracle", samples=1,
        qualification_limits="test eval context"))
    @test failed.manifest["scenario_evidence"]["status"] == "error"
    @test isempty(failed.observations)
    @test prepared[] == cleaned[]
    bad = merge(case, (; operation=values->error("operation failed")))
    failed = only(run_scenario(bad; id="failed_operation", samples=1,
        qualification_limits="test eval context"))
    @test failed.manifest["scenario_evidence"]["status"] == "error"
    @test prepared[] == cleaned[]
    unavailable = merge(case, (; availability=()->(;available=false, reason="test unavailable")))
    failed = only(run_scenario(unavailable; id="unavailable", samples=1,
        qualification_limits="test eval context"))
    @test failed.manifest["scenario_evidence"]["status"] == "unavailable"
    @test_throws ArgumentError run_scenario(case; id="bad", samples=0)
    @test_throws ArgumentError run_scenario(case; id="bad", collectors=())
    @test_throws ArgumentError run_scenario(case; id="bad", collectors=(:profile,))
    @test_throws ArgumentError run_scenario((; operation=identity); id="bad")
    # Failure must release the entry-point lock for subsequent independent work.
    @test only(run_scenario(case; id="recovered", samples=1,
        qualification_limits="test eval context")).manifest["scenario_evidence"]["status"] == "complete"
end

@testitem "Live callbacks detect source drift and reject nesting without generated source" tags=[:unit, :shared_scenarios] begin
    using PerfChecker
    mktempdir() do directory
        path = joinpath(directory, "declared-input.txt")
        write(path, "before")
        changed = Ref(false)
        cleaned = Ref(0)
        case = (; prepare=()->nothing,
            operation=state->begin
                if !changed[]
                    write(path, "after")
                    changed[] = true
                end
                4
            end,
            verify=(state,result)->result==4,
            cleanup=state->(cleaned[]+=1; nothing))
        bundle = only(run_scenario(case; id="drift", samples=1, source_files=(path,),
            qualification_limits="test callbacks are eval-defined"))
        @test bundle.manifest["scenario_evidence"]["status"] == "invalid"
        @test haskey(bundle.manifest["scenario_evidence"], "source_after")
        @test cleaned[] >= 1
    end
    inner = (;prepare=()->nothing, operation=identity, verify=(s,r)->true)
    outer = (; prepare=()->nothing,
        operation=state->run_scenario(inner; id="inner", samples=1, qualification_limits="test eval context"),
        verify=(s,r)->true)
    bundle = only(run_scenario(outer; id="outer", samples=1, qualification_limits="test eval context"))
    @test bundle.manifest["scenario_evidence"]["status"] == "error"
    @test occursin("nested live scenarios", bundle.manifest["scenario_evidence"]["message"])
end

@testitem "Live profile collectors retain raw evidence under explicit exclusive ownership" tags=[:unit, :shared_scenarios] begin
    using PerfChecker
    prepared, cleaned = Ref(0), Ref(0)
    case = (; prepare=()->(prepared[]+=1; Ref(0)),
        operation=state->begin
            values = zeros(Int, 32)
            state[] = sum(values) + 4
            sleep(0.003)
            state[]
        end,
        verify=(state,result)->state[]==result==4,
        cleanup=state->(cleaned[]+=1; nothing))
    bundles = run_scenario(case; id="live_profiles", collectors=(:profile,:profile_alloc),
        samples=2, exclusive_profiles=true, qualification_limits="test eval callback definitions")
    @test length(bundles) == 2
    @test all(b.manifest["scenario_evidence"]["status"]=="complete" for b in bundles)
    @test prepared[] == cleaned[]
    @test haskey(bundles[1].manifest["scenario_evidence"], "cpu_stacks")
    @test haskey(bundles[2].manifest["scenario_evidence"], "allocation_sites")
    @test haskey(bundles[2].manifest["scenario_evidence"], "allocation_profile")
    @test all(b.manifest["live_qualification"]["exclusive_profiles"] for b in bundles)
end

@testitem "Live failures retain owned task cleanup and stop before another collector" tags=[:unit, :shared_scenarios] begin
    using PerfChecker
    P=PerfChecker
    R=P.SharedScenarioRuntime
    mutable struct LiveOwner <: Exception
        native::Union{Nothing,Task}
        gate::Union{Nothing,Channel{Bool}}
        failures::Int
        closes::Int
    end
    Base.isopen(owner::LiveOwner)=owner.native!==nothing
    Base.showerror(io::IO,owner::LiveOwner)=print(io,"owned task fixture")
    function Base.close(owner::LiveOwner)
        owner.native===nothing && return nothing
        owner.closes+=1
        if owner.failures>0
            owner.failures-=1
            error("injected owned task cleanup failure")
        end
        put!(owner.gate,true)
        wait(owner.native)
        owner.native=nothing
        owner.gate=nothing
        return nothing
    end
    owners=LiveOwner[]
    function acquire(failures)
        gate=Channel{Bool}(1)
        task=@async take!(gate)
        owner=LiveOwner(task,gate,failures,0)
        push!(owners,owner)
        return owner
    end
    try
        mktempdir() do project
            prepared=Ref(0)
            latest=Ref{Any}()
            case=(;prepare=()->begin
                    prepared[]+=1
                    owner=acquire(2)
                    latest[]=owner
                    throw(owner)
                end,
                operation=identity,verify=(state,result)->true)
            pending=try
                P.run_scenario(case;id="owned_prepare",collectors=(:benchmark,:chairmark),
                    samples=1,project,qualification_limits="task-owning failure fixture; no manifest")
            catch error
                error
            end
            @test pending isa R.PendingScenarioCleanup
            owner=latest[]
            task=owner.native
            @test prepared[]==1 # Second collector must not start.
            @test isopen(pending) && !istaskdone(task)
            @test length(pending.owners)==1
            @test occursin("owned task fixture",sprint(showerror,pending))
            @test_throws R.PendingScenarioCleanup close(pending)
            @test isopen(pending) && owner.native===task
            @test !isempty(pending.retry_failures)
            close(pending)
            @test istaskdone(task) && !isopen(pending)
            @test owner.native===nothing && owner.gate===nothing
            @test close(pending)===nothing && owner.closes==3

            released=Ref{Any}()
            recovered=merge(case,(;prepare=()->begin
                owner=acquire(0);released[]=owner;throw(owner)
            end))
            bundle=only(P.run_scenario(recovered;id="recovered_prepare",samples=1,project,
                qualification_limits="task-owning failure fixture; no manifest"))
            raw=bundle.manifest["scenario_evidence"]
            @test raw["status"]=="error"
            @test raw["cleanup_recovery"]["attempted"]==1
            @test raw["cleanup_recovery"]["released"]==1
            @test raw["cleanup_recovery"]["pending"]==0
            @test !isopen(released[])
            ordinary=(;prepare=()->nothing,operation=state->error("ordinary failure"),verify=(s,r)->true)
            normal=only(P.run_scenario(ordinary;id="ordinary_failure",samples=1,project,
                qualification_limits="ordinary failure fixture; no manifest"))
            @test normal.manifest["scenario_evidence"]["status"]=="error"
            @test !haskey(normal.manifest["scenario_evidence"],"cleanup_recovery")
            @test isempty(normal.observations)

            state_owner=Ref{Any}()
            state_case=(;prepare=()->begin
                    state=acquire(1);state_owner[]=state;state
                end,
                operation=state->error("state operation failure"),verify=(s,r)->true,
                cleanup=state->close(state))
            pending=try
                P.run_scenario(state_case;id="state_cleanup",samples=1,project,
                    qualification_limits="state-owned task fixture; no manifest")
            catch error
                error
            end
            @test pending isa R.PendingScenarioCleanup
            action=only(pending.owners)
            evaluation=action.evaluation
            state_task=state_owner[].native
            @test !evaluation.closed && !istaskdone(state_task)
            @test state_owner[].closes==1
            close(pending)
            @test evaluation.closed && istaskdone(state_task)
            @test action.evaluation===nothing && state_owner[].native===nothing
        end

        # Known composite cause order is preserved; an unresolved earlier owner
        # prevents unsafe disposal of a later, potentially parent owner.
        first,second=acquire(1),acquire(0)
        wrapped=CompositeException(Any[CapturedException(first,backtrace()),R.ScenarioFailure(:cleanup,second)])
        pending=try P.recover_scenario_exception!(wrapped) catch error;error end
        @test pending isa R.PendingScenarioCleanup
        @test isopen(second) && isopen(first)
        @test pending.original===wrapped
        close(pending)
        @test !isopen(first) && !isopen(second)
        struct OpaqueFailure <: Exception
            hidden::Any
        end
        hidden=acquire(0)
        @test P.recover_scenario_exception!(OpaqueFailure(hidden)).attempted==0
        @test isopen(hidden)
        close(hidden)

        state=Ref(0)
        cleanups=Ref(0)
        both=(;prepare=()->state,operation=s->error("primary operation"),
            verify=(s,r)->true,cleanup=s->begin
                cleanups[]+=1
                cleanups[]==1 && error("secondary cleanup")
                s[]=-1
            end)
        aggregate=try R.once(both) catch error;error end
        @test aggregate isa R.PendingScenarioCleanup
        action=only(aggregate.owners)
        evaluation=action.evaluation
        @test !evaluation.closed && cleanups[]==1
        @test occursin("primary operation",sprint(showerror,aggregate))
        @test occursin("secondary cleanup",sprint(showerror,aggregate))
        close(aggregate)
        @test evaluation.closed && cleanups[]==2 && state[] == -1
        @test action.evaluation===nothing

        dependency=acquire(1)
        dependency_task=dependency.native
        parent_closed=Ref(false)
        ordered=(;prepare=()->nothing,operation=state->throw(dependency),
            verify=(s,r)->true,cleanup=state->begin
                isopen(dependency) && error("unsafe parent disposal")
                parent_closed[]=true
            end)
        pending=try R.once(ordered) catch error;error end
        @test pending isa R.PendingScenarioCleanup
        @test !parent_closed[] && !istaskdone(dependency_task)
        close(pending)
        @test parent_closed[] && istaskdone(dependency_task)
    finally
        for owner in owners
            owner.failures=0
            close(owner)
        end
    end
end
