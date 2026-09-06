# SPDX-License-Identifier: Apache-2.0
# Copyright 2023-2026 Deutsches Elektronen Synchrotron DESY
#                     and the University of Glasgow
# Authors: Dwayne Spiteri and Gordon Stewart.
# For more information about rights and fair use please refer to src/OracleD.jl.
# ===========================================================================

# Job submission scheduling, mirroring src/jobs/JobScheduler.py.

"""
    JobScheduler

Seeds the cluster with an initial mix of jobs at construction and, if
configured, submits further job batches at regular simulated intervals.

`initial_job_mix` maps VO names (`"ATLAS"`, `"LHCb"`, `"GridPP"`, anything
else is a basic VO job) to job counts. `regular_incoming_jobs` is a list of
`(job mix, cycle length in seconds)` pairs; an empty list means no regular
submissions.
"""
mutable struct JobScheduler
    simulation_time::SimulationTime
    cluster::Cluster
    initial_job_mix::OrderedDict{String,Int}
    regular_incoming_jobs::Vector{Tuple{OrderedDict{String,Int},Int}}

    basic_job::VOJobFactory
    gridpp_job::GridPPJobFactory
    atlas_prod::ATLASJobFactory
    lhcb_prod::LHCbJobFactory

    gridpp_hourly::GridPPJobFactory
    atlas_hourly::ATLASJobFactory
    lhcb_hourly::LHCbJobFactory
end

"""
    JobScheduler(simulation_time, cluster_to_submit_jobs_to, inital_job_mix,
                 regular_incoming_jobs) -> JobScheduler

Create the scheduler and immediately seed `cluster_to_submit_jobs_to` with
the initial job mix.
"""
function JobScheduler(simulation_time::SimulationTime, cluster_to_submit_jobs_to::Cluster,
                      inital_job_mix::AbstractDict,
                      regular_incoming_jobs::Vector{Tuple{OrderedDict{String,Int},Int}})
    scheduler = JobScheduler(simulation_time, cluster_to_submit_jobs_to,
                             OrderedDict{String,Int}(String(k) => Int(v) for (k, v) in inital_job_mix),
                             regular_incoming_jobs,
                             VOJobFactory("VO-Basic-"),
                             GridPPJobFactory("GridPP-"),
                             ATLASJobFactory("ATLAS-Prod-"),
                             LHCbJobFactory("LHCb-Prod-"),
                             GridPPJobFactory("GridPP-Hourly"),
                             ATLASJobFactory("ATLAS-Hourly-"),
                             LHCbJobFactory("LHCb-Hourly-"))

    # Seed the cluster with initial jobs
    for (VO, amount) in scheduler.initial_job_mix
        factory = _production_factory(scheduler, VO)
        for _ in 1:amount
            submit_job!(scheduler.cluster, create_job!(factory))
        end
    end
    return scheduler
end

"Pick the production job factory for a VO name (basic VO jobs otherwise)."
function _production_factory(scheduler::JobScheduler, VO::AbstractString)
    VO == "ATLAS" && return scheduler.atlas_prod
    VO == "LHCb" && return scheduler.lhcb_prod
    VO == "GridPP" && return scheduler.gridpp_job
    return scheduler.basic_job
end

"Pick the regular-submission job factory for a VO name (basic VO jobs otherwise)."
function _hourly_factory(scheduler::JobScheduler, VO::AbstractString)
    VO == "ATLAS" && return scheduler.atlas_hourly
    VO == "LHCb" && return scheduler.lhcb_hourly
    VO == "GridPP" && return scheduler.gridpp_hourly
    return scheduler.basic_job
end

"""
    update!(scheduler)

Submit any regular incoming job batches whose cycle boundary coincides with
the current simulated time. Nothing is submitted while the cluster is
completely idle with an empty queue (the run is about to end).
"""
function update!(scheduler::JobScheduler)
    for (dict_VO_jobs_per_cycle, cycle) in scheduler.regular_incoming_jobs
        # Check to see if multiples of cycle number of seconds have gone by.
        timediff = get_current_datetime(scheduler.simulation_time) -
                   get_start_datetime(scheduler.simulation_time)
        cyclespassed = total_seconds(timediff) / cycle

        if !has_running_jobs(scheduler.cluster) && !has_queued_jobs(scheduler.cluster)
            continue
        end

        if cyclespassed != 0 && cyclespassed % 1 == 0
            for (VO, amount) in dict_VO_jobs_per_cycle
                factory = _hourly_factory(scheduler, VO)
                for _ in 1:amount
                    submit_job!(scheduler.cluster, create_job!(factory))
                end
            end
        end
    end
    return scheduler
end
