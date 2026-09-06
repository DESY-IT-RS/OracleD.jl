# SPDX-License-Identifier: Apache-2.0
# Copyright 2023-2026 Dwayne Spiteri and Gordon Stewart.
# For more information about rights and fair use please refer to src/OracleD.jl.
# ===========================================================================

# Worker node model, mirroring src/cluster/WorkerNode.py.
#
# The Python code generates a WorkerNode *subclass* per machine type at
# runtime. In Julia that role is played by `WorkerNodeSpec`: a plain
# immutable description of a machine type from which any number of
# `WorkerNode` instances can be built.

"""
    WorkerNodeSpec

Immutable description of one machine type in the cluster inventory, the
Julia counterpart of the dynamically generated Python `WorkerNode`
subclasses.

Fields:
- `node_key`: name of the machine type, e.g. `"DESYT3_0"`; used as the
  hostname prefix of instantiated nodes.
- `threads`: number of (hyper)threads per machine.
- `memory_gb`: RAM per machine in GB.
- `idle_power_w`: average instantaneous power dissipated by an idle node in W.
- `frequencies`: available CPU frequencies in GHz, sorted descending (the
  first entry is the default maximum).
- `powers_w`: average instantaneous power dissipated in W by a fully
  occupied node at each frequency.
- `hepscores`: HEPScore23 benchmark score at each frequency.
- `system`, `cpu_model`, `install_year`: descriptive metadata.
"""
struct WorkerNodeSpec
    node_key::String
    threads::Int
    memory_gb::Float64
    idle_power_w::Float64
    frequencies::Vector{Float64}
    powers_w::Vector{Float64}
    hepscores::Vector{Float64}
    system::String
    cpu_model::String
    install_year::String
end

"""
    WorkerNodeSpec(node_key, threads, memory_gb, idle_power_w, freq_dep_specs;
                   system = "Arthur C Clarke", cpu_model = "HAL 9000",
                   install_year = "3001") -> WorkerNodeSpec

Build a machine-type specification from a frequency dependence mapping
`freq_dep_specs :: Dict{Float64,Tuple{Float64,Float64}}` of
`frequency GHz => (power W, HEPScore)`, sorted to descending frequency
order (highest frequency is the default).
"""
function WorkerNodeSpec(node_key::AbstractString, threads::Integer, memory_gb::Real,
                        idle_power_w::Real, freq_dep_specs::AbstractDict{<:Real,<:Tuple};
                        system::AbstractString = "Arthur C Clarke",
                        cpu_model::AbstractString = "HAL 9000",
                        install_year::AbstractString = "3001")
    frequencies = Float64[]
    powers_w = Float64[]
    hepscores = Float64[]
    for freq in sort(collect(keys(freq_dep_specs)); rev = true)
        power, hepscore = freq_dep_specs[freq]
        push!(frequencies, freq)
        push!(powers_w, power)
        push!(hepscores, hepscore)
    end
    return WorkerNodeSpec(String(node_key), Int(threads), Float64(memory_gb), Float64(idle_power_w),
                          frequencies, powers_w, hepscores,
                          String(system), String(cpu_model), String(install_year))
end

"""
    WorkerNode

A simulated worker node.

Power-related quantities are stored as energy use per second (the W values
from the specification divided by 3600, as in the Python code). Job
durations are rescaled when jobs start according to the node's HEPScore
relative to the reference machine (see `fixed_duration_multiplier`), and
again when the node is clocked up or down (`dynamic_duration_multiplier`).
"""
mutable struct WorkerNode
    simulation_time::SimulationTime
    hostname::String
    number_of_threads::Int
    physical_cores::Float64 # threads/2, used for power-scaling purposes
    busy_cores::Int
    maximum_RAM::Float64
    busy_RAM::Float64
    jobs::Vector{Job}

    powerusage_idle::Float64
    frequencies::Vector{Float64}
    powers_available::Vector{Float64}
    HEPScores::Vector{Float64}
    running_frequency::Float64
    previous_frequency::Float64
    max_HEPScore::Float64
    powerusage_active::Float64

    fixed_duration_multiplier::Float64
    dynamic_duration_multiplier::Float64

    system::String
    cpu::String
    year::String

    datalogger::DataLogger
end

"""
    WorkerNode(spec, simulation_time, datalogger, hostname_suffix = "") -> WorkerNode

Instantiate a worker node of the machine type described by `spec`. The
node's hostname is `spec.node_key * hostname_suffix`.
"""
function WorkerNode(spec::WorkerNodeSpec, simulation_time::SimulationTime,
                    datalogger::DataLogger, hostname_suffix::AbstractString = "")
    frequencies = copy(spec.frequencies)
    powers_available = spec.powers_w ./ 3600 # Energy use (needs to convert from hours to seconds)
    hepscores = copy(spec.hepscores)
    max_hepscore = hepscores[1]
    return WorkerNode(simulation_time,
                      spec.node_key * hostname_suffix,
                      spec.threads,
                      spec.threads / 2, # Differentiate for power consumption purposes.
                      0,
                      spec.memory_gb,
                      0.0,
                      Job[],
                      spec.idle_power_w / 3600,
                      frequencies,
                      powers_available,
                      hepscores,
                      frequencies[1],
                      frequencies[1],
                      max_hepscore,
                      powers_available[1],
                      # The relative HEPScore on this machine running a standard benchmark
                      # compared to a 2*AMD Milano (d22) node at max frequency.
                      1939.60 / max_hepscore,
                      1.0,
                      spec.system,
                      spec.cpu_model,
                      spec.install_year,
                      datalogger)
end

"""
    number_of_cores(worker_node) -> Int

Number of job slots on the node. As in the Python original this is the
number of *threads* (people interchange cores with threads when counting
job slots); the physical-core count used for power scaling is the
`physical_cores` field.
"""
number_of_cores(worker_node::WorkerNode) = worker_node.number_of_threads

"""
    is_awaiting_jobs(worker_node) -> Bool

Whether the node has at least one free core.
"""
is_awaiting_jobs(worker_node::WorkerNode) = get_free_core_count(worker_node) > 0

"""
    get_free_core_count(worker_node) -> Int

Number of currently unoccupied cores (threads) on the node.
"""
get_free_core_count(worker_node::WorkerNode) = worker_node.number_of_threads - worker_node.busy_cores

"""
    get_memory_available(worker_node) -> Float64

Amount of currently unallocated RAM on the node in GB.
"""
get_memory_available(worker_node::WorkerNode) = worker_node.maximum_RAM - worker_node.busy_RAM

"""
    can_schedule_job(worker_node, job) -> Bool

Whether `job` fits on the node right now. Note that, as in the Python
original, only the per-core memory request is checked against the free
memory (not `memory_req * cores_req`).
"""
function can_schedule_job(worker_node::WorkerNode, job::Job)
    job.cores_req > get_free_core_count(worker_node) && return false
    job.memory_req > get_memory_available(worker_node) && return false
    return true
end

"""
    set_running_frequency!(worker_node, value)

Set the node's running frequency, recording the previous one. Throws an
error if `value` is not one of the node's available frequencies.
"""
function set_running_frequency!(worker_node::WorkerNode, value::Real)
    value in worker_node.frequencies ||
        error("The machine cannot be set to run at this frequency.")
    worker_node.previous_frequency = worker_node.running_frequency
    worker_node.running_frequency = Float64(value)
    return worker_node
end

"""
    start_job!(worker_node, job)

Start `job` on the node: stamp its start time, rescale its sampled duration
by the node's performance (fixed multiplier and current-frequency HEPScore)
and allocate cores and memory.
"""
function start_job!(worker_node::WorkerNode, job::Job)
    set_start_time!(job, get_current_datetime(worker_node.simulation_time))
    # Adjust sampled duration according to worker node performance
    set_duration!(job, job.duration * worker_node.fixed_duration_multiplier)
    # Adjust end times based on how the nodes are running
    freqindex = findfirst(==(worker_node.running_frequency), worker_node.frequencies)
    currentHEPScore = worker_node.HEPScores[freqindex]
    set_duration!(job, job.duration * worker_node.max_HEPScore / currentHEPScore)

    job_start!(worker_node.datalogger, job, worker_node)
    push!(worker_node.jobs, job)
    worker_node.busy_cores += job.cores_req
    worker_node.busy_RAM += job.memory_req * job.cores_req
    return worker_node
end

"""
    timestep_power_dissipated(worker_node) -> Float64

The amount of energy used by the machine in one timestep, in kWh. Machines
always draw at least the idle power; above that, power scales linearly with
the number of busy physical cores up to the fully-active power.
"""
function timestep_power_dissipated(worker_node::WorkerNode)
    baseusage = worker_node.powerusage_idle
    maxusage = worker_node.powerusage_active
    physicalcores = worker_node.physical_cores
    coresactive = worker_node.busy_cores # Actually the number of threads active in a HT system.

    # In a HT system, each core runs two threads and the load is usually balanced, so to a good
    # approximation the max energy output is when half the threads are in use, one running on
    # every core. A core roughly will not consume more power by running 2 threads instead of 1.
    scaling = coresactive / physicalcores
    if scaling > 1
        scaling = 1.0
    end

    inst_pow_disp = maxusage * scaling
    if inst_pow_disp < baseusage
        inst_pow_disp = baseusage # Can't expend less power than the idle.
    end

    inst_pow_disp_timestep = inst_pow_disp * get_timestep(worker_node.simulation_time) # Scale up from power per second to power per timestep.
    return inst_pow_disp_timestep / 1000 # Convert from Wh to kWh.
end

"""
    change_clock_speed!(worker_node, clockspeed)

Change the clock frequency of the node to `clockspeed` (GHz) and rescale
the remaining time of every running job by the current dynamic duration
multiplier.
"""
function change_clock_speed!(worker_node::WorkerNode, clockspeed::Real)
    set_running_frequency!(worker_node, clockspeed)

    current = get_current_datetime(worker_node.simulation_time)
    for job in worker_node.jobs
        # Change the amount of time left on all jobs running on the node
        time_left_ms = Dates.value(job.end_time - current)
        new_duration_ms = round(Int64, time_left_ms * worker_node.dynamic_duration_multiplier)
        set_end_time!(job, current + Millisecond(new_duration_ms))
    end
    return worker_node
end

"""
    clock_down!(worker_node)

Decrease the frequency of the node by one available frequency step,
adjusting its active power draw and stretching running jobs by the ratio of
HEPScores. Prints a message if the node is already at its lowest frequency.
"""
function clock_down!(worker_node::WorkerNode)
    freqindex = findfirst(==(worker_node.running_frequency), worker_node.frequencies)
    if freqindex + 1 <= length(worker_node.frequencies)
        # Change the power setting according to the frequency
        worker_node.powerusage_active = worker_node.powers_available[freqindex + 1]
        # Alter the length of a job by the ratio of the HEPScore in the frequency you are
        # moving to w.r.t the one you are moving from
        worker_node.dynamic_duration_multiplier =
            worker_node.HEPScores[freqindex] / worker_node.HEPScores[freqindex + 1]
        change_clock_speed!(worker_node, worker_node.frequencies[freqindex + 1])
    else
        println("This machine, $(worker_node.hostname), is already running at its lowest frequency: $(worker_node.frequencies[freqindex]) GHz.")
    end
    return worker_node
end

"""
    clock_up!(worker_node)

Increase the frequency of the node by one available frequency step,
adjusting its active power draw and shrinking running jobs by the ratio of
HEPScores. Prints a message if the node is already at its maximum frequency.
"""
function clock_up!(worker_node::WorkerNode)
    freqindex = findfirst(==(worker_node.running_frequency), worker_node.frequencies)
    if freqindex - 1 >= 1
        # Change the power setting according to the frequency
        worker_node.powerusage_active = worker_node.powers_available[freqindex - 1]
        # Change the length of a job by the job-extension-factor in the frequency you are moving from
        worker_node.dynamic_duration_multiplier =
            worker_node.HEPScores[freqindex] / worker_node.HEPScores[freqindex - 1]
        change_clock_speed!(worker_node, worker_node.frequencies[freqindex - 1])
    else
        println("This machine, $(worker_node.hostname), is already running at its maximum frequency: $(worker_node.frequencies[freqindex]) GHz.")
    end
    return worker_node
end

"""
    update!(worker_node)

Advance the node by one timestep: finish any jobs whose end time has been
reached, freeing their cores and memory and reporting them to the data
logger.

The recorded duration of a finished job reproduces Python's
`timedelta.seconds`, i.e. the whole-seconds part of the elapsed time with
full days discarded.
"""
function update!(worker_node::WorkerNode)
    current = get_current_datetime(worker_node.simulation_time)
    remaining_jobs = Job[]

    for job in worker_node.jobs
        # Has the job finished?
        if job.end_time <= current
            # Update the duration of the job if it has been edited due to clockdowns.
            # (This is Python's timedelta.seconds: whole days are dropped.)
            elapsed_seconds = fld(Dates.value(job.end_time - job.start_time), 1000)
            set_duration!(job, Float64(mod(elapsed_seconds, 86400)))
            job_finish!(worker_node.datalogger, job, worker_node)
            worker_node.busy_RAM -= job.memory_req * job.cores_req # Free up the memory now it is no longer being used.
            worker_node.busy_cores -= job.cores_req # Free up the cores now they are no longer being used.
        else
            push!(remaining_jobs, job)
        end
    end

    worker_node.jobs = remaining_jobs
    return worker_node
end
