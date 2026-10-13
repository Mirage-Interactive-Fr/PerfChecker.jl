using PerfChecker, BenchmarkTools
config = PerfConfig(:benchmark; path = dirname(Base.active_project()),
    pkgs = ("Bibliography", :custom, [v"0.3.1", v"0.4.0"], false),
    include_current = false, samples = 50, evals = 1, seconds = 1.0)
result = @check config begin
    using Bibliography
    entries = Bibliography.import_bibtex(
        "@article{example, title={A small example}, author={Ada Lovelace}, " *
        "journal={Julia Studies}, year={2026}}\n")
end begin
    Bibliography.export_bibtex(entries)
end
