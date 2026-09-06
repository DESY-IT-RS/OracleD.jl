# SPDX-License-Identifier: Apache-2.0
# Copyright 2023-2026 Deutsches Elektronen Synchrotron DESY
#                     and the University of Glasgow
# Authors: Dwayne Spiteri and Gordon Stewart.
# For more information about rights and fair use please refer to src/OracleD.jl.
# ===========================================================================

# Per-VO job factories, mirroring src/jobs/VOJobFactory.py.

"""
    AbstractVOJobFactory

Common supertype of the per-VO job factories. Each concrete factory stores
the same state (tag, running job number, memory per core and the cached
core request) and specialises [`get_duration`](@ref) and
[`require_cores!`](@ref).

!!! note
    As in the Python original, the number of cores drawn for the *first*
    job is cached in `cores_requested` and reused for every subsequent job
    from the same factory. This quirk is preserved deliberately so the
    Julia simulation reproduces the Python results.
"""
abstract type AbstractVOJobFactory end

"""
    VOJobFactory(tag, RAM_per_core = 1, cores_req = 0) -> VOJobFactory

Basic VO job factory producing short "empty pilot" jobs of ~15 minutes,
with a 50% chance that all its jobs require 8 cores rather than 1.
A `cores_req` of `0` means "not yet decided" (Python `None`).
"""
mutable struct VOJobFactory <: AbstractVOJobFactory
    tag::String
    job_number::Int
    memory_required_GB_per_core::Float64
    cores_requested::Int
end
VOJobFactory(tag::AbstractString, RAM_per_core::Real = 1, cores_req::Integer = 0) =
    VOJobFactory(String(tag), 0, Float64(RAM_per_core), Int(cores_req))

"""
    GridPPJobFactory(tag, RAM_per_core = 2, cores_req = 0) -> GridPPJobFactory

Test VO factory that fixes all job variables: every job runs for exactly
5 hours on a single core (unless `cores_req` is given).
"""
mutable struct GridPPJobFactory <: AbstractVOJobFactory
    tag::String
    job_number::Int
    memory_required_GB_per_core::Float64
    cores_requested::Int
end
GridPPJobFactory(tag::AbstractString, RAM_per_core::Real = 2, cores_req::Integer = 0) =
    GridPPJobFactory(String(tag), 0, Float64(RAM_per_core), Int(cores_req))

"""
    ATLASJobFactory(tag, RAM_per_core = 2, cores_req = 0) -> ATLASJobFactory

ATLAS production job factory: ~42% short pilot jobs (~15 min), otherwise
~5 hour jobs; ~80% chance the factory produces 8-core jobs.
"""
mutable struct ATLASJobFactory <: AbstractVOJobFactory
    tag::String
    job_number::Int
    memory_required_GB_per_core::Float64
    cores_requested::Int
end
ATLASJobFactory(tag::AbstractString, RAM_per_core::Real = 2, cores_req::Integer = 0) =
    ATLASJobFactory(String(tag), 0, Float64(RAM_per_core), Int(cores_req))

"""
    LHCbJobFactory(tag, RAM_per_core = 4, cores_req = 0) -> LHCbJobFactory

LHCb production job factory: ~22% short pilot jobs, otherwise job lengths
drawn from a Landau-like distribution between 9.5 and 18.5 hours; ~10%
chance the factory produces 8-core jobs.
"""
mutable struct LHCbJobFactory <: AbstractVOJobFactory
    tag::String
    job_number::Int
    memory_required_GB_per_core::Float64
    cores_requested::Int
end
LHCbJobFactory(tag::AbstractString, RAM_per_core::Real = 4, cores_req::Integer = 0) =
    LHCbJobFactory(String(tag), 0, Float64(RAM_per_core), Int(cores_req))

"""
    get_duration(factory) -> Float64

Sample a job duration in seconds for a job from `factory`.
"""
function get_duration(factory::VOJobFactory)
    # ~15 mins for an empty pilot to run.
    durationmins = gauss(15, 5)
    if durationmins < 5
        durationmins = 5.0
    end
    return durationmins * 60
end

function get_duration(factory::GridPPJobFactory)
    # Fixed length of 5 hours to test that other things work.
    durationmins = 300
    return durationmins * 60
end

function get_duration(factory::ATLASJobFactory)
    seed = floor(Int, 600 * rand())
    if seed < 251 # empty pilot jobs
        durationmins = gauss(15, 5) # ~15 mins for an empty pilot to run.
    else
        durationmins = gauss(300, 100) # Average job length is about 5 hours.
    end
    if durationmins < 5
        durationmins = 5.0
    end
    return durationmins * 60
end

function get_duration(factory::LHCbJobFactory)
    seed = floor(Int, 100 * rand())
    if seed < 22 # empty pilot jobs (21% of the time)
        durationmins = gauss(15, 5) # ~15 mins for an empty pilot to run.
    else
        # Models the landau distribution of LHCb jobs with a range of 9.5 to 18.5 hours.
        jobdisthours = weighted_choice(collect(9.5:1.0:18.5),
                                       [1/90, 2.5/90, 21/90, 30/90, 15/90, 7.5/90, 7/90, 3/90, 2/90, 1/90])
        durationmins = 60 * jobdisthours
    end
    if durationmins < 5
        durationmins = 5.0
    end
    return durationmins * 60
end

"""
    require_cores!(factory) -> Int

Return the number of cores jobs from this factory request. On the first
call (when `cores_requested == 0`) the value is drawn randomly according to
the VO's multi-core probability and cached for all later jobs.
"""
function require_cores!(factory::VOJobFactory)
    if factory.cores_requested == 0
        core_num_seed = randn()
        factory.cores_requested = core_num_seed < 0 ? 8 : 1 # Random 50% chance of requiring 8 or 1 core.
    end
    return factory.cores_requested
end

function require_cores!(factory::GridPPJobFactory)
    # 100% chance of requiring 1 core if nothing is specified.
    if factory.cores_requested == 0
        factory.cores_requested = 1
    end
    return factory.cores_requested
end

function require_cores!(factory::ATLASJobFactory)
    if factory.cores_requested == 0
        core_num_seed = rand(0:101)
        factory.cores_requested = core_num_seed < 80 ? 8 : 1 # 80% chance of requiring 8 cores.
    end
    return factory.cores_requested
end

function require_cores!(factory::LHCbJobFactory)
    if factory.cores_requested == 0
        core_num_seed = rand(0:101)
        factory.cores_requested = core_num_seed < 10 ? 8 : 1 # 10% chance of requiring 8 cores.
    end
    return factory.cores_requested
end

"""
    debug_label(factory) -> String

The debug-log message emitted when `factory` creates a job.
"""
debug_label(::VOJobFactory) = "Creating job"
debug_label(::GridPPJobFactory) = "Creating GridPP production job"
debug_label(::ATLASJobFactory) = "Creating ATLAS production job"
debug_label(::LHCbJobFactory) = "Creating LHCb production job"

"""
    create_job!(factory) -> Job

Create the next [`Job`](@ref) from `factory`, advancing its job counter.
"""
function create_job!(factory::AbstractVOJobFactory)
    log_debug(get_logger(), debug_label(factory))
    factory.job_number += 1
    name = "$(factory.tag)$(factory.job_number)"
    return Job(name, get_duration(factory), factory.memory_required_GB_per_core, require_cores!(factory))
end
