# SPDX-License-Identifier: Apache-2.0
# Copyright 2023-2026 Deutsches Elektronen Synchrotron DESY
#                     and the University of Glasgow
# Authors: Dwayne Spiteri and Gordon Stewart.
# For more information about rights and fair use please refer to src/OracleD.jl.
# ===========================================================================

# Simulated clock, mirroring src/simulation/Time.py.

"""
    SimulationTime

The shared simulated clock.

Fields:
- `time`: the current simulated `DateTime`.
- `start_time`: the simulated `DateTime` the run started from.
- `timestep_seconds`: how far [`advance!`](@ref) moves the clock each step.
- `origin`: the real (wall-clock) `DateTime` the simulation was created at.
- `verbosity`: the configured output verbosity, used to gate log messages.
"""
mutable struct SimulationTime
    time::DateTime
    start_time::DateTime
    timestep_seconds::Int
    origin::DateTime
    verbosity::String
end

"""
    SimulationTime(config, time = nothing) -> SimulationTime

Create the simulation clock. `time` is either `nothing` (start from the
current wall-clock time, truncated to the minute) or a string of the form
`"2024-01-12 15:00"`.
"""
function SimulationTime(config::AbstractDict, time::Union{AbstractString,Nothing} = nothing)
    verbosity = get(get(config, "output", OrderedDict{String,Any}()), "verbosity", "high")
    simulation_time = SimulationTime(DateTime(0), DateTime(0), 600, now(), verbosity)

    if time === nothing
        set_to_current_time!(simulation_time)
    else
        set_to_time!(simulation_time, DateTime(time, dateformat"yyyy-mm-dd HH:MM"))
    end

    simulation_time.start_time = simulation_time.time
    simulation_time.origin = now()

    if verbosity in ("high", "medium", "low")
        log_info(get_logger(), "Set origin: $(pystr(simulation_time.origin))")
    end
    return simulation_time
end

"""
    set_to_current_time!(simulation_time)

Set the simulated clock to the current wall-clock time, truncated to the
minute (as the Python code does by round-tripping through a string).
"""
function set_to_current_time!(simulation_time::SimulationTime)
    set_to_time!(simulation_time, trunc(now(), Minute))
    return simulation_time
end

"""
    set_to_time!(simulation_time, time::DateTime)

Set the simulated clock to `time`.
"""
function set_to_time!(simulation_time::SimulationTime, time::DateTime)
    simulation_time.time = time
    if simulation_time.verbosity in ("high", "medium")
        log_info(get_logger(), "Set to time: $(pystr(simulation_time.time))")
    end
    return simulation_time
end

"""
    find_hh_segment(simulation_time, dt, instruction = "current") -> DateTime

Find the half-hour segment boundary associated with `dt`. With
`instruction == "current"` this is the boundary at or before `dt`; with
`instruction == "next"` it is the boundary strictly after `dt` (a `dt`
exactly on a boundary counts as belonging to the previous segment).
"""
function find_hh_segment(simulation_time::SimulationTime, dt::DateTime, instruction::AbstractString = "current")
    nudge = dt + Second(1) # If we start on the half-hour it counts as starting on the previous, so nudge it forward
    half_hour_ms = 30 * 60 * 1000
    pad = mod(-Dates.value(nudge), half_hour_ms)
    next_hh_seg = nudge + Millisecond(pad)
    if instruction == "next"
        return next_hh_seg
    else
        return next_hh_seg - Minute(30)
    end
end

"""
    advance!(simulation_time)

Move the simulated clock forward by one timestep.
"""
function advance!(simulation_time::SimulationTime)
    simulation_time.time += Second(simulation_time.timestep_seconds)
    log_debug(get_logger(), "Current time: $(pystr(simulation_time.time))")
    return simulation_time
end

"""
    get_start_datetime(simulation_time) -> DateTime

Get the simulated start time of the run.
"""
get_start_datetime(simulation_time::SimulationTime) = simulation_time.start_time

"""
    get_origin_datetime(simulation_time) -> DateTime

Get the real (wall-clock) time the simulation was started at.
"""
get_origin_datetime(simulation_time::SimulationTime) = simulation_time.origin

"""
    get_current_datetime(simulation_time) -> DateTime

Get the current simulated time.
"""
get_current_datetime(simulation_time::SimulationTime) = simulation_time.time

"""
    get_timestep(simulation_time) -> Int

Get the simulation timestep in seconds.
"""
get_timestep(simulation_time::SimulationTime) = simulation_time.timestep_seconds
