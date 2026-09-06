# Custom cluster makeup

```@meta
CurrentModule = OracleD
```

While ORACLE-D ships with a demo cluster makeup, it is designed to be easily
adapted to other datacentres. Two data files are required: the **inventory**
and the **frequency dependence**. Their filenames are specified in
`config.json` under `cluster.inventory_csv` and `cluster.frequency_csv` and
are loaded by [`load_cluster_inventory`](@ref) /
[`load_frequency_map`](@ref) in `src/ClusterLoader.jl`.

## Inventory CSV

The machine inventory is a comma-separated file whose header is scanned by
column name. The columns used by the loader are:

| Header entry                  | Description |
| :---------------------------- | :----------------------- |
| `type`                        | The name of the machine type. |
| `subtype`                     | The subtype name; the full node key becomes `type_subtype`. |
| `number_machines`             | The number of machines of this subtype. |
| `total_threads`               | The number of (hyper)threads per machine. |
| `total_mem_in_Gb`             | The amount of memory per machine in GB. |
| `power_min_60d`               | The minimal power the machine draws (the idle power). |
| `cluster(main_Puppet_hostgroup)` | The cluster the machines belong to; used to filter by `cluster_name`. |
| `model`                       | The model of the machine *(optional)*. |
| `cpu_model`                   | The CPU of the machine *(optional)*. |
| `installation_date`           | The installation date of the machine *(optional)*. |

Other columns shipped with the demo data (`representative`,
`timestamp_check`, `number_decommissioned`, `comment`, `manufacturer`,
`hepscore`, `total_cores`, `power_max_60d`, ...) are ignored by the loader.

For example:

```csv
representative,timestamp_check,number_machines,type,subtype,comment,manufacturer,model,cpu_model,hepscore,installation_date,cluster(main_Puppet_hostgroup),total_cores,total_threads,total_mem_in_Gb,power_min_60d,power_max_60d
default-DESYT3,2024-01-01T00:00:00,40,DESYT3,0,hardcoded default,,DELL PowerEdge R6525,AMD EPYC 7402 24-Core Processor,1450,2020,DEFAULT,48,96,256,112,530.1
```

## Frequency dependence CSV

The frequency dependence file maps each node key (`type_subtype`) to a list
of measured frequency points. It is a comma-separated file with a header row
(the columns `hostname`, `type`, `subtype`, `latest measurement` are
ignored by the loader) followed by one row per node type. Each row lists the
node type and subtype in columns 2 and 3 and, from column 5 onward, a
comma-separated list of entries of the form

```
<frequency in MHz>_<power in W>_<HEPScore>
```

one per measured frequency step, starting from the maximum (default)
frequency:

```
hostname,type,subtype,latest measurement,frequency_power_hepscore
default-DESYT3,DESYT3,0,2024-01-01T00:00:00,2700_530.1_1450,2500_530.1_1450,2300_330_1102,2100_332.4_1100,1900_333.3_1102,1700_330.7_1102
```

Each entry supplies, for the given frequency, the average power a fully
occupied node draws (in W) and its [HEPScore23](https://w3.hepix.org/benchmarking/how_to_run_HS23.html)
benchmark score. The power and HEPScore of the **first** (maximum) entry are
used as the node's default.

## Adding new machine types

- Add the machine to the **inventory** CSV with the required columns above.
- Add a matching **frequency dependence** row using its `type_subtype` key.
- If you want to change how nodes behave (rather than just their data), the
  model lives in `src/WorkerNode.jl` ([`WorkerNodeSpec`](@ref) and
  [`WorkerNode`](@ref)); see [Development](development.md#Adding-extra-options).
