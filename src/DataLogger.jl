# SPDX-License-Identifier: Apache-2.0
# Copyright 2023-2026 Deutsches Elektronen Synchrotron DESY
#                     and the University of Glasgow
# Authors: Dwayne Spiteri and Gordon Stewart.
# For more information about rights and fair use please refer to src/OracleD.jl.
# ===========================================================================

# Statistics recording and summary output, mirroring src/datalogger/DataLogger.py.

"""
    DataLogger

Accumulates run statistics (job counts, CPU time, energy, carbon and
occupancy) and produces the end-of-run summary on the console and in the
run directory (`summary.txt` and `summary.json`).
"""
mutable struct DataLogger
    jobs_submitted::Int
    jobs_started::Int
    jobs_finished::Int
    jobs_failed::Int
    jobs_aborted::Int
    jobs_total_cores_used::Int

    cumulative_cpu_time::Float64
    cumulative_wallclock_time::Float64
    total_energy_consumed::Float64
    peaktime_energy_consumed::Float64
    total_carbon_consumed::Float64
    peaktime_carbon_consumed::Float64
    sum_occupancy::Float64

    avg_jobs_completed::Float64
    avg_energy_per_job::Float64
    avg_carbon_per_job::Float64
    avg_occupancy::Float64

    verbosity::String
    run_dir::String
    simulation_parameters::OrderedDict{String,Any}
end

"""
    DataLogger(config) -> DataLogger

Create a data logger reading `output.verbosity` and `output.run_dir` from
the configuration.
"""
function DataLogger(config::AbstractDict)
    output_cfg = config["output"]
    return DataLogger(0, 0, 0, 0, 0, 0,
                      0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
                      0.0, 0.0, 0.0, 0.0,
                      output_cfg["verbosity"],
                      get(output_cfg, "run_dir", "logs"),
                      OrderedDict{String,Any}())
end

"""
    set_simulation_parameters!(datalogger, simulation_parameters)

Store the simulation parameter dictionary for inclusion in `summary.json`.
"""
function set_simulation_parameters!(datalogger::DataLogger, simulation_parameters::AbstractDict)
    datalogger.simulation_parameters = simulation_parameters
    return datalogger
end

"""
    job_submit!(datalogger, job)

Record that a job has been submitted to the cluster queue (currently a
no-op, as in the Python code).
"""
job_submit!(datalogger::DataLogger, job) = nothing

"""
    job_start!(datalogger, job, worker_node)

Record that `job` has started on `worker_node`.
"""
function job_start!(datalogger::DataLogger, job, worker_node)
    if datalogger.verbosity == "high"
        log_info(get_logger(), "Starting job $(job.name) on node $(worker_node.hostname) at $(pystr(job.start_time))")
    end
    datalogger.jobs_started += 1
    datalogger.jobs_total_cores_used += job.cores_req
    return nothing
end

"""
    job_finish!(datalogger, job, worker_node)

Record that `job` has finished on `worker_node`, accumulating its wallclock
and CPU time.
"""
function job_finish!(datalogger::DataLogger, job, worker_node)
    if datalogger.verbosity == "high"
        log_info(get_logger(), "Job $(job.name) finished on node $(worker_node.hostname) at $(pystr(job.end_time))")
    end
    datalogger.jobs_finished += 1
    datalogger.cumulative_wallclock_time += job.duration
    # Yes, Sam, I know... ;-)
    datalogger.cumulative_cpu_time += job.duration * job.cores_req
    return nothing
end

"""
    energy_and_carbon_consumed!(datalogger, timestep_energy_consumed, timestep_carbon_consumed_per_unit_energy)

Accumulate the energy dissipated in a timestep (kWh) and the corresponding
carbon (energy times the grid carbon intensity in g/kWh).
"""
function energy_and_carbon_consumed!(datalogger::DataLogger,
                                     timestep_energy_consumed::Real,
                                     timestep_carbon_consumed_per_unit_energy::Real)
    datalogger.total_energy_consumed += timestep_energy_consumed # kWh
    datalogger.total_carbon_consumed += timestep_energy_consumed * timestep_carbon_consumed_per_unit_energy # g
    return nothing
end

"""
    peaktime_energy_and_carbon_consumed!(datalogger, timestep_energy_consumed, timestep_carbon_consumed_per_unit_energy)

As [`energy_and_carbon_consumed!`](@ref) but accumulated into the peak-time
(5pm-9pm) totals.
"""
function peaktime_energy_and_carbon_consumed!(datalogger::DataLogger,
                                              timestep_energy_consumed::Real,
                                              timestep_carbon_consumed_per_unit_energy::Real)
    datalogger.peaktime_energy_consumed += timestep_energy_consumed # kWh
    datalogger.peaktime_carbon_consumed += timestep_energy_consumed * timestep_carbon_consumed_per_unit_energy # g
    return nothing
end

"""
    sum_occupancy!(datalogger, timestep_occupancy)

Accumulate the cluster occupancy fraction for one timestep (divided by the
number of timesteps when the simulation ends to give the average).
"""
function sum_occupancy!(datalogger::DataLogger, timestep_occupancy::Real)
    datalogger.sum_occupancy += timestep_occupancy
    return nothing
end

function _format_summary(datalogger::DataLogger, total_simulated_time::Real, total_real_time::Real)
    io = IOBuffer()
    println(io, "========")
    println(io, "Summary")
    println(io, "========")
    println(io)
    @printf(io, "Total Simulated-time Duration      : %4.1f hours\n", total_simulated_time / 3600)
    @printf(io, "Total Real-time Duration           : %4.1f minutes\n", total_real_time / 60)
    println(io)
    println(io, "Jobs Started                       : $(datalogger.jobs_started)")
    println(io, "Jobs Finished                      : $(datalogger.jobs_finished)")
    println(io)
    @printf(io, "Total CPU duration                 : %6.1f hours\n", datalogger.cumulative_cpu_time / 3600)
    @printf(io, "Average CPU duration               : %4.2f hours\n",
            (datalogger.cumulative_cpu_time / 3600) / datalogger.jobs_total_cores_used)
    @printf(io, "Average Occupancy of all clusters  : %3.1f %%\n", datalogger.avg_occupancy * 100)
    println(io)
    @printf(io, "Total energy consumed by compute   : %3.2f kWh\n", datalogger.total_energy_consumed)
    @printf(io, "Peaktime (5-9pm) energy consumption: %3.2f kWh\n", datalogger.peaktime_energy_consumed)
    @printf(io, "Average energy consumption per job : %3.2f Wh\n", datalogger.avg_energy_per_job * 1e3)
    println(io)
    @printf(io, "Estimated CO2e emissions           : %.3f kg\n", datalogger.total_carbon_consumed / 1e3)
    @printf(io, "Estimated Peaktime CO2e emissions  : %.3f kg\n", datalogger.peaktime_carbon_consumed / 1e3)
    @printf(io, "Average CO2e emissions per job     : %.3f g\n", datalogger.avg_carbon_per_job)
    @printf(io, "Peaktime CO2e emissions percentage : %.3f %%\n",
            datalogger.peaktime_carbon_consumed / datalogger.total_carbon_consumed * 100)
    println(io)
    return String(take!(io))
end

"""
    print_summary(datalogger, summary_file, additional_description,
                  total_simulated_time, timestepinsec, total_real_time)

Compute the derived averages, print the run summary to the console and,
when `summary_file` is `true`, append it to `summary.txt` and write the
machine-readable `summary.json` in the run directory.
"""
function print_summary(datalogger::DataLogger, summary_file::Bool, additional_description,
                       total_simulated_time::Real, timestepinsec::Real, total_real_time::Real)
    datalogger.avg_jobs_completed = datalogger.jobs_finished +
        (datalogger.jobs_started - datalogger.jobs_finished) / 2
    datalogger.avg_energy_per_job = datalogger.total_energy_consumed / datalogger.avg_jobs_completed
    datalogger.avg_carbon_per_job = datalogger.total_carbon_consumed / datalogger.avg_jobs_completed
    datalogger.avg_occupancy = datalogger.sum_occupancy / (total_simulated_time / timestepinsec)
    summary = _create_summary(datalogger, total_simulated_time, total_real_time)

    summary_text = _format_summary(datalogger, total_simulated_time, total_real_time)
    print(summary_text)

    if summary_file
        summary_path = joinpath(datalogger.run_dir, "summary.txt")
        open(summary_path, "a") do outfile
            write(outfile, summary_text)
        end

        summary_json_path = joinpath(datalogger.run_dir, "summary.json")
        open(summary_json_path, "w") do outfile
            # JSON.print already ends indented output with a newline, matching json.dump + '\n'.
            JSON.print(outfile, summary, 4)
        end
    end
    return nothing
end

"""
    _create_summary(datalogger, total_simulated_time, total_real_time) -> OrderedDict

Build the machine-readable summary written to `summary.json`.
"""
function _create_summary(datalogger::DataLogger, total_simulated_time::Real, total_real_time::Real)
    return OrderedDict{String,Any}(
        "simulation_parameters" => datalogger.simulation_parameters,
        "duration" => OrderedDict{String,Any}(
            "simulated_seconds" => total_simulated_time,
            "simulated_hours" => total_simulated_time / 3600,
            "real_seconds" => total_real_time,
            "real_minutes" => total_real_time / 60,
        ),
        "jobs" => OrderedDict{String,Any}(
            "started" => datalogger.jobs_started,
            "finished" => datalogger.jobs_finished,
            "average_completed" => datalogger.avg_jobs_completed,
            "total_cores_used" => datalogger.jobs_total_cores_used,
        ),
        "cpu" => OrderedDict{String,Any}(
            "total_core_seconds" => datalogger.cumulative_cpu_time,
            "total_core_hours" => datalogger.cumulative_cpu_time / 3600,
            "average_core_hours" => (datalogger.cumulative_cpu_time / 3600) / datalogger.jobs_total_cores_used,
        ),
        "occupancy" => OrderedDict{String,Any}(
            "average_fraction" => datalogger.avg_occupancy,
            "average_percent" => datalogger.avg_occupancy * 100,
        ),
        "energy" => OrderedDict{String,Any}(
            "total_kwh" => datalogger.total_energy_consumed,
            "peaktime_kwh" => datalogger.peaktime_energy_consumed,
            "average_per_job_wh" => datalogger.avg_energy_per_job * 1e3,
        ),
        "carbon" => OrderedDict{String,Any}(
            "total_g" => datalogger.total_carbon_consumed,
            "total_kg" => datalogger.total_carbon_consumed / 1e3,
            "peaktime_g" => datalogger.peaktime_carbon_consumed,
            "peaktime_kg" => datalogger.peaktime_carbon_consumed / 1e3,
            "average_per_job_g" => datalogger.avg_carbon_per_job,
            "peaktime_percent" => datalogger.peaktime_carbon_consumed / datalogger.total_carbon_consumed * 100,
        ),
    )
end
