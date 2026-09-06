# SPDX-License-Identifier: Apache-2.0
# Copyright 2023-2026 Deutsches Elektronen Synchrotron DESY
#                     and the University of Glasgow
# ===========================================================================
include("OracleD.jl")
using .OracleD
using Dates
using OrderedCollections
using Test

"Build a minimal configuration dictionary for constructing simulation objects in tests."
function test_config(run_dir::AbstractString; verbosity::AbstractString = "low")
    return OrderedDict{String,Any}(
        "output" => OrderedDict{String,Any}(
            "verbosity" => verbosity,
            "run_dir" => run_dir,
        ),
    )
end

"A small synthetic three-frequency machine type used across the tests."
test_spec() = OracleD.WorkerNodeSpec("TEST_0", 8, 64.0, 100.0,
                                     Dict(3.0 => (300.0, 3000.0),
                                          2.0 => (200.0, 2000.0),
                                          1.0 => (100.0, 1000.0)))

@testset "OracleD" begin

    @testset "util" begin
        @test OracleD.pynum(400) == "400"
        @test OracleD.pynum(400.0) == "400"
        @test OracleD.pynum(400.5) == "400.5"

        @test OracleD.slugify("RF20PMTest-50000LHCJobs-Base") == "rf20pmtest_50000lhcjobs_base"
        @test OracleD.slugify("--") == "simulation"

        @test OracleD.normalize_verbosity("medium") == "medium"
        @test OracleD.normalize_verbosity("bogus") == "high"
        @test OracleD.normalize_verbosity(nothing) == "high"

        values = collect(9.5:1.0:18.5)
        for _ in 1:100
            v = OracleD.weighted_choice(values, fill(0.1, 10))
            @test v in values
        end
        @test OracleD.weighted_choice([42.0], [1.0]) == 42.0

        @test OracleD.total_seconds(DateTime(2024, 1, 1, 1) - DateTime(2024, 1, 1)) == 3600.0
        @test OracleD.pystr(DateTime(2024, 1, 16, 16, 0)) == "2024-01-16 16:00:00"

        @test isdir(OracleD.project_root())
        @test OracleD.resolve_path("/abs/path") == "/abs/path"
        @test OracleD.resolve_path("config.json") == joinpath(OracleD.project_root(), "config.json")
    end

    @testset "SimulationTime" begin
        mktempdir() do dir
            config = test_config(dir)
            st = OracleD.SimulationTime(config, "2024-01-16 16:00")
            @test OracleD.get_start_datetime(st) == DateTime(2024, 1, 16, 16, 0)
            @test OracleD.get_timestep(st) == 600

            # Half-hour segment lookup, including the on-boundary case where a time
            # exactly on the half hour belongs to the previous segment.
            @test OracleD.find_hh_segment(st, DateTime(2024, 1, 16, 16, 10)) == DateTime(2024, 1, 16, 16, 0)
            @test OracleD.find_hh_segment(st, DateTime(2024, 1, 16, 16, 10), "next") == DateTime(2024, 1, 16, 16, 30)
            @test OracleD.find_hh_segment(st, DateTime(2024, 1, 16, 16, 30)) == DateTime(2024, 1, 16, 16, 30)
            @test OracleD.find_hh_segment(st, DateTime(2024, 1, 16, 16, 30), "next") == DateTime(2024, 1, 16, 17, 0)

            OracleD.advance!(st)
            @test OracleD.get_current_datetime(st) == DateTime(2024, 1, 16, 16, 10)
        end
    end

    @testset "Job" begin
        job = OracleD.Job("Test-1", 3600.0, 2.0, 8)
        @test job.start_time == OracleD.UNSET_TIME
        @test job.end_time == OracleD.UNSET_TIME

        # Setting a duration before the job starts must not touch the end time.
        OracleD.set_duration!(job, 1800.0)
        @test job.end_time == OracleD.UNSET_TIME

        OracleD.set_start_time!(job, DateTime(2024, 1, 16, 16, 0))
        @test job.end_time == DateTime(2024, 1, 16, 16, 30)

        # Once started, changing the duration recomputes the end time.
        OracleD.set_duration!(job, 3600.0)
        @test job.end_time == DateTime(2024, 1, 16, 17, 0)

        OracleD.set_end_time!(job, DateTime(2024, 1, 16, 18, 0))
        @test job.end_time == DateTime(2024, 1, 16, 18, 0)

        @test string(job) == "Test-1"
    end

    @testset "VOJobFactory" begin
        gridpp = OracleD.GridPPJobFactory("GridPP-")
        job = OracleD.create_job!(gridpp)
        @test job.name == "GridPP-1"
        @test job.duration == 300 * 60
        @test job.cores_req == 1
        @test job.memory_req == 2.0
        @test OracleD.create_job!(gridpp).name == "GridPP-2"

        atlas = OracleD.ATLASJobFactory("ATLAS-Prod-")
        cores = OracleD.require_cores!(atlas)
        @test cores in (1, 8)
        # The first draw is cached: every later job requests the same core count.
        for _ in 1:20
            @test OracleD.create_job!(atlas).cores_req == cores
        end
        @test OracleD.create_job!(atlas).duration >= 5 * 60

        lhcb = OracleD.LHCbJobFactory("LHCb-Prod-")
        for _ in 1:20
            duration = OracleD.get_duration(lhcb)
            @test duration >= 5 * 60
            @test duration <= 18.5 * 3600
        end

        fixed = OracleD.ATLASJobFactory("ATLAS-8-", 2, 8)
        @test OracleD.create_job!(fixed).cores_req == 8
    end

    @testset "ClusterLoader" begin
        inventory = OracleD.load_cluster_inventory(
            "data/cluster/default-machinegroups_inventory.csv",
            "data/cluster/default-frequency_dependence.csv";
            cluster_name = "DEFAULT", strict = true)

        @test length(inventory) == 9
        @test sum(quantity for (_, quantity) in inventory) == 310

        spec, quantity = inventory[1]
        @test spec.node_key == "DESYT3_0"
        @test quantity == 40
        @test spec.threads == 96
        @test spec.memory_gb == 256.0
        @test spec.idle_power_w == 112.0
        # Frequencies are sorted descending, with power and HEPScore kept in step.
        @test issorted(spec.frequencies; rev = true)
        @test spec.frequencies[1] == 2.7
        @test spec.powers_w[1] == 530.1
        @test spec.hepscores[1] == 1450.0

        # An unknown cluster name filters out every row.
        @test isempty(OracleD.load_cluster_inventory(
            "data/cluster/default-machinegroups_inventory.csv",
            "data/cluster/default-frequency_dependence.csv";
            cluster_name = "NO_SUCH_CLUSTER", strict = true))
    end

    @testset "WorkerNode" begin
        mktempdir() do dir
            config = test_config(dir)
            st = OracleD.SimulationTime(config, "2024-01-16 16:00")
            dl = OracleD.DataLogger(config)
            node = OracleD.WorkerNode(test_spec(), st, dl, "-001")

            @test node.hostname == "TEST_0-001"
            @test OracleD.number_of_cores(node) == 8
            @test node.physical_cores == 4.0
            @test OracleD.get_free_core_count(node) == 8
            @test OracleD.is_awaiting_jobs(node)

            # Idle node: dissipates the idle power over one 600 s timestep, in kWh.
            @test OracleD.timestep_power_dissipated(node) ≈ 100.0 / 3600 * 600 / 1000

            job = OracleD.Job("Test-1", 3600.0, 2.0, 8)
            @test OracleD.can_schedule_job(node, job)
            OracleD.start_job!(node, job)
            @test node.busy_cores == 8
            @test node.busy_RAM == 16.0
            @test dl.jobs_started == 1
            # Duration is rescaled by the reference HEPScore ratio (1939.6 / 3000).
            @test job.duration ≈ 3600.0 * 1939.60 / 3000.0
            @test job.start_time == DateTime(2024, 1, 16, 16, 0)

            # Fully busy node dissipates the full active power (scaling capped at 1).
            @test OracleD.timestep_power_dissipated(node) ≈ 300.0 / 3600 * 600 / 1000

            # As in Python, only the per-core memory request is checked when scheduling.
            probe = OracleD.Job("Test-2", 600.0, 2.0, 8)
            node2 = OracleD.WorkerNode(test_spec(), st, dl)
            node2.busy_RAM = 61.0 # 3 GB free: an 8-core 2 GB/core job "fits"
            @test OracleD.can_schedule_job(node2, probe)
            node2.busy_RAM = 63.0 # 1 GB free < 2 GB per core: it does not
            @test !OracleD.can_schedule_job(node2, probe)

            # Clocking down steps one frequency, adjusts power and stretches running jobs.
            end_before = job.end_time
            OracleD.clock_down!(node)
            @test node.running_frequency == 2.0
            @test node.powerusage_active ≈ 200.0 / 3600
            @test node.dynamic_duration_multiplier ≈ 3000.0 / 2000.0
            @test OracleD.total_seconds(job.end_time - OracleD.get_current_datetime(st)) ≈
                  1.5 * OracleD.total_seconds(end_before - OracleD.get_current_datetime(st)) atol = 0.01

            OracleD.clock_up!(node)
            @test node.running_frequency == 3.0
            @test node.powerusage_active ≈ 300.0 / 3600

            # Clocking past the ends of the frequency list just prints a message.
            OracleD.clock_up!(node)
            @test node.running_frequency == 3.0

            # Finishing a job frees its resources and records the duration using
            # Python's timedelta.seconds semantics (whole days are dropped).
            OracleD.set_end_time!(job, DateTime(2024, 1, 17, 17, 0)) # 25 h after start
            OracleD.set_to_time!(st, DateTime(2024, 1, 18))
            OracleD.update!(node)
            @test isempty(node.jobs)
            @test node.busy_cores == 0
            @test node.busy_RAM == 0.0
            @test dl.jobs_finished == 1
            @test job.duration == mod(25 * 3600, 86400) # 1 h, not 25 h
        end
    end

    @testset "Cluster and JobScheduler" begin
        mktempdir() do dir
            config = test_config(dir)
            config["jobs"] = OrderedDict{String,Any}(
                "initial_mix" => OrderedDict{String,Any}("GridPP" => 3),
            )
            st = OracleD.SimulationTime(config, "2024-01-16 16:00")
            dl = OracleD.DataLogger(config)
            carbondata = [OracleD.CarbonIntensityEntry(DateTime(2024, 1, 16, 16, 0) + Hour(h), 350.0, 150.0)
                          for h in 0:48]
            inventory = [(test_spec(), 2)]
            cluster = OracleD.Cluster(config, st, inventory, carbondata, "none", 400, dl)

            @test OracleD.get_number_of_nodes(cluster) == 2
            @test OracleD.get_number_of_cores(cluster) == 16
            @test !OracleD.has_queued_jobs(cluster)
            @test !OracleD.has_running_jobs(cluster)

            scheduler = OracleD.JobScheduler(st, cluster, config["jobs"]["initial_mix"],
                                             Tuple{OrderedDict{String,Int},Int}[])
            @test OracleD.has_queued_jobs(cluster)
            @test length(cluster.queued_jobs) == 3
            @test cluster.queued_jobs[1].name == "GridPP-1"

            # Run the loop until all jobs finish; 5 h GridPP jobs scaled by the node
            # performance should complete well inside two simulated days.
            output = redirect_stdout(devnull) do
                steps = 0
                while !cluster.mission_accomplished && steps < 500
                    OracleD.update!(scheduler)
                    OracleD.update!(cluster)
                    OracleD.advance!(st)
                    steps += 1
                end
            end
            @test cluster.mission_accomplished
            @test dl.jobs_started == 3
            @test dl.jobs_finished == 3
            @test dl.total_energy_consumed > 0
            @test dl.total_carbon_consumed > 0
        end
    end

    @testset "DataLogger summary" begin
        mktempdir() do dir
            config = test_config(dir)
            dl = OracleD.DataLogger(config)
            OracleD.energy_and_carbon_consumed!(dl, 2.0, 150.0)
            @test dl.total_energy_consumed == 2.0
            @test dl.total_carbon_consumed == 300.0
            OracleD.peaktime_energy_and_carbon_consumed!(dl, 1.0, 150.0)
            @test dl.peaktime_energy_consumed == 1.0
            OracleD.sum_occupancy!(dl, 0.5)
            OracleD.sum_occupancy!(dl, 0.7)

            dl.jobs_started = 10
            dl.jobs_finished = 10
            dl.jobs_total_cores_used = 20
            dl.cumulative_cpu_time = 72000.0

            redirect_stdout(devnull) do
                OracleD.print_summary(dl, true, "test", 1200.0, 600, 60.0)
            end
            @test dl.avg_jobs_completed == 10.0
            @test dl.avg_energy_per_job == 0.2
            @test dl.avg_occupancy ≈ 0.6

            summary_txt = read(joinpath(dir, "summary.txt"), String)
            @test occursin("Jobs Started                       : 10", summary_txt)
            @test occursin("Total energy consumed by compute   : 2.00 kWh", summary_txt)
            @test isfile(joinpath(dir, "summary.json"))
        end
    end

end
