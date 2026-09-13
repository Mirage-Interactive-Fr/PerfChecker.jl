using CairoMakie, JSON, Statistics
length(ARGS) == 2 || error("Pass a network JSON file (or history directory) and an export directory")
source, output = abspath.(ARGS)
files = isdir(source) ? filter(f -> endswith(f, ".json"), readdir(source; join = true)) : [source]
records = [JSON.parsefile(file) for file in files]
sort!(records; by = r -> VersionNumber(r["version"]))
isempty(records) && error("No network observations")
mkpath(output)
latest = last(records)
open(io -> JSON.print(io, latest, 2), joinpath(output, "latest.json"), "w")
open(io -> JSON.print(io, Dict("versions" => records), 2), joinpath(output, "history.json"), "w")

function four_panel(rows, x, labels; title, xlabel)
    figure = Figure(size = (1100, 780))
    Label(figure[0, 1:2], title; fontsize = 22)
    specs = [("Round-trip latency", "milliseconds", s -> s["workload_seconds"] * 1000),
        ("Application throughput (both bodies)", "MiB / second", (s,n) -> 2n / s["workload_seconds"] / 2^20),
        ("Loopback transmit bytes", "bytes / exchange", s -> s["bytes_sent"]),
        ("Loopback transmit packets", "packets / exchange", s -> s["packets_sent"])]
    for (i, (heading, unit, value)) in enumerate(specs)
        axis = Axis(figure[fld(i-1,2)+1, mod(i-1,2)+1]; title = heading, ylabel = unit,
            xlabel, xticks = (x, labels), xticklabelrotation = length(x) > 6 ? pi/3 : 0)
        medians = Float64[]
        for (j,row) in enumerate(rows)
            observations = [i == 2 ? value(sample,row["payload_bytes"]) : value(sample) for sample in row["samples"]]
            scatter!(axis, fill(x[j], length(observations)), observations; color = (:steelblue, 0.3), markersize = 5)
            push!(medians, median(observations))
        end
        lines!(axis, x, medians; color = :steelblue, linewidth = 2, label = "median; dots = all 30 samples")
        scatter!(axis, x, medians; color = :steelblue, markersize = 8)
        axislegend(axis; position = :lt, labelsize = 10)
    end
    figure
end

rows = latest["records"]
save(joinpath(output, "network.svg"), four_panel(rows, collect(1:length(rows)),
    [string(row["payload_bytes"]) for row in rows]; title = "Oxygen $(latest["version"]): real loopback exchanges", xlabel = "request body bytes"))
if length(records) > 1
    for n in [r["payload_bytes"] for r in first(records)["records"]]
        local rows = [only(filter(row -> row["payload_bytes"] == n, record["records"])) for record in records]
        save(joinpath(output, "history-$(n).svg"), four_panel(rows, collect(1:length(records)),
            [record["version"] for record in records]; title = "Oxygen patch history: $(n)-byte echo", xlabel = "Oxygen release"))
    end
end
println("Exported actual network observations for ", length(records), " releases")
