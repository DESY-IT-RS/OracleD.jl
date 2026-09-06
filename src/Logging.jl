# SPDX-License-Identifier: Apache-2.0
# Copyright 2023-2026 Deutsches Elektronen Synchrotron DESY
#                     and the University of Glasgow
# Authors: Dwayne Spiteri and Gordon Stewart.
# For more information about rights and fair use please refer to src/OracleD.jl.
# ===========================================================================

# File logging for simulation runs, mirroring src/util/Logging.py.

"Verbosity values accepted in the `output` section of `config.json`."
const VALID_VERBOSITY_LEVELS = ("low", "medium", "high")

"""
    SimLogger

A minimal file logger for the simulation, playing the role of the Python
`logging` logger named `CLUSTERSIM`.

Until [`configure_logger!`](@ref) is called the logger is unconfigured and
all messages are dropped (just as the Python logger has no handler before
`configure_logger()` runs). Afterwards messages are appended to
`simulation.log` in the run directory.
"""
mutable struct SimLogger
    configured::Bool
    debug_enabled::Bool
    io::IOStream

    function SimLogger()
        logger = new()
        logger.configured = false
        logger.debug_enabled = false
        return logger
    end
end

"The process-wide simulation logger instance."
const LOGGER = SimLogger()

"""
    get_logger() -> SimLogger

Return the shared simulation logger, mirroring the Python
`Logging.get_logger()` helper.
"""
get_logger() = LOGGER

"""
    configure_logger!(logger::SimLogger, debug::Bool, run_dir::AbstractString)

Point `logger` at `<run_dir>/simulation.log` and set whether debug messages
are recorded. Any previously opened log file is closed first.
"""
function configure_logger!(logger::SimLogger, debug::Bool, run_dir::AbstractString)
    if logger.configured
        close(logger.io)
    end
    logger.io = open(joinpath(run_dir, "simulation.log"), "a")
    logger.debug_enabled = debug
    logger.configured = true
    return logger
end

"""
    close_logger!(logger::SimLogger)

Close the log file (if open) and return the logger to its unconfigured
state.
"""
function close_logger!(logger::SimLogger)
    if logger.configured
        close(logger.io)
        logger.configured = false
    end
    return logger
end

function _write_log(logger::SimLogger, level::AbstractString, message::AbstractString)
    logger.configured || return nothing
    timestamp = Dates.format(now(), dateformat"yyyy-mm-dd HH:MM:SS,sss")
    write(logger.io, "$timestamp  $level  $message\n")
    flush(logger.io)
    return nothing
end

"""
    log_info(logger::SimLogger, message)

Record an INFO-level message. Dropped if the logger is not yet configured.
"""
log_info(logger::SimLogger, message::AbstractString) = _write_log(logger, "INFO", message)

"""
    log_warning(logger::SimLogger, message)

Record a WARNING-level message. Dropped if the logger is not yet configured.
"""
log_warning(logger::SimLogger, message::AbstractString) = _write_log(logger, "WARNING", message)

"""
    log_debug(logger::SimLogger, message)

Record a DEBUG-level message. Only written when the logger was configured
with `debug = true`.
"""
function log_debug(logger::SimLogger, message::AbstractString)
    logger.debug_enabled || return nothing
    return _write_log(logger, "DEBUG", message)
end

"""
    normalize_verbosity(raw_verbosity, default = "high") -> String

Map the configured verbosity onto one of $(VALID_VERBOSITY_LEVELS),
returning `default` when the value is missing or invalid.
"""
function normalize_verbosity(raw_verbosity, default::AbstractString = "high")
    verbosity = raw_verbosity === nothing ? String(default) : string(raw_verbosity)
    verbosity in VALID_VERBOSITY_LEVELS || return String(default)
    return verbosity
end

"""
    default_run_label(config) -> String

Build the fallback run label `<total initial jobs>jobs_<savings policy>`
used when `output.run_label` is not present in the configuration.
"""
function default_run_label(config::AbstractDict)
    initial_jobs = get(get(config, "jobs", OrderedDict{String,Any}()), "initial_mix", OrderedDict{String,Any}())
    total_jobs = isempty(initial_jobs) ? 0 : sum(values(initial_jobs))
    policy = get(get(config, "Simulation", OrderedDict{String,Any}()), "savings_policy", "unknown-policy")
    return "$(total_jobs)jobs_$(policy)"
end

"""
    slugify(value) -> String

Reduce `value` to a lower-case filesystem-friendly slug: runs of
non-alphanumeric characters become `_`, leading/trailing `_` are stripped,
and an empty result becomes `"simulation"`.
"""
function slugify(value)
    slug = replace(string(value), r"[^A-Za-z0-9]+" => "_")
    slug = strip(slug, '_')
    slug = lowercase(slug)
    return isempty(slug) ? "simulation" : String(slug)
end

"""
    create_run_directory(config) -> String

Create a unique per-run output directory named
`<timestamp>_<run label slug>` below `output.log_dir` (default
`logs/runs`), store it in `config["output"]["run_dir"]` and return it.
"""
function create_run_directory(config::AbstractDict)
    output_cfg = get!(config, "output", OrderedDict{String,Any}())
    base_dir = resolve_path(get(output_cfg, "log_dir", joinpath("logs", "runs")))
    mkpath(base_dir)

    timestamp = Dates.format(now(), dateformat"yyyy-mm-dd_HH-MM-SS")
    run_label = get(output_cfg, "run_label", default_run_label(config))
    run_dir = joinpath(base_dir, "$(timestamp)_$(slugify(run_label))")

    suffix = 1
    unique_run_dir = run_dir
    while ispath(unique_run_dir)
        suffix += 1
        unique_run_dir = "$(run_dir)_$(suffix)"
    end

    mkpath(unique_run_dir)
    output_cfg["run_dir"] = unique_run_dir
    return unique_run_dir
end
