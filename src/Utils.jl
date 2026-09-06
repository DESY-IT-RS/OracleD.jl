# SPDX-License-Identifier: Apache-2.0
# Copyright 2023-2026 Deutsches Elektronen Synchrotron DESY
#                     and the University of Glasgow
# Authors: Dwayne Spiteri and Gordon Stewart.
# For more information about rights and fair use please refer to src/OracleD.jl.
# ===========================================================================

# Generic utilities shared across the OracleD sources.

"""
    project_root() -> String

Return the absolute path of the ORACLE-D repository root, i.e. the parent
directory of the `OracleD.jl` package directory.

All relative paths found in `config.json` (data files, log directories) are
resolved against this directory, so the simulation behaves the same
regardless of the current working directory.
"""
project_root() = dirname(dirname(dirname(abspath(@__FILE__))))

"""
    resolve_path(path) -> String

Resolve `path` against [`project_root`](@ref) unless it is already absolute.
"""
resolve_path(path::AbstractString) = isabspath(path) ? String(path) : joinpath(project_root(), path)

"""
    weighted_choice(values, probabilities) -> eltype(values)

Draw a single random element from `values` with the given (normalised)
`probabilities`. This is the equivalent of the Python
`numpy.random.choice(values, p=probabilities)` call used to model the LHCb
job-length distribution.
"""
function weighted_choice(values::AbstractVector, probabilities::AbstractVector{<:Real})
    length(values) == length(probabilities) ||
        throw(ArgumentError("values and probabilities must have the same length"))
    r = rand() * sum(probabilities)
    acc = 0.0
    for (v, p) in zip(values, probabilities)
        acc += p
        if r < acc
            return v
        end
    end
    return values[end]
end

"""
    gauss(mu, sigma) -> Float64

Sample from a normal distribution with mean `mu` and standard deviation
`sigma`, mirroring Python's `random.gauss(mu, sigma)`.
"""
gauss(mu::Real, sigma::Real) = mu + sigma * randn()

"""
    pystr(dt::DateTime) -> String

Format a `DateTime` the way Python's `str(datetime)` does, e.g.
`"2024-01-16 16:00:00"`. Milliseconds are included only when non-zero.
"""
function pystr(dt::DateTime)
    if millisecond(dt) == 0
        return Dates.format(dt, dateformat"yyyy-mm-dd HH:MM:SS")
    end
    return Dates.format(dt, dateformat"yyyy-mm-dd HH:MM:SS.sss")
end

"""
    pynum(x) -> String

Format a number the way Python's string interpolation would: integers
without a decimal point, everything else via `string`. Used where the Python
code prints values taken straight from `config.json`.
"""
pynum(x::Integer) = string(x)
pynum(x::Real) = isinteger(x) ? string(Int(x)) : string(x)

"""
    total_seconds(period) -> Float64

Return the total number of seconds in a `Dates` period difference between
two `DateTime`s, mirroring Python's `timedelta.total_seconds()`.
"""
total_seconds(period::Dates.Period) = Dates.value(Millisecond(period)) / 1000
