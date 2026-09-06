# SPDX-License-Identifier: Apache-2.0
# Copyright 2023-2026 Deutsches Elektronen Synchrotron DESY
#                     and the University of Glasgow
# Authors: Dwayne Spiteri and Gordon Stewart.
# For more information about rights and fair use please refer to src/OracleD.jl.
# ===========================================================================

# The cluster of worker nodes, mirroring src/cluster/Cluster.py.

"""
    CarbonIntensityEntry

One record of grid carbon intensity data: the start of a data segment, the
forecast intensity and the actual intensity (both in gCO2e/kWh).
"""
struct CarbonIntensityEntry
    datetime::DateTime
    forecast::Float64
    actual::Float64
end

"""
    Cluster

The cluster to be simulated: a set of worker nodes, the queue of jobs
waiting to be scheduled, and the state needed to apply the configured
energy-saving policy against the grid carbon intensity data.
"""
mutable struct Cluster
    simulation_time::SimulationTime
    worker_nodes::Vector{WorkerNode}
    queued_jobs::Vector{Job}
    timestep_power_dissipated::Float64
    timestep_carbon_consumed::Float64
    timestep_occupancy::Float64
    days::Int
    last_day::String

    carbondata::Vector{CarbonIntensityEntry}
    energy_saving_try::String
    cditerant::Int # Marks our place in the carbon data list w.r.t. simulation time.
    CIThresholdValue::Float64
    in_clkdown::Bool # Flags to make decisions based on the status of the cluster.
    anticipate_clkdown::Bool
    anticipate_clockup::Bool

    mission_accomplished::Bool # State of completion for the simulation.
    worker_node_inventory::Vector{Tuple{WorkerNodeSpec,Int}}
    verbosity::String
    datalogger::DataLogger
end

"""
    Cluster(config, simulation_time, worker_node_inventory, C_Intensity_data,
            esgimmick, C_Intensity_Threshold_Value, datalogger) -> Cluster

Create the cluster to be simulated.

# Arguments
- `config`: the parsed `config.json` dictionary.
- `simulation_time`: the common simulation clock.
- `worker_node_inventory`: ordered list of `(WorkerNodeSpec, quantity)`
  pairs from [`load_cluster_inventory`](@ref).
- `C_Intensity_data`: the carbon intensity data covering the simulation.
- `esgimmick`: the energy-saving policy to run with (`"none"`, `"cd"`,
  `"cdcd"`, `"cd1721"`, `"cdcd1721"` or `"highforecast"`).
- `C_Intensity_Threshold_Value`: the carbon intensity above which the
  `highforecast` policy kicks in, in gCO2e/kWh.
- `datalogger`: the run statistics recorder (in the Python original this is
  attached after construction via `set_datalogger_handlers`).
"""
function Cluster(config::AbstractDict, simulation_time::SimulationTime,
                 worker_node_inventory::Vector{Tuple{WorkerNodeSpec,Int}},
                 C_Intensity_data::Vector{CarbonIntensityEntry},
                 esgimmick::AbstractString, C_Intensity_Threshold_Value::Real,
                 datalogger::DataLogger)
    verbosity = config["output"]["verbosity"]

    cluster = Cluster(simulation_time, WorkerNode[], Job[], 0.0, 0.0, 0.0, 0, "",
                      C_Intensity_data, String(esgimmick), 1,
                      Float64(C_Intensity_Threshold_Value), false, false, false,
                      false, worker_node_inventory, verbosity, datalogger)

    # Create worker nodes from specifications.
    for (spec, quantity) in worker_node_inventory
        for node_number in 1:quantity
            # Adds quantity number of nodes you have specified in the Simulation.
            push!(cluster.worker_nodes,
                  WorkerNode(spec, simulation_time, datalogger, @sprintf("-%03d", node_number)))
        end
    end

    if verbosity in ("high", "medium")
        log_info(get_logger(),
                 "Created cluster with $(get_number_of_nodes(cluster)) worker nodes and $(get_number_of_cores(cluster)) cores")
    end
    return cluster
end

"""
    get_number_of_nodes(cluster) -> Int

Total number of worker nodes in the cluster.
"""
get_number_of_nodes(cluster::Cluster) = length(cluster.worker_nodes)

"""
    get_number_of_cores(cluster) -> Int

Total number of job slots (threads) across all worker nodes.
"""
function get_number_of_cores(cluster::Cluster)
    total = 0
    for node in cluster.worker_nodes
        total += number_of_cores(node)
    end
    return total
end

"""
    submit_job!(cluster, job)

Add `job` to the cluster's queue and notify the data logger.
"""
function submit_job!(cluster::Cluster, job::Job)
    push!(cluster.queued_jobs, job)
    job_submit!(cluster.datalogger, job)
    return cluster
end

"""
    has_queued_jobs(cluster) -> Bool

Whether any jobs are waiting in the queue.
"""
has_queued_jobs(cluster::Cluster) = !isempty(cluster.queued_jobs)

"""
    has_running_jobs(cluster) -> Bool

Whether any worker node is currently running jobs.
"""
function has_running_jobs(cluster::Cluster)
    for worker_node in cluster.worker_nodes
        if worker_node.busy_cores > 0
            return true
        end
    end
    return false
end

"""
    cluster_occupancy(cluster) -> Float64

The fraction of all job slots that are currently busy.
"""
function cluster_occupancy(cluster::Cluster)
    coresavail = 0
    coresused = 0
    for node in cluster.worker_nodes
        coresavail += number_of_cores(node)
        coresused += node.busy_cores
    end
    return coresused / coresavail
end

"""
    update!(cluster)

Advance the cluster by one timestep: update all nodes, try to schedule
queued jobs, apply the configured energy-saving policy, and report the
timestep's energy, carbon and occupancy to the data logger. Sets
`mission_accomplished` when no jobs are running or queued.
"""
function update!(cluster::Cluster)
    # ---------------------------------
    #    Job Management Steps
    # ---------------------------------
    ### Running jobs ###
    current = get_current_datetime(cluster.simulation_time)
    day = Dates.format(current, dateformat"dd/mm/yyyy")
    if day != cluster.last_day
        cluster.days += 1
        println(day * ": Simulation Day " * string(cluster.days))
        cluster.last_day = day
    end

    for worker_node in cluster.worker_nodes
        update!(worker_node)
    end

    ### Queues ###
    remaining_jobs = Job[]

    # Try to start queued jobs
    for pending_job in cluster.queued_jobs
        scheduled = false
        # Try to fill nodes in order
        for worker_node in cluster.worker_nodes
            if can_schedule_job(worker_node, pending_job)
                start_job!(worker_node, pending_job)
                scheduled = true
                break
            end
        end

        # If we failed to allocate job to node
        if !scheduled
            push!(remaining_jobs, pending_job)
        end
    end

    cluster.queued_jobs = remaining_jobs

    # ---------------------------------
    #    Termination Check
    # ---------------------------------
    # First end condition: no jobs running and no more jobs to submit.
    # Exit this code and don't report power metrics.
    if !has_running_jobs(cluster) && !has_queued_jobs(cluster)
        cluster.mission_accomplished = true
        return cluster
    end

    # ---------------------------------
    #    Energy Saving Try Section
    # ---------------------------------
    # Compares the simulation time w.r.t. the time in the hh segment and moves a
    # pointer to the correct hh segment carbon usage.
    if current > cluster.carbondata[cluster.cditerant + 1].datetime
        cluster.cditerant += 1
    end

    # Code to clock down nodes between 5pm and 9pm every day
    if occursin("cd1721", cluster.energy_saving_try)
        if hour(current) == 17 && minute(current) < 10
            println("It's 5pm time to clock down the nodes!")
            for worker_node in cluster.worker_nodes
                clock_down!(worker_node)
                cluster.energy_saving_try == "cdcd1721" && clock_down!(worker_node)
            end
        end

        if hour(current) == 21 && minute(current) < 10
            println("It's 9pm time to clock up the nodes!")
            for worker_node in cluster.worker_nodes
                clock_up!(worker_node)
                cluster.energy_saving_try == "cdcd1721" && clock_up!(worker_node)
            end
        end
    end

    # Clocking down nodes when the next hh timesegment is forecast to have "high" usage,
    # with a +-5 gCO2e/kWh hysteresis band around the configured threshold to dampen
    # the transitions.
    if occursin("highforecast", cluster.energy_saving_try)
        if cluster.anticipate_clkdown
            for worker_node in cluster.worker_nodes
                clock_down!(worker_node)
            end
            cluster.anticipate_clkdown = false
            cluster.in_clkdown = true
        end

        if cluster.anticipate_clockup
            for worker_node in cluster.worker_nodes
                clock_up!(worker_node)
            end
            cluster.anticipate_clockup = false
            cluster.in_clkdown = false
        end

        if !cluster.in_clkdown &&
           cluster.carbondata[cluster.cditerant + 1].forecast > cluster.CIThresholdValue + 5
            println("Usage is expected to be high, next timestep we'll clock down the nodes.")
            cluster.anticipate_clkdown = true
        end

        if cluster.in_clkdown &&
           cluster.carbondata[cluster.cditerant + 1].forecast < cluster.CIThresholdValue - 5
            println("Usage is going down, next timestep we'll clock up the nodes.")
            cluster.anticipate_clockup = true
        end
    end

    # --------------------------------------------------------
    #   Export Energy, Carbon Used and Occupancy per timestep to logger
    # --------------------------------------------------------
    for worker_node in cluster.worker_nodes
        # The amount of power used by machines in a timestep in kWh.
        cluster.timestep_power_dissipated += timestep_power_dissipated(worker_node)
    end

    # Read in the carbon intensity of the grid at the timestep you are on.
    cluster.timestep_carbon_consumed = cluster.carbondata[cluster.cditerant].actual
    cluster.timestep_occupancy = cluster_occupancy(cluster)

    # Passing energy consumed and the carbon intensity per timestep
    energy_and_carbon_consumed!(cluster.datalogger,
                                cluster.timestep_power_dissipated,
                                cluster.timestep_carbon_consumed)
    # Passing occupancy per timestep
    sum_occupancy!(cluster.datalogger, cluster.timestep_occupancy)

    if Time(17, 0, 0) < Time(current) < Time(21, 0, 0)
        peaktime_energy_and_carbon_consumed!(cluster.datalogger,
                                             cluster.timestep_power_dissipated,
                                             cluster.timestep_carbon_consumed)
    end

    cluster.timestep_power_dissipated = 0.0 # Reset the accumulator every time-step
    return cluster
end
