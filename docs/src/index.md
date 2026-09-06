# OracleD.jl

```@meta
CurrentModule = OracleD
```

*Optimised Resource Analysis and Carbon Legacy Estimator for Data centres.*

OracleD.jl is the Julia implementation of the **ORACLE-D** framework: a
modular simulator of Grid-computing sites. It models a cluster of compute
nodes processing HEP-style job workloads and estimates, time-step by
time-step, the energy consumed and the carbon emitted while doing so —
including the effect of running the site under different **energy-saving
policies**.

The package is a direct migration of the original [Python implementation]
(https://github.com/desy/ORACLE-D). It reads the same `config.json` and data
files from the repository root and produces the same console output and
per-run artefacts (`simulation.log`, `summary.txt`, `summary.json`,
`parameters.txt` and a copy of the run `config.json` under `logs/runs/`).
The Python-original behavioural quirks that the migration deliberately
preserves are catalogued in [`doc/migration-notes.md`](development.md).

## Table of contents

```@contents
Pages = ["index.md", "configuration.md", "custom-cluster.md", "development.md", "api.md", "about.md"]
Depth = 2
```

## Features

- **Modular components.** The computing site ([`WorkerNode`](@ref)), the
  work submitted to it ([`VOJobFactory`](@ref), [`JobScheduler`](@ref)) and
  the running mode ([`savings_policy`](configuration.md)) are all easy to
  swap or extend.
- **Energy & carbon accounting.** Every worker node reports its energy use
  per time-step (10 minutes by default); this is multiplied by the grid
  carbon intensity to estimate emissions, with total and peak-time
  (5pm–9pm) breakdowns.
- **Energy-saving policies.** `cd`, `cdcd`, `cd1721`, `cdcd1721` and
  `highforecast` clock the nodes down (and back up) either permanently, at
  fixed times of day, or according to forecast carbon intensity.
- **Just-in-case reproducibility.** An optional `rng_seed` in the
  configuration makes a run reproducible.
- **Per-run artefacts.** Every run produces a summary 
(`summary.txt`, `summary.json`, `parameters.txt`, `simulation.log`)


## Quick start

### Requirements

- **Julia 1.12 or newer** (the migration was done with the production
  release 1.12.6, e.g. via [juliaup](https://github.com/JuliaLang/juliaup)).

### Instantiate the environment

From the `OracleD.jl/` package directory, resolve the dependencies once:

```sh
julia --project -e 'using Pkg; Pkg.instantiate()'
```

### Run the baseline simulation

```sh
julia --project src/OracleD.jl
```

This runs the job mix configured in the repository-root `config.json` — by
default 40,000 ATLAS and 10,000 LHCb jobs on the default DESY Grid compute
cluster starting 2024-01-16 16:00, without special running conditions and at
medium verbosity. The output is written to a new timestamped folder under
`logs/runs/`. All relative paths in the configuration are resolved against
the repository root, so the command works from any working directory.

Alternatively, from the Julia REPL:

```julia
using OracleD
OracleD.main()      # OracleD exports nothing; qualify names explicitly
```

### Run the tests

```sh
julia --project -e 'using Pkg; Pkg.test()'
```

### Build this documentation

```sh
julia --project=docs docs/make.jl
```

See [Building the documentation](development.md#Building-the-documentation)
for details.
