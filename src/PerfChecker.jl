"""
Performance measurement, comparison and qualification for Julia workloads.
Start with `discover_testitems` for existing tests or `plan_suite` for explicit
feature workloads. Interface packages consume the same plans and saved evidence;
measurement and diagnostic processes run in separately prepared environments.
"""
module PerfChecker

# SECTION - Imports
import Base.Sys: CPUinfo, CPU_NAME, cpu_info, WORD_SIZE
import CoverageTools: analyze_malloc_files, find_malloc_files, MallocInfo
import CpuId: simdbytes, cpucores, cputhreads, cputhreads_per_core
import CSV
import Dates
import Downloads
import JSON
import Libdl
import Malt: remote_eval_wait, Worker, remote_eval_fetch, stop, fetch
import Pkg
import Pkg.Types: PackageSpec, Context
import Profile
import Random

# Extension entry points. Their implementations are loaded only when the
# corresponding optional dependency is present.
"""
    drwatson_run_suite(suite; profile=:quick, directory="", force=false,
                      tag=true, kwargs...)

Load `DrWatson`. Plan a suite, use its plan revision as a cache parameter and
run it with reports when production is required. Return the DrWatson cache
result. Existing artifacts may be reused: request `force=true` when fresh
execution is required, and inspect the saved provenance before comparison.
"""
function drwatson_run_suite end
"""
    documenter_makedocs(bundle; root=pwd(), source="src", build="build",
                        page="performance.md", sitename="Performance", kwargs...)

Load `Documenter`. Generate a performance page from saved evidence and invoke
`Documenter.makedocs`, forwarding additional options. This writes documentation
outputs but does not deploy them. For VitePress, use the corresponding extension.
"""
function documenter_makedocs end
"""
    documenter_page(bundle_or_result, destination; title="Performance",
                    blocks=PerformanceDocumentBlock[], config=nothing)

Load `Documenter` and write a Markdown report page from existing evidence.
`config` selects blocks from a configuration file; without blocks, include the
version comparison summary. Create parent directories, replace the destination
and return its absolute path. This renders saved data without running workloads.
"""
function documenter_page end
"""
    documenter_vitepress_makedocs(bundle; repo, devbranch="main",
                                  devurl="dev", deploy_url=nothing, kwargs...)

Load `Documenter` and `DocumenterVitepress`. Configure the VitePress formatter and
build a report site through `documenter_makedocs`. `repo` is required. This is a
report-publishing integration for user projects, separate from PerfChecker's
own website and its collection qualification gate.
"""
function documenter_vitepress_makedocs end
"""
    freeze_propcheck_corpus(path, generator; count=100, seed=0,
                            encode=identity, metadata=Dict(), force=false)

Load `PropCheck` to enable this extension. Generate cases with a seeded Xoshiro
RNG, extract tree roots, apply `encode` and save a frozen JSON corpus. Return its
absolute path. `count` must be positive; overwriting requires `force=true`.
Generation happens now, outside later measurement workers.
"""
function freeze_propcheck_corpus end
"""
    prepare_pluto_dashboard(path; suite_path=nothing, factory=:build_suite, kwargs...)

Load `PerfCheckerPluto`. Write a suite dashboard notebook and return its absolute
path without starting Pluto or a workload. `suite_path` selects the Julia suite
definition and `factory` its constructor; the notebook uses explicit run controls.
Other keywords, including `project`, `reports_root` and `force`, are forwarded to
[`write_suite_notebook`](@ref).
"""
function prepare_pluto_dashboard end
"""
Load `UnicodePlots` to render a performance plot model or a selected bundle plot in the terminal. This consumes existing observations without rerunning their workload.
"""
function terminal_plot end
import SHA
import TOML
import TOML: parse
import TestItems: @testitem
import TypedTables: Table
import UUIDs: UUID, uuid4, uuid5

# SECTION - Exports
export @check
export FeatureSpec
export OracleSpec
export ProbeSpec
export workload_id
export worker_environment
export FeatureVariant
export FeatureRun
export ExternalCommandSpec
export BundleComparison
export VersionComparison
export CompatibilityReport
export PackageSuite
export PlannedFeatureRun
export SoftwareSuite
export SoftwareSuiteResult
export RunBundle
export JuliaRuntimeSpec
export JuliaRuntimeCampaign
export JuliaRegressionInvestigation
export NativeDependencyEvidence
export NetworkInterfaceSnapshot
export ProcessMemorySnapshot
export ExternalMemorySnapshot
export ResourceEnvelope
export NetworkIsolationSpec
export IsolatedNetworkCommandResult
export PerformanceQuery
export QueryPredicate
export PerformanceDocumentBlock
export SuiteJob
export SuitePlan
export SuiteCandidate
export ComparisonPolicy
export comparison_policy_dict
export VersionWindow
export check_to_metadata_csv
export bundle_passed
export cancel_suite!
export bundle_dict
export comparison_dict
export comparison_passed
export comparison_verdict
export compatibility_report_dict
export compare_bundles
export compare_suite_versions
export performance_figure
export performance_plot
export performance_plot_dict
export performance_plot_html
export performance_query
export performance_query_dict
export performance_document_block
export read_document_blocks
export read_ui_configuration
export perfchecker_main
export query_bundle
export query_result_dict
export agent_evidence
export plot_catalog
export external_command_dict
export checkres_to_boxplots
export checkres_to_pie
export checkres_to_scatterlines
export csv_to_table
export drwatson_parameters
export drwatson_produce_or_load
export drwatson_run_suite
export drwatson_savename
export documenter_makedocs
export documenter_page
export documenter_vitepress_makedocs
export find_by_tags
export freeze_supposition_corpus
export freeze_propcheck_corpus
export get_versions
export dependency_evidence
export dependency_evidence_dict
export julia_runtime_command
export julia_runtime_matrix
export julia_runtime_spec_dict
export julia_runtime_suite_command
export julia_runtime_campaign_dict
export julia_investigation_dict
export loaded_library_inventory
export package_dependency_inventory
export probe_julia_runtime
export run_julia_runtime_campaign
export runtime_campaign_passed
export investigate_julia_regressions
export launch_pluto_dashboard
export prepare_pluto_dashboard
export launch_suite
export load_software_suite
export plan_suite
export preflight_suite
export preflight_passed
export probe_spec_dict
export oracle_spec_dict
export planned_run_id
export PerfConfig
export perf_setup
export register_oxygen_routes!
export read_property_corpus
export read_provider_result
export read_run_bundle
export list_run_bundles
export migrate_run_bundle
export verify_run_bundle
export measure_network_interface
export process_memory_capabilities
export process_memory_snapshot
export process_memory_snapshot_dict
export external_memory_snapshot
export external_memory_snapshot_dict
export resource_envelope_dict
export resource_envelope_metrics
export evaluate_resource_envelope
export resource_policy_passed
export measure_network_isolated
export measure_isolated_network_command
export network_interface_capabilities
export network_interface_delta
export network_interface_snapshot
export network_isolation_capabilities
export network_isolation_spec_dict
export isolated_network_result_dict
export run_external_command
export run_suite
export run_suite_file
export run_studio_agent
export saveplot
export serve_suite
export select_suite_plan
export filter_suite_plan
export configure_suite_repl
export print_suite_plan
export run_suite_repl
export studio_token_authenticator
export write_folded_profile
export write_pprof_profile
export write_speedscope_profile
export summary_table
export suite_dashboard
export suite_dict
export suite_job_status
export suite_job_dict
export suite_job_progress
export suite_passed
export suite_verdict
export suite_plan_dict
export suite_summary
export suite_version_series
export table_to_csv
export table_to_pie
export terminal_plot
export to_table
export write_suite_json
export write_julia_runtime_campaign
export write_julia_investigation
export write_run_bundle
export write_comparison_json
export write_comparison_markdown
export write_compatibility_report
export write_version_comparison_json
export write_version_comparison_markdown
export write_version_series_json
export version_comparison_dict
export version_comparison_passed
export version_comparison_verdict
export write_suite_bundle
export write_suite_junit
export write_suite_markdown
export write_suite_notebook
export write_software_suite_template
export write_suite_reports
export write_template
export write_property_corpus
export wait_suite
export ScenarioSpec, ScenarioCatalog, load_scenario_catalog, scenario_catalog_dict
export select_scenarios, read_scenario_runs
export InvestigationView, investigation_view, InvestigationJob, launch_investigation
export investigation_status, wait_investigation
export write_investigation_notebook
export discover, run_scenarios, diagnose, advise, write_investigation_report
export diagnostic_capabilities
export CancellationToken, cancel!, compare_scenarios
export tool_catalog, AdvisorConfig, load_advisor_config, read_advice, narrate_advice,
       investigate, evaluate_advisors
export advisor_transport
export advisor_setup, advisor_setup_transport, launch_advisor_setup
export scenario_sync, write_scenario_workflow
export run_perfitem, discover_testitems, run_testitems, testitem_filter
export machine_profile, similar_machines, estimate_performance
export native_tool_plan
export register_testitem_routes!

# SECTION - Includes
include("init.jl")
include("json_compat.jl")
include("hwinfo.jl")
include("config.jl")
include("process_resources.jl")
include("checker_results.jl")
include("summary.jl")
include("utils.jl")
include("csv.jl")
include("versions.jl")
include("templates.jl")
include("corpus.jl")
include("check.jl")
include("alloc.jl")
include("profile_allocs.jl")
include("profile.jl")
include("network.jl")
include("network_isolation.jl")
include("dependency_evidence.jl")
include("qualification.jl")
include("runtime_specs.jl")
include("suites.jl")
include("compatibility.jl")
include("repl.jl")
include("protocol.jl")
include("profile_exports.jl")
include("compare.jl")
include("machine_transfer.jl")
include("version_compare.jl")
include("plots.jl")
include("report_queries.jl")
include("runtime_campaigns.jl")
include("runtime_investigations.jl")
include("scenarios.jl")
include("perfitems.jl")
include("testitems.jl")
include("discovery.jl")
include("diagnostics.jl")
include("advice.jl")
include("tool_catalog.jl")
include("native_tools.jl")
include("scenario_sync.jl")
include("advisor.jl")
include("advisor_setup.jl")
include("investigator.jl")
include("investigation_views.jl")
"Generate an investigation notebook. Load PerfCheckerPluto before calling."
function write_investigation_notebook end
include("scenario_cli.jl")
include("cli.jl")

end
