# A single SMT factor is meaningful only when every observed core has the same
# number of processing units. Hybrid CPUs can have both one and two per core.
function _topology_corecount(logical::Int, threads_per_core::AbstractVector{<:Integer})
    physical = length(threads_per_core)
    uniform = physical > 0 && all(>(0), threads_per_core) &&
              sum(threads_per_core) == logical &&
              all(==(first(threads_per_core)), threads_per_core)
    return (physical, logical, uniform ? Int(first(threads_per_core)) : 0)
end

function _hardware_corecount(;
        topology = () -> Hwloc.gettopology(; reload = true, io = false),
        logical_threads::Int = Sys.CPU_THREADS)
    fallback = (0, logical_threads, 0)
    try
        tree = topology()
        logical = length(Hwloc.collectobjects(:PU, tree))
        logical > 0 || return fallback
        cores = Hwloc.collectobjects(:Core, tree)
        per_core = [length(Hwloc.collectobjects(:PU, core)) for core in cores]
        return _topology_corecount(logical, per_core)
    catch error
        error isa InterruptException && rethrow()
        # Topology is optional metadata. Keep Julia's OS logical count if the
        # native topology query fails, without guessing physical cores or SMT.
        return fallback
    end
end

"""
    HwInfo(; reload=true)

Capture Julia's native CPU identity and Hwloc's physical/logical CPU topology.
`reload=true` refreshes Hwloc's cached topology, without querying I/O devices;
`reload=false` reuses the existing topology if available. Counts describe the
topology exposed by the OS, not an enforced CPU quota.
`simdbytes == 0` means unknown SIMD width. The third entry of `corecount` is zero
when threads per core are unknown or heterogeneous, rather than an average.
If the topology query fails, use `(0, Sys.CPU_THREADS, 0)`: zero physical cores
and threads per core mean unknown. This applies to x86 (including Linux32)
as well as ARM. Saved snapshots retain their recorded values.
"""
struct HwInfo
    cpus::Vector{CPUinfo}
    machine::String
    word::Int
    simdbytes::Int
    corecount::Tuple{Int, Int, Int}
end
function HwInfo(; reload::Bool = true)
    corecount = _hardware_corecount(;
        topology = () -> Hwloc.gettopology(; reload, io = false))
    return HwInfo(cpu_info(), CPU_NAME, WORD_SIZE, 0, corecount)
end

# Function to convert HwInfo to a dictionary for JSON serialization
function hwinfo_to_dict(hwinfo::HwInfo)
    return Dict(
        "cpus" => hwinfo.cpus,
        "machine" => hwinfo.machine,
        "word" => hwinfo.word,
        "simdbytes" => hwinfo.simdbytes,
        "corecount" => hwinfo.corecount
    )
end

# Function to write HwInfo and UUID to a JSON file
function write_hwinfo_to_json(hwinfo::HwInfo, u::UUID; path::String = "")
    filename = joinpath(path, "$(u).json")
    hwinfo_dict = hwinfo_to_dict(hwinfo)
    hwinfo_dict["uuid"] = string(u)

    # Write to the JSON file
    open(filename, "w") do io
        JSON.print(io, hwinfo_dict)
    end
end

# Helper function to convert a dictionary back to CPUinfo
function dict_to_cpuinfo(dict::AbstractDict)
    return CPUinfo(
        dict["model"], dict["speed"], dict["cpu_times!user"], dict["cpu_times!nice"],
        dict["cpu_times!sys"], dict["cpu_times!idle"], dict["cpu_times!irq"])
end

# Function to load HwInfo from a JSON file
function load_hwinfo_from_json(filepath::String)
    if !isfile(filepath)
        error("File $filepath does not exist.")
    end

    data = _json_parsefile(filepath)

    cpus = [dict_to_cpuinfo(cpu) for cpu in data["cpus"]]

    HwInfo(
        cpus,
        data["machine"],
        data["word"],
        data["simdbytes"],
        (data["corecount"][1], data["corecount"][2], data["corecount"][3])
    )
end

@testitem "Hardware identity" tags=[:unit, :hardware] begin
    import PerfChecker

    info = PerfChecker.HwInfo()
    as_dict = PerfChecker.hwinfo_to_dict(info)
    @test as_dict["machine"] == info.machine
    @test as_dict["corecount"] == info.corecount
    @test info.machine == Sys.CPU_NAME
    @test info.word == Sys.WORD_SIZE
    @test !isempty(info.cpus)
    @test info.simdbytes == 0
    @test info.corecount[1] == PerfChecker.Hwloc.num_physical_cores()
    @test info.corecount[2] == PerfChecker.Hwloc.num_virtual_cores()
    @test info.corecount[2] > 0
    @test PerfChecker.HwInfo(; reload = false).corecount == info.corecount
    specs = PerfChecker.machine_profile()["specs"]
    @test specs["physical_cores"] == info.corecount[1]
    @test specs["logical_cpus"] == info.corecount[2]
    @test specs["simd_bytes"] == info.simdbytes
    mktempdir() do dir
        id = PerfChecker.uuid4()
        path = joinpath(dir, "$(id).json")
        PerfChecker.write_hwinfo_to_json(info, id; path = dir)
        restored = PerfChecker.load_hwinfo_from_json(path)
        @test restored.machine == info.machine
        @test restored.word == info.word
        @test restored.simdbytes == info.simdbytes
        @test restored.corecount == info.corecount
        # Historical snapshots keep their recorded nonzero capabilities.
        historical = PerfChecker.HwInfo(info.cpus, info.machine, info.word, 32, (8, 16, 2))
        PerfChecker.write_hwinfo_to_json(historical, id; path = dir)
        restored_historical = PerfChecker.load_hwinfo_from_json(path)
        @test restored_historical.simdbytes == 32
        @test restored_historical.corecount == (8, 16, 2)
        @test PerfChecker.hardware_id(historical) != PerfChecker.hardware_id(info)
        rm(path; force = true)
    end
end

@testitem "Portable hardware topology and fallback" tags=[:unit, :hardware] begin
    import PerfChecker

    # Preserve observed physical and logical counts on a mixed-SMT CPU.
    @test PerfChecker._topology_corecount(20, vcat(fill(2, 8), fill(1, 4))) == (12, 20, 0)
    @test PerfChecker._topology_corecount(16, fill(2, 8)) == (8, 16, 2)
    @test PerfChecker._topology_corecount(8, fill(1, 8)) == (8, 8, 1)
    @test PerfChecker._topology_corecount(8, Int[]) == (0, 8, 0)
    @test PerfChecker._topology_corecount(8, [0, 0, 0, 0]) == (4, 8, 0)
    @test PerfChecker._topology_corecount(9, fill(2, 4)) == (4, 9, 0)
    failure() = error("topology unavailable")
    @test PerfChecker._hardware_corecount(; topology = failure, logical_threads = 12) ==
          (0, 12, 0)
    interrupt() = throw(InterruptException())
    @test_throws InterruptException PerfChecker._hardware_corecount(; topology = interrupt)

    tree = PerfChecker.Hwloc.gettopology(; reload = true, io = false)
    counts = [length(PerfChecker.Hwloc.collectobjects(:PU, core))
              for core in PerfChecker.Hwloc.collectobjects(:Core, tree)]
    actual = PerfChecker.HwInfo(; reload = false)
    if length(unique(counts)) > 1
        @test actual.corecount[3] == 0
    elseif !isempty(counts) && all(>(0), counts) && sum(counts) == actual.corecount[2]
        @test actual.corecount[3] == first(counts)
    end
end
