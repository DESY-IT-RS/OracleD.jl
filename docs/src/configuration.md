# Configuration

The simulation is configured via the `config.json` file at the repository
root. All relevant parameters are specified there, split into sections that
map onto the different parts of the code. All relative paths (data files,
log directories) are resolved against the repository root.

The current running options for the savings policy are:

| Running flag  | Description                                                        |
| :------------: | :----------------------------------------------------------------- |
| `none`        | Run the nodes as standard.                                         |
| `cd`          | Clock all nodes down one frequency step below their reported maximum for the entire simulation. |
| `cdcd`        | Clock all nodes down two frequency steps below their reported maximum for the entire simulation. |
| `cd1721`      | Clock all nodes down one frequency step below their reported maximum only between 5pm and 9pm. |
| `cdcd1721`    | Clock all nodes down two frequency steps below their reported maximum only between 5pm and 9pm. |
| `highforecast`| Clock all nodes down one frequency step below their reported maximum only when the forecast carbon intensity is high (> `high_CI_threshold`, e.g. > 400 gCO2e/kWh). |

The simulation has two encoded end conditions:

1. all the jobs sent to the cluster have been completed; or
2. the amount of time in seconds specified by `Simulation.simulation_length`
   has passed.

## `Simulation`

| Variable          | Description                                        |
| :---------------- | :------------------------------------------------- |
| `desired_starttime` | The time at which the simulation starts (`"YYYY-MM-DD HH:MM"`). Leaving it as `nothing` defaults to the current clock time. |
| `simulation_length` | The maximum duration the simulation may run for, in seconds. |
| `timestep`        | The timestep between updates, in seconds.          |
| `savings_policy`  | The savings policy (see the table above).         |
| `rng_seed`        | *(Julia addition.)* A seed for `Random.seed!`, making the run reproducible. |

## `carbon_intensity`

| Variable            | Description                                                        |
| :------------------ | :----------------------------------------------------------------- |
| `folder`            | The folder where the carbon intensity data is stored.              |
| `filename`          | The filename of the carbon intensity data file.                    |
| `high_CI_threshold` | The threshold (gCO2e/kWh) above which carbon intensity is considered "high". |

## `jobs`

| Variable               | Description |
| :--------------------- | :----------------------------------------------------------------- |
| `initial_mix`          | The mix of jobs submitted to the cluster at the start. A dictionary mapping job type → number of jobs. Implemented job types are `"ATLAS"`, `"LHCb"` and `"GridPP"`; any other name produces a basic VO job. |
| `regular_incoming_mix` | A mix of jobs submitted at regular intervals (same format as `initial_mix`). If empty, no jobs are refilled. |
| `incoming_timestep`    | The timestep (seconds) between successive job submissions.         |

## `output`

| Variable   | Description |
| :--------- | :----------------------------------------------------------------- |
| `verbosity`| INFO-level logging detail. Valid values are `"low"`, `"medium"` and `"high"`. |
| `debug`    | If `true`, DEBUG messages are recorded in addition to warnings and errors. |
| `log_dir`  | Optional. Directory where per-run log folders are written (default `logs/runs`). |
| `run_label`| Optional. Human-readable label added to the run folder name. If omitted, the label is generated from the number of initial jobs and the savings policy. |

Each run creates a folder named `YYYY-MM-DD_HH-MM-SS_<run-label>` under
`log_dir` containing `simulation.log`, `summary.txt`, `summary.json`,
`parameters.txt` and a copy of the run `config.json`. `summary.json`
contains both the simulation parameters and the final summary metrics, for
machine-readable comparison between runs.

Verbosity behaviour:

- `low`: only high-level lifecycle messages (for example simulation creation).
- `medium`: major progress messages (for example loading data and the
  end-condition messages).
- `high`: the most detailed INFO logs, including per-job start/finish
  entries from the data logger.

If `output.verbosity` is not one of the three valid values, ORACLE-D logs a
warning and defaults to `high`.

## `cluster`

| Variable        | Description |
| :-------------- | :----------------------------------------------------------------- |
| `cluster_name`  | The name of the cluster; used to filter the inventory on the `cluster(main_Puppet_hostgroup)` column. |
| `inventory_csv` | The CSV file with the cluster inventory. |
| `frequency_csv` | The CSV file with the frequency dependence of the cluster. |
| `strict`        | Whether the program terminates on incomplete frequency-dependence data entries (`true`) or logs a warning and continues (`false`). |

See [Custom cluster makeup](custom-cluster.md) for the exact CSV formats.

## Example

A minimal configuration that runs 100,000 `GridPP` jobs on the default DESY
cluster, starting 2024-01-16 16:00, for up to one week, with
`highforecast` running conditions:

```json
{
    "Simulation": {
        "desired_starttime": "2024-01-16 16:00",
        "simulation_length": 604800,
        "timestep": 600,
        "savings_policy": "highforecast",
        "rng_seed": 42
    },
    "carbon_intensity": {
        "folder": "data/carbon_intensity/",
        "filename": "de_carbon_Intensity_2024_15min.csv",
        "high_CI_threshold": 400
    },
    "cluster": {
        "cluster_name": "DEFAULT",
        "inventory_csv": "data/cluster/default-machinegroups_inventory.csv",
        "frequency_csv": "data/cluster/default-frequency_dependence.csv",
        "strict": false
    },
    "jobs": {
        "initial_mix": {"GridPP": 100000},
        "regular_incoming_mix": {"GridPP": 1000},
        "incoming_timestep": 3600
    },
    "output": {
        "verbosity": "medium",
        "debug": false,
        "log_dir": "logs/runs",
        "run_label": "MyFirstRun"
    }
}
```
