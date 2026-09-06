# SPDX-License-Identifier: Apache-2.0
# Copyright 2023-2026 Deutsches Elektronen Synchrotron DESY
#                     and the University of Glasgow
# Authors: Dwayne Spiteri and Gordon Stewart.
# For more information about rights and fair use please refer to src/OracleD.jl.
# ===========================================================================

# Job description, mirroring src/jobs/Jobs.py.

"Sentinel used for `Job` start/end times that have not been set yet."
const UNSET_TIME = typemin(DateTime)

"""
    Job

A single unit of work submitted to the cluster.

Fields:
- `name`: unique job name, e.g. `"ATLAS-Prod-17"`.
- `duration`: the job length in seconds (scaled by node performance when
  the job starts).
- `memory_req`: requested memory in GB **per core**.
- `cores_req`: number of cores (threads) requested.
- `start_time` / `end_time`: simulated schedule of the job, `UNSET_TIME`
  until the job has been started. Use [`set_duration!`](@ref),
  [`set_start_time!`](@ref) and [`set_end_time!`](@ref) to keep them
  consistent.
"""
mutable struct Job
    name::String
    duration::Float64
    memory_req::Float64
    cores_req::Int
    start_time::DateTime
    end_time::DateTime
end

"""
    Job(name, duration, memory_req = 1, cores_req = 1) -> Job

Create a job with unset start and end times.
"""
Job(name::AbstractString, duration::Real, memory_req::Real = 1, cores_req::Integer = 1) =
    Job(String(name), Float64(duration), Float64(memory_req), Int(cores_req), UNSET_TIME, UNSET_TIME)

Base.show(io::IO, job::Job) = print(io, job.name)

"Convert a duration in (possibly fractional) seconds to a `Millisecond` period."
_duration_period(duration::Real) = Millisecond(round(Int64, duration * 1000))

"""
    set_duration!(job, value)

Set the job duration in seconds. If the job has already started, its end
time is recomputed from the start time and the new duration.
"""
function set_duration!(job::Job, value::Real)
    job.duration = Float64(value)
    if job.start_time != UNSET_TIME
        job.end_time = job.start_time + _duration_period(job.duration)
    end
    return job
end

"""
    set_start_time!(job, value::DateTime)

Set the job start time; the end time is derived from the current duration.
"""
function set_start_time!(job::Job, value::DateTime)
    job.start_time = value
    job.end_time = job.start_time + _duration_period(job.duration)
    return job
end

"""
    set_end_time!(job, value::DateTime)

Directly set the job end time, for processes that change the life of a job
while it is in progress (e.g. clocking a node up or down).
"""
function set_end_time!(job::Job, value::DateTime)
    job.end_time = value
    return job
end
