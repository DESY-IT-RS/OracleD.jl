# SPDX-License-Identifier: Apache-2.0
# Copyright 2023-2026 Deutsches Elektronen Synchrotron DESY
#                     and the University of Glasgow
# Authors: Dwayne Spiteri and Gordon Stewart.
# For more information about rights and fair use please refer to src/OracleD.jl.
# ===========================================================================

# Top-level simulation, mirroring src/simulation/Simulation.py.

"""
    Simulation

Owns the full simulation state: the clock, the carbon intensity data, the
cluster, the job scheduler and the data logger. Constructing a `Simulation`
performs all setup (including seeding the initial jobs) and prints the
setup banner; [`start!`](@ref) then runs the main loop to completion.
"""
mutable struct Simulation
    desiredStartTime::String
    simulation_time::SimulationTime
    simulation_length::Int
    simulation_starting_segment::DateTime
    simulation_maxfinal_segment::DateTime
    verbosity::String
    datastart_str::String
    datafinal_str::String
    CIntendata::Vector{CarbonIntensityEntry}
    CIThresholdValue::Float64
    cluster::Cluster
    datalogger::DataLogger
    jobScheduler::JobScheduler
    jobdescript::String
end

"""
    Simulation(config, inventory) -> Simulation

Set up a simulation from the parsed `config.json` dictionary and the
cluster `inventory` returned by [`load_cluster_inventory`](@ref).
"""
function Simulation(config::AbstractDict, inventory::Vector{Tuple{WorkerNodeSpec,Int}})
    # Starts the simulation at a set time, in the format '2024-01-12 15:00'.
    # If you want this to be set to the current time, set desired_starttime to nothing.
    desiredStartTime = config["Simulation"]["desired_starttime"]
    simulation_time = SimulationTime(config, desiredStartTime)
    # Desired maximum length of the simulation in seconds. (For one year 365*24*3600)
    simulation_length = config["Simulation"]["simulation_length"]
    simulation_time.timestep_seconds = config["Simulation"]["timestep"] # Simulation time step in seconds.
    # Finds the half-hour time segment to which the start of the simulation belongs
    # and the one after the end time.
    starting_segment = find_hh_segment(simulation_time, simulation_time.time)
    maxfinal_segment = find_hh_segment(simulation_time,
                                       simulation_time.time + Second(simulation_length), "next")

    verbosity = config["output"]["verbosity"]

    println("Setting up simulation.")
    println("Start date: " * Dates.format(simulation_time.start_time, dateformat"dd/mm/yy"))
    println("Timestep: " * string(get_timestep(simulation_time)) * " seconds")

    # Importing average data about the Carbon Intensity of the whole grid for the
    # maximum duration of the simulation. Carbon Intensity data is in gCO2/kWh.
    if verbosity in ("medium", "high")
        log_info(get_logger(), "Loading in Carbon Intensity Data")
    end
    datapath = config["carbon_intensity"]["folder"]
    datafile = config["carbon_intensity"]["filename"]
    # Convert start and end segment datetimes to the format found in the datafile.
    datastart_str = Dates.format(starting_segment, dateformat"yyyy-mm-ddTHH:MM:SS")
    datafinal_str = Dates.format(maxfinal_segment, dateformat"yyyy-mm-ddTHH:MM:SS")

    CIntendata = _load_carbon_intensity_data(resolve_path(joinpath(datapath, datafile)),
                                             datastart_str, datafinal_str)

    # This roughly corresponds to what is labelled 'high' in the UK (200 gCO2e/kWh);
    # for Germany it is set to 400 in the configuration.
    CIThresholdValue = config["carbon_intensity"]["high_CI_threshold"]

    # Class to record statistics. (Created before the cluster, unlike the Python
    # original, so the worker nodes can hold a concrete reference to it.)
    datalogger = DataLogger(config)

    # Create the cluster from the loaded inventory, passing the carbon data needed to
    # estimate the amount of carbon used and the energy-saving policy to apply.
    cluster = Cluster(config, simulation_time, inventory, CIntendata,
                      config["Simulation"]["savings_policy"], CIThresholdValue, datalogger)

    print("Cluster: ")
    for (spec, quantity) in cluster.worker_node_inventory
        print(spec.node_key * ": " * string(quantity) * " ")
    end
    println()
    println("Energy saving try: " * cluster.energy_saving_try)
    println("CIThresholdValue: " * pynum(CIThresholdValue))

    # Create a job scheduler to initially seed the cluster with jobs and provide jobs
    # on a regular notice.
    # Format for initial jobs is a mapping of VO name => number of jobs.
    # Format for regular jobs is a list of (VO mix, cycle length in seconds) pairs.
    jobs_refill = Tuple{OrderedDict{String,Int},Int}[]
    if !isempty(config["jobs"]["regular_incoming_mix"])
        mix = OrderedDict{String,Int}(String(k) => Int(v)
                                      for (k, v) in config["jobs"]["regular_incoming_mix"])
        push!(jobs_refill, (mix, config["jobs"]["incoming_timestep"]))
    end

    jobScheduler = JobScheduler(simulation_time, cluster, config["jobs"]["initial_mix"], jobs_refill)
    jobdescript = "RF20PMTest-50000LHCJobs-Base" # Add here what kind of jobs you are running.

    print("Jobs: ")
    for (vo, jobs) in jobScheduler.initial_job_mix
        print(vo * ": " * string(jobs))
    end
    if !isempty(jobScheduler.regular_incoming_jobs)
        print(" then ")
        for (vos, secs) in jobScheduler.regular_incoming_jobs
            for (vo, jobs) in vos
                print(vo * ": " * string(jobs) * " ")
            end
            print(" per " * string(secs / 3600) * " hours")
        end
    end
    println()

    simulation = Simulation(desiredStartTime, simulation_time, simulation_length,
                            starting_segment, maxfinal_segment, verbosity,
                            datastart_str, datafinal_str, CIntendata,
                            Float64(CIThresholdValue), cluster, datalogger,
                            jobScheduler, jobdescript)

    if verbosity in ("low", "medium", "high")
        simulation_parameters = _get_simulation_parameters(simulation, datapath, datafile, config)
        set_simulation_parameters!(datalogger, simulation_parameters)
        simulation_parameters_text = _format_simulation_parameters(simulation, simulation_parameters)
        log_info(get_logger(), "Created simulation with parameters:\n" * simulation_parameters_text)
        _write_simulation_parameters(simulation, simulation_parameters_text)
    end
    println("Simulation Started. Good Luck")

    return simulation
end

"""
    _load_carbon_intensity_data(path, datastart_str, datafinal_str)
        -> Vector{CarbonIntensityEntry}

Read the carbon intensity CSV, keeping the rows from the one whose datetime
matches `datastart_str` up to (but excluding) the one matching
`datafinal_str`. Rows with missing forecast or actual values produce the
same console warnings as the Python code (and are stored as `NaN`).
"""
function _load_carbon_intensity_data(path::AbstractString,
                                     datastart_str::AbstractString,
                                     datafinal_str::AbstractString)
    linesofimport = CarbonIntensityEntry[]
    datarequired = false
    for line in readlines(path)
        fields = split(line, ',')

        if fields[1] == datastart_str # Ignores all lines before the one you want.
            datarequired = true
        elseif fields[1] == datafinal_str # Exit file after you have reached the end time value.
            datarequired = false
        end

        if datarequired # Import data when you have found the date you want.
            forecast = actual = NaN
            if isempty(fields[2]) # If there is data missing
                println("You are missing forecast CI data for the time segment: " * fields[1])
            else
                forecast = parse(Float64, fields[2])
            end
            if isempty(fields[3]) # If there is data missing
                println("You are missing actual CI data for the time segment: " * fields[1])
            else
                actual = parse(Float64, fields[3])
            end
            push!(linesofimport,
                  CarbonIntensityEntry(DateTime(fields[1], dateformat"yyyy-mm-ddTHH:MM:SS"),
                                       forecast, actual))
        end
    end
    return linesofimport
end

"""
    _write_simulation_parameters(simulation, simulation_parameters)

Write the human-readable parameter listing to `parameters.txt` in the run
directory.
"""
function _write_simulation_parameters(simulation::Simulation, simulation_parameters::AbstractString)
    run_dir = simulation.datalogger.run_dir
    if !isempty(run_dir)
        open(joinpath(run_dir, "parameters.txt"), "w") do outfile
            write(outfile, simulation_parameters)
            write(outfile, '\n')
        end
    end
    return nothing
end

"""
    _get_simulation_parameters(simulation, carbon_data_path, carbon_data_file, config)
        -> OrderedDict

Collect the simulation parameters into an ordered dictionary for logging
and for inclusion in `summary.json`.
"""
function _get_simulation_parameters(simulation::Simulation, carbon_data_path::AbstractString,
                                    carbon_data_file::AbstractString, config::AbstractDict)
    cluster_inventory = OrderedDict{String,Int}()
    for (spec, quantity) in simulation.cluster.worker_node_inventory
        cluster_inventory[spec.node_key] = quantity
    end

    regular_jobs = Any[]
    for (job_mix, secs) in simulation.jobScheduler.regular_incoming_jobs
        push!(regular_jobs, OrderedDict{String,Any}(
            "job_mix" => job_mix,
            "incoming_timestep_seconds" => secs,
        ))
    end

    return OrderedDict{String,Any}(
        "start_time" => pystr(get_start_datetime(simulation.simulation_time)),
        "max_end_time" => pystr(get_start_datetime(simulation.simulation_time) +
                                Second(simulation.simulation_length)),
        "simulation_length_seconds" => simulation.simulation_length,
        "timestep_seconds" => get_timestep(simulation.simulation_time),
        "savings_policy" => simulation.cluster.energy_saving_try,
        "carbon_intensity" => OrderedDict{String,Any}(
            "file" => "$(carbon_data_path)$(carbon_data_file)",
            "segments" => OrderedDict{String,Any}(
                "start" => simulation.datastart_str,
                "end" => simulation.datafinal_str,
            ),
            "high_CI_threshold" => config["carbon_intensity"]["high_CI_threshold"],
        ),
        "cluster" => OrderedDict{String,Any}(
            "worker_nodes" => get_number_of_nodes(simulation.cluster),
            "worker_cores" => get_number_of_cores(simulation.cluster),
            "worker_node_inventory" => cluster_inventory,
        ),
        "jobs" => OrderedDict{String,Any}(
            "initial" => simulation.jobScheduler.initial_job_mix,
            "regular_incoming" => regular_jobs,
        ),
    )
end

"""
    _format_simulation_parameters(simulation, simulation_parameters) -> String

Format the parameter dictionary as the indented text block used in the log
file and `parameters.txt`.
"""
function _format_simulation_parameters(simulation::Simulation, simulation_parameters::AbstractDict)
    carbon_intensity = simulation_parameters["carbon_intensity"]
    cluster = simulation_parameters["cluster"]
    jobs = simulation_parameters["jobs"]
    regular_jobs = "none"
    if !isempty(jobs["regular_incoming"])
        entries = String[]
        for regular_job in jobs["regular_incoming"]
            for (vo, count) in regular_job["job_mix"]
                push!(entries, "$vo: $count per $(regular_job["incoming_timestep_seconds"]) seconds")
            end
        end
        regular_jobs = join(entries, ", ")
    end

    return join([
        "  start_time: $(simulation_parameters["start_time"])",
        "  max_end_time: $(simulation_parameters["max_end_time"])",
        "  simulation_length_seconds: $(simulation_parameters["simulation_length_seconds"])",
        "  timestep_seconds: $(simulation_parameters["timestep_seconds"])",
        "  savings_policy: $(simulation_parameters["savings_policy"])",
        "  carbon_intensity_file: $(carbon_intensity["file"])",
        "  carbon_intensity_segments: $(carbon_intensity["segments"]["start"]) to $(carbon_intensity["segments"]["end"])",
        "  high_CI_threshold: $(carbon_intensity["high_CI_threshold"])",
        "  worker_nodes: $(cluster["worker_nodes"])",
        "  worker_cores: $(cluster["worker_cores"])",
        "  worker_node_inventory: $(_format_job_mix(cluster["worker_node_inventory"]))",
        "  initial_jobs: $(_format_job_mix(jobs["initial"]))",
        "  regular_incoming_jobs: $regular_jobs",
    ], "\n")
end

"""
    _format_job_mix(job_mix) -> String

Format a `name => count` mapping as `"name: count, name: count"`, or
`"none"` when empty.
"""
function _format_job_mix(job_mix::AbstractDict)
    isempty(job_mix) && return "none"
    return join(["$vo: $jobs" for (vo, jobs) in job_mix], ", ")
end

"""
    start!(simulation)

Run the simulation main loop until either all jobs have completed or the
configured maximum simulated duration has passed, then print the summary.
"""
function start!(simulation::Simulation)
    # Permanently run nodes clocked down.
    if simulation.cluster.energy_saving_try == "cd"
        for worker_node in simulation.cluster.worker_nodes
            clock_down!(worker_node)
        end
    end
    if simulation.cluster.energy_saving_try == "cdcd"
        for worker_node in simulation.cluster.worker_nodes
            clock_down!(worker_node)
            clock_down!(worker_node)
        end
    end

    while true
        # Simulated Time
        simtottime = total_seconds(get_current_datetime(simulation.simulation_time) -
                                   get_start_datetime(simulation.simulation_time))

        # Update the state of the scheduler
        update!(simulation.jobScheduler)

        # Update the state of the cluster
        update!(simulation.cluster)

        # First end condition: when we have no jobs running and no more jobs to submit.
        # Flag is activated in the cluster update.
        if simulation.cluster.mission_accomplished
            # Real Time
            realtottime = total_seconds(now() - get_origin_datetime(simulation.simulation_time))
            print_summary(simulation.datalogger, true, simulation.jobdescript,
                          simtottime, get_timestep(simulation.simulation_time), realtottime)

            if simulation.verbosity in ("medium", "high")
                log_info(get_logger(), "No more jobs!")
                log_info(get_logger(),
                         "Ending simulation at $(pystr(get_current_datetime(simulation.simulation_time)))")
            end
            println("Simulation Finished. Check logs directory for output")
            return simulation
        end

        # Second end condition: when the configured simulated duration has passed.
        if simtottime >= simulation.simulation_length
            # Real Time
            realtottime = total_seconds(now() - get_origin_datetime(simulation.simulation_time))
            print_summary(simulation.datalogger, true, simulation.jobdescript,
                          simtottime, get_timestep(simulation.simulation_time), realtottime)

            if simulation.verbosity in ("medium", "high")
                log_info(get_logger(), "You have been running for a week! Time to stop")
                log_info(get_logger(),
                         "Ending simulation at $(pystr(get_current_datetime(simulation.simulation_time)))")
            end
            println("Simulation Finished. Check logs directory for output")
            return simulation
        end

        # Move forward in time
        advance!(simulation.simulation_time)
    end
end
