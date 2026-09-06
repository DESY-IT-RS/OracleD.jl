# Development

```@meta
CurrentModule = OracleD
```

## Package layout

```
OracleD.jl/
├── Project.toml                     # Julia project metadata (+ docs workspace)
├── Manifest.toml                    # Resolved dependencies
├── README.md                        # Quick-start README
├── diagnostics_new.jl               # Whole-port performance diagnostics (developer tool)
├── doc/
│   └── migration-notes.md           # Python → Julia migration decisions
├── test/
│   └── runtests.jl                  # Unit tests (see Running the tests)
├── docs/
│   ├── Project.toml                 # Documentation environment
│   ├── make.jl                      # Documenter build script
│   └── src/                         # Documentation source (this website)
└── src/
    ├── OracleD.jl                   # Module + main() entry point
    ├── Utils.jl                     # Generic utilities (paths, RNG, formatting)
    ├── Logging.jl                   # SimLogger + run-directory creation
    ├── Time.jl                      # SimulationTime clock
    ├── Jobs.jl                      # Job struct
    ├── VOJobFactory.jl              # Abstract type + 4 concrete job factories
    ├── DataLogger.jl                # Metrics + summary output
    ├── WorkerNode.jl                # WorkerNodeSpec + WorkerNode
    ├── ClusterLoader.jl             # CSV inventory/frequency loading
    ├── Cluster.jl                   # Cluster struct + per-timestep update
    ├── JobScheduler.jl              # Initial seed + periodic job refill
    └── Simulation.jl                # Simulation struct + main loop
```

The package defines a single module `OracleD`; everything is included via
`src/OracleD.jl`. The module **exports nothing**, so names are used
qualified (`OracleD.Simulation`, `OracleD.start!`, ...) unless brought into
scope explicitly.

## Python → Julia mapping

The source files mirror their Python counterparts (same names, same
behaviour):

| Python                          | Julia                     |
| :------------------------------ | :------------------------ |
| `src/Main.py`                   | `src/OracleD.jl`          |
| `src/simulation/Simulation.py`  | `src/Simulation.jl`       |
| `src/simulation/Time.py`        | `src/Time.jl`             |
| `src/cluster/Cluster.py`        | `src/Cluster.jl`          |
| `src/cluster/ClusterLoader.py`  | `src/ClusterLoader.jl`    |
| `src/cluster/WorkerNode.py`     | `src/WorkerNode.jl`       |
| `src/jobs/Jobs.py`              | `src/Jobs.jl`             |
| `src/jobs/VOJobFactory.py`      | `src/VOJobFactory.jl`     |
| `src/jobs/JobScheduler.py`      | `src/JobScheduler.jl`     |
| `src/datalogger/DataLogger.py`  | `src/DataLogger.jl`       |
| `src/util/Logging.py`           | `src/Logging.jl`          |

The behavioural quirks of the Python code that the migration deliberately
preserves (e.g. the caching of the first core-count draw, the
whole-days-dropped CPU durations, and the no-op `sys.exit` on missing CI
data) are described in [`doc/migration-notes.md`](development.md).

## Running the tests

```sh
julia --project -e 'using Pkg; Pkg.test()'
```

## Adding extra options

Adding new machine types is **data driven**: edit the cluster inventory and
frequency-dependence CSV files listed in `config.json` (see
[Custom cluster makeup](custom-cluster.md)), no code changes required.

To alter the *behaviour* of nodes rather than their measurements, the model
lives in `src/WorkerNode.jl`:

- [`WorkerNodeSpec`](@ref) — immutable description of one machine type
  (threads, memory, idle power, per-frequency powers and HEPScores,
  metadata).
- [`WorkerNode`](@ref) — the mutable simulated node: hosts running jobs,
  tracks busy cores/RAM, and applies clock-speed changes.

New job types are added by writing a new concrete struct under
[`AbstractVOJobFactory`](@ref) in `src/VOJobFactory.jl` and specialising
[`get_duration`](@ref) and [`require_cores!`](@ref) for it (multiple
dispatch replaces Python's name-mangled method overriding).

## Building the documentation

The documentation is built with [Documenter.jl](https://documenter.juliadocs.org/stable/).
The `docs/` folder is listed as a workspace member of the package
(`[workspace] projects = ["docs"]` in `Project.toml`). To build it:

```sh
# from the OracleD.jl/ directory
julia --project=docs -e 'using Pkg; Pkg.instantiate()'
julia --project=docs docs/make.jl
```

This writes the generated website into `docs/build/` (browse it with a local
web server, e.g. `python3 -m http.server --directory docs/build`).

### Adding or editing pages

- Markdown pages live in `docs/src/`. Edit existing pages or add new ones
  and register them in the `pages` vector in `docs/make.jl`.
- The sidebar / page ordering is configured through the `pages` keyword of
  `makedocs`.
- `docs/src/api.md` splices in docstrings with `@docs` blocks under
  `CurrentModule = OracleD`. Add a `@docs` entry for any new documented
  binding.

### Documenting code

Follow the Julia conventions (see
[Writing Documentation](https://docs.julialang.org/en/v1/manual/documentation/)):
place a docstring immediately before the object it documents, start with an
indented signature line, use an imperative one-liner description, and
provide `# Arguments` / `# Examples` sections where helpful. Use `@ref`
links to cross-reference other documented names and keep lines within the
surrounding code's width (≈92 characters).

### Deploying

To publish the documentation to GitHub Pages, set the repository URL in
`deploydocs(...)` in `docs/make.jl`, put the repository on a git remote,
and use the standard GitHub Actions workflow for Julia documentation
(e.g. `julia-actions/julia-docdeploy`), which calls `docs/make.jl` in a CI
environment. Documenter pushes the generated site to the `gh-pages` branch.
The `build/` directory is generated and should **not** be committed.
