# SPDX-License-Identifier: Apache-2.0
# ========================================================================
# Copyright 2023-2026 Deutsches Elektronen Synchrotron DESY
#                     and the University of Glasgow
# Authors: Dwayne Spiteri and Gordon Stewart.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#
# The main repository houses LICENSE and NOTICE files for your information
# ========================================================================

"""
    OracleD

The Optimised Resource Analysis and Carbon Legacy Estimator for Data
centres (ORACLE-D) — a simulator of compute clusters, the jobs they run and
the energy and carbon they consume in doing so.

This is the Julia migration of the original Python implementation; see the
repository `README.md` for the full description and `doc/` for migration
notes. Run the baseline simulation with

    julia --project src/OracleD.jl

or, from the Julia REPL, `using OracleD; OracleD.main()`.
"""
module OracleD

using Dates
using Printf
using Random
using JSON
using OrderedCollections

include("Utils.jl")
include("Logging.jl")
include("Time.jl")
include("Jobs.jl")
include("VOJobFactory.jl")
include("DataLogger.jl")
include("WorkerNode.jl")
include("ClusterLoader.jl")
include("Cluster.jl")
include("JobScheduler.jl")
include("Simulation.jl")

"""
    main() -> Simulation

Entry point of the baseline simulation, the counterpart of the Python
`src/Main.py` script: read `config.json` from the repository root, load the
cluster inventory, create the run directory and logger, then build and run
the [`Simulation`](@ref).
"""
function main()
    config_path = joinpath(project_root(), "config.json")
    config = JSON.parsefile(config_path; dicttype = OrderedDict{String,Any})

    inventory = load_cluster_inventory(
        config["cluster"]["inventory_csv"],
        config["cluster"]["frequency_csv"];
        cluster_name = config["cluster"]["cluster_name"],
        strict = config["cluster"]["strict"],
    )

    output_cfg = get!(config, "output", OrderedDict{String,Any}())
    verbosity_raw = get(output_cfg, "verbosity", nothing)
    output_cfg["verbosity"] = normalize_verbosity(verbosity_raw)

    debug = get(output_cfg, "debug", false)

    run_dir = create_run_directory(config)
    open(joinpath(run_dir, "config.json"), "w") do outfile
        # JSON.print already ends indented output with a newline, matching json.dump + '\n'.
        JSON.print(outfile, config, 4)
    end

    logger = get_logger()
    configure_logger!(logger, debug, run_dir)
    log_info(logger, "Writing run output to $run_dir")

    if verbosity_raw != output_cfg["verbosity"]
        log_warning(logger, "Invalid verbosity value '$verbosity_raw', defaulting to 'high'")
    end

    Random.seed!(config["Simulation"]["rng_seed"])
    sim = Simulation(config, inventory)

    start!(sim)
    return sim
end

end # module OracleD

if abspath(PROGRAM_FILE) == @__FILE__
    OracleD.main()
end
