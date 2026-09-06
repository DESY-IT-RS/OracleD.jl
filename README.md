# The ORACLE-D Framework (Julia — OracleD.jl)

## Description
The Optimised Resource Analysis and Carbon Legacy Estimator for Data centres (ORACLE-D) Framework is a framework for simulating different types of compute nodes, seeing how they deal with incoming jobs, and how much power is consumed/carbon emitted in doing so. The initial idea was to use this to investigate how energy consumption and/or carbon usage can be reduced at an average Grid computing site. This software is a Julia implementation (`OracleD.jl`, module `OracleD`) of the original Python3 version, written so that it behaves the same way and produces the same output as the Python version; see `ORACLE-D-main/README.md` in the parent repository for the full description of the simulation model, configuration options and data file formats.

## Project status
Version 1.1.0 (see `OracleD.jl/Project.toml`). The Julia package mirrors the release versions, features and configuration format of the Python implementation.

## Current Functionality
The simulation framework is designed to simulate the amount of energy and carbon used* when a computing site[1] performing work[2] is run in different ways[3]. The simulation is modular so [1], [2] and [3] are easily editable.

\* All the nodes that make up the computing site output the amount of energy they have used every time-step (10 minutes by default); this is also multiplied by the carbon intensity of the grid (see the `carbon_intensity` data files) to estimate the carbon emissions per time-step.

[1] A computing site is made up solely of a specified type(s) and number(s) of compute nodes defined by `WorkerNodeSpec` in `src/WorkerNode.jl` (loaded from the cluster inventory CSV by `src/ClusterLoader.jl`) which run work.

[2] The work that the nodes run is made up of jobs that are specified by the job factories in `src/VOJobFactory.jl` (`VOJobFactory`, `GridPPJobFactory`, `ATLASJobFactory`, `LHCbJobFactory`), and are inserted into the simulation either at the beginning of the simulation or at fixed durations throughout the simulation in `src/JobScheduler.jl`.

[3] The different saving policies that the simulation can be run with are specified via a setting in `config.json`. This policy changes the frequency the nodes are run at and at what times of day this is done. Current running options are

| Running Flag  | Description |
| :------------: | :------ |
| none          |  Run the nodes as standard  |
| cd            |  Runs all the nodes clocked down one frequency step from the reported maximum frequency for the entire duration of the simulation    |
| cdcd          |  Runs all the nodes clocked down two frequency steps from the reported maximum frequency for the entire duration of the simulation      |
| cd1721        |  Runs all the nodes clocked down one frequency step from the reported maximum frequency only between the hours of 5pm and 9pm  |
| cdcd1721      |  Runs all the nodes clocked down two frequency steps from the reported maximum frequency only between the hours of 5pm and 9pm   |
| highforecast  |  Runs all the nodes clocked down one frequency step from the reported maximum frequency only when the forecasted usage is high (> `high_CI_threshold`, e.g. > 400 gCO2e/kWh)   |

The Simulation has two encoded end conditions
  1) All the jobs sent to the cluster have been completed
  2) The amount of time in seconds specified with `Simulation.simulation_length` has passed

**Outputs**
-  Number of jobs started and finished.
-  Total and Peak-time (5pm-9pm) Estimated Energy used in kWh.
-  Total and Peak-time Estimated Carbon (CO2e) used in kg.
-  Total and average CPU duration.
-  Total real-time and simulated-time passed.
-  Average occupancy of the cluster

### Package Dependencies
ORACLE-D (Julia) has its external package requirements declared in `OracleD.jl/Project.toml` (with the resolved versions in `OracleD.jl/Manifest.toml`).

Requirements:
- Julia 1.12 or newer (the migration was done with the current production release, 1.12.6, e.g. via [juliaup](https://github.com/JuliaLang/juliaup)).
- Julia packages: `Dates`, `Printf`, `Random`, `JSON`, `OrderedCollections` (test/development tools: `BenchmarkTools`, `Cthulhu`, `FileIO`, `FlameGraphs`, `JET`, `Test`).

To instantiate the package environment (creates/uses the local project environment from `Project.toml`), run from the `OracleD.jl/` directory:
```
julia --project -e 'using Pkg; Pkg.instantiate()'
```

## Getting started with the first run
To run the simulation, from the `OracleD.jl/` directory type the command:
```
julia --project src/OracleD.jl
```

Alternatively, from the Julia REPL:
```julia
using OracleD
OracleD.main()
```

This runs the job mix configured in the repository-root `config.json` — by default 50,000 GridPP jobs on the default DESY Grid compute cluster from 2024-01-16 16:00 without any special running conditions at medium verbosity. It produces a log output, and the folder `logs/runs/[DATE]_<run-label>` containing the summary of the output. The information of grid carbon intensity is taken from the file configured in `carbon_intensity.filename` (e.g. `data/carbon_intensity/de_carbon_Intensity_2024_15min.csv`). All relative paths in the configuration are resolved against the repository root, so the command works from any working directory.

Output summary for the test run with default settings can be found in `logs/Demo_run_summary.txt` ---> can be verified against to make sure the code is working as intended.

## Configuration
The simulation is configured via the `config.json` file at the repository root. In there, all relevant parameters are specified. They are split into several sections dealing with the different parts of the code.

### Simulation
The parameters that can be changed for the simulation include:

| Variables to edit  | Description |
| :------------: | :------ |
| desired_starttime          | The time at which the simulation starts (`"YYYY-MM-DD HH:MM"`). Leaving this as `nothing` defaults to the current clock time  |
| simulation_length   | The maximum duration that the simulation will run for in seconds |
| timestep   | The timestep the simulation does in between each update in seconds |
| savings_policy   | The savings policy specified in an earlier section. The options are `"none"`, `"cd"`, `"cdcd"`, `"cd1721"`, `"cdcd1721"`, and `"highforecast"`. |
| rng_seed   | (Julia addition) Seeds Julia's random number generator via `Random.seed!` at the start of `main()` for reproducible runs |

### carbon_intensity
The parameters that define information on the carbon intensity. They include:

| Variables to edit  | Description |
| :------------: | :------ |
| folder          | The folder where the carbon intensity data is stored  |
| filename   | The filename of the carbon intensity data |
| high_CI_threshold   | The threshold of what is considered a high carbon intensity in gCO2e/kWh |

### jobs
In this part of the config, the types of jobs that the simulation will run are specified. The relevant parameters are:

| Variables to edit  | Description |
| :------------: | :------ |
| initial_mix          | The initial mix of jobs submitted to the cluster. The format is a dictionary with the type of jobs as key and the number as value. Currently implemented are the jobtypes `"ATLAS"`, `"LHCb"` and `"GridPP"`. With any other name, a basic VO job will be run. |
| regular_incoming_mix   | A mix of jobs that gets submitted at regular intervals. The format is the same as `initial_mix`. If left empty, no jobs will be refilled. |
| incoming_timestep   | The timestep between job submissions |

### output
This part controls how much information is written to the logfile in the `logs/` directory.

| Variables to edit  | Description |
| :------------: | :------ |
| verbosity | Controls INFO-level logging detail. Valid values are `"low"`, `"medium"`, and `"high"`. |
| debug | Controls the logging level. If set to true, debug messages are logged alongside information, warnings and errors. |
| log_dir | Optional. Directory where per-run log folders are written. Defaults to `logs/runs`. |
| run_label | Optional. Human-readable label added to the run folder name. If omitted, the label is generated from the number of initial jobs and the savings policy. |

Each simulation run creates a folder named like `YYYY-MM-DD_HH-MM-SS_<run-label>` under `logs/runs/`. The folder contains `simulation.log`, `summary.txt`, `summary.json`, `parameters.txt`, and a copy of the run `config.json`.
The `summary.json` file contains both the simulation parameters and the final summary metrics for machine-readable comparisons between runs.

Verbosity behavior:
- `low`: only high-level lifecycle messages (for example simulation creation) are logged.
- `medium`: includes major progress messages (for example loading data and simulation end-condition messages).
- `high`: includes the most detailed INFO logs, including per-job start/finish entries from the data logger.

If `output.verbosity` is not one of `low`, `medium`, or `high`, ORACLE-D logs a warning and defaults to `high`.

### cluster

The parameters for the cluster include:

| Variables to edit  | Description |
| :------------: | :------ |
| cluster_name          | The name of the cluster, used to filter the inventory on the `cluster(main_Puppet_hostgroup)` column  |
| inventory_csv   | The csv file with the inventory of the cluster |
| frequency_csv   | The csv file with frequency dependence of the cluster |
| strict   | Whether the program should terminate when an incomplete frequency dependence data entry is found or simply log and continue. |

## Adding Extra Options
If you want to amend the measurements for each node or add different types of node not yet in the simulation, this is done **data-driven** in the Julia version: edit the cluster inventory and frequency dependence CSV files listed in `config.json` (see "Custom cluster makeup" below) rather than code. The node model itself lives in `src/WorkerNode.jl`, where each machine type is described by an immutable `WorkerNodeSpec` (node key, threads, memory, idle power, frequencies, per-frequency power and HEPScores) from which the mutable `WorkerNode` instances are constructed.

To add new machines you will need the following information for each entry:
- name (type and subtype, combined as `type_subtype`)
- number of (hyper)threads
- amount of memory available to the node
- the value of the power displaced when node is IDLE
- the value of the power displaced when the node is fully occupied with work at its maximum frequency value
- HEPScore value for the node at its maximum frequency value
- (optional) the value of the power displaced of a fully occupied node at its alternative frequency values
- (optional) the HEPScore value of a fully occupied node at its alternative frequency values

## Custom cluster makeup
While ORACLE-D is shipped with a demo cluster makeup, it is designed to be easily adapted to other datacentres. For that, two datafiles are required: the inventory and the frequency dependence. Both filenames should be specified in `config.json` under `cluster.inventory_csv` and `cluster.frequency_csv`.

The inventory is a csv with the columns used by `src/ClusterLoader.jl` (`load_cluster_inventory`):

| Header entry  | Description |
| :------------: | :------ |
| type | The name of the type of nodes  |
| subtype   | The name of the subtype of nodes. Allows for greater flexibility in naming convention. The full name will be `type_subtype` |
| number_machines   | The number of machines in each subtype |
| total_threads   | The number of threads per machine |
| total_mem_in_Gb | The amount of memory per machine in Gb |
| power_min_60d | The minimal power the machine draws, i.e. the idle power |
| cluster(main_Puppet_hostgroup) | The name of the cluster the machines belong to (used to filter by `cluster_name`) |
| model | The model of the machine (optional) |
| cpu_model | The cpu of the machine (optional) |
| installation_date | The installation date of the machine (optional) |
| (other columns such as `representative`, `timestamp_check`, `number_decommissioned`, `comment`, `manufacturer`, `hepscore`, `total_cores`, `power_max_60d`) | Present in the shipped data but not required by the loader |

The frequency dependence file is a csv with a header row followed by one row per node type. Each row holds the node type and subtype in columns 2 and 3, and then a series of comma-separated entries of the form `frequencyMHz_powerW_HEPScore`, one for each measured frequency step (the first is the maximum frequency), e.g.:

| hostname | type | subtype | latest measurement | frequency_power_hepscore |
| :------------: | :------ | :------ | :------ | :------ |
| default-DESYT3 | DESYT3 | 0 | 2024-01-01T00:00:00 | 2700_530.1_1450, 2500_530.1_1450, 2300_330_1102, ... |

## Copyright and License
Copyright 2023-2026 Deutsches Elektronen Synchrotron DESY and the University of Glasgow

Original Authors: Dwayne Spiteri and Gordon Stewart.

All code in the `src/` directory and subsequent subdirectory structure is
licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.

## Contributors
Dwayne Spiteri, Gordon Stewart and Konrad Kockler

## Acknowledgements
The measurements used here to categorise the different types of server come from running the [HEPScore23 benchmark](https://w3.hepix.org/benchmarking/how_to_run_HS23.html) on compute nodes. For the server examples used in ORACLE-D these were taken by **Emanuele Simili** at the University of Glasgow in February 2024 and **Jan Hartmann** at DESY in May of 2025.

The carbon intensity data for the UK is taken from the [UK National Grid ESO](https://www.nationalgrideso.com/data-portal/national-carbon-intensity-forecast/national_carbon_intensity_forecast) interpolated to fill in gaps in the data and can be downloaded from [here](https://www.nationalgrideso.com/data-portal/national-carbon-intensity-forecast/national_carbon_intensity_forecast) and for Germany is taken from [Agorameter](https://www.agora-energiewende.de/daten-tools/agorameter) and [Green Grid Compass](https://www.greengrid-compass.eu/).

This code was partially written for the RF2.0 project that has received funding from the European Union’s Horizon Europe research and innovation programme under grant agreement No. 101131850 and from the Swiss State Secretariat for Education Research and Innovation (SERI)
