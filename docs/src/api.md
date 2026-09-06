# API reference

```@meta
CurrentModule = OracleD
```

The package defines a single module `OracleD`. Docstrings are spliced in
below; every entry corresponds to a public binding of the module. The module
does not `export` anything, so these names are accessed as `OracleD.<name>`.

## Entry point

```@docs
main
```

## Simulation and main loop

```@docs
Simulation
start!
_load_carbon_intensity_data
```

## Time

```@docs
SimulationTime
set_to_current_time!
set_to_time!
find_hh_segment
advance!
get_start_datetime
get_origin_datetime
get_current_datetime
get_timestep
```

## Jobs

```@docs
Job
set_duration!
set_start_time!
set_end_time!
```

## VO job factories

```@docs
AbstractVOJobFactory
VOJobFactory
GridPPJobFactory
ATLASJobFactory
LHCbJobFactory
get_duration
require_cores!
debug_label
create_job!
```

## Cluster and worker nodes

```@docs
WorkerNodeSpec
WorkerNode
number_of_cores
is_awaiting_jobs
get_free_core_count
get_memory_available
can_schedule_job
set_running_frequency!
start_job!
timestep_power_dissipated
change_clock_speed!
clock_down!
clock_up!
update!
CarbonIntensityEntry
Cluster
get_number_of_nodes
get_number_of_cores
submit_job!
has_queued_jobs
has_running_jobs
cluster_occupancy
```

## Cluster loading

```@docs
load_frequency_map
load_cluster_inventory
```

## Job scheduler

```@docs
JobScheduler
```

## Data logger

```@docs
DataLogger
job_start!
job_finish!
energy_and_carbon_consumed!
peaktime_energy_and_carbon_consumed!
sum_occupancy!
print_summary
```

## Logging

```@docs
SimLogger
get_logger
configure_logger!
close_logger!
log_info
log_warning
log_debug
normalize_verbosity
default_run_label
slugify
create_run_directory
```

## Utilities

```@docs
project_root
resolve_path
weighted_choice
gauss
pystr
pynum
total_seconds
```

## Index

```@index
```
