# SPDX-License-Identifier: Apache-2.0
# Copyright 2023-2026 Deutsches Elektronen Synchrotron DESY
#                     and the University of Glasgow
# Authors: Dwayne Spiteri and Gordon Stewart.
# For more information about rights and fair use please refer to src/OracleD.jl.
# ===========================================================================

# Runtime loader for cluster node definitions, mirroring
# src/cluster/ClusterLoader.py. Instead of generating classes at runtime it
# produces `WorkerNodeSpec` values (see WorkerNode.jl).

"""
    load_frequency_map(frequency_csv, strict = true)
        -> Dict{String,Dict{Float64,Tuple{Float64,Float64}}}

Load the per-node-type frequency dependence map from CSV. Each entry maps a
node key (`type_subtype`) to a dictionary of
`frequency GHz => (power W, HEPScore)`.

With `strict = true` malformed entries raise an error; otherwise they are
logged and skipped.
"""
function load_frequency_map(frequency_csv::AbstractString, strict::Bool = true)
    frequencies_by_node = Dict{String,Dict{Float64,Tuple{Float64,Float64}}}()

    lines = readlines(frequency_csv)
    for row_line in lines[2:end] # skip the header
        row = split(row_line, ',')
        length(row) < 5 && continue

        node_type = strip(row[2])
        node_subtype = strip(row[3])
        node_key = "$(node_type)_$(node_subtype)"

        specs = Dict{Float64,Tuple{Float64,Float64}}()
        for raw_entry in row[5:end]
            raw_entry = strip(raw_entry)
            isempty(raw_entry) && continue

            parts = split(raw_entry, '_')
            if length(parts) != 3
                if strict
                    error("Malformed frequency entry '$raw_entry' for node $node_key in $frequency_csv")
                end
                log_warning(get_logger(),
                            "Skipping malformed frequency entry '$raw_entry' for node $node_key")
                continue
            end

            freq_mhz, power_w, hep_score = parts
            specs[parse(Float64, freq_mhz) / 1000.0] = (parse(Float64, power_w), parse(Float64, hep_score))
        end

        if isempty(specs)
            if strict
                error("No frequency points found for node $node_key in $frequency_csv")
            end
            log_warning(get_logger(), "Skipping node $node_key with no frequency points")
            continue
        end

        frequencies_by_node[node_key] = specs
    end

    return frequencies_by_node
end

"""
    load_cluster_inventory(machinegroups_inventory_csv, frequency_dependence_csv;
                           cluster_name = nothing, strict = true)
        -> Vector{Tuple{WorkerNodeSpec,Int}}

Load the cluster inventory as an ordered list of
`(machine type specification, quantity)` pairs — the Julia counterpart of
the Python `{WorkerNodeSubclass: quantity}` mapping, preserving the CSV row
order.

# Arguments
- `machinegroups_inventory_csv`: path to the machine inventory CSV.
- `frequency_dependence_csv`: path to the frequency dependence CSV.
- `cluster_name`: optional filter on the `cluster(main_Puppet_hostgroup)`
  column.
- `strict`: if `true`, raise on malformed or missing data; if `false`, log
  a warning and skip the offending row.
"""
function load_cluster_inventory(machinegroups_inventory_csv::AbstractString,
                                frequency_dependence_csv::AbstractString;
                                cluster_name::Union{AbstractString,Nothing} = nothing,
                                strict::Bool = true)
    machinegroups_inventory_csv = resolve_path(machinegroups_inventory_csv)
    frequency_dependence_csv = resolve_path(frequency_dependence_csv)

    frequencies_by_node = load_frequency_map(frequency_dependence_csv, strict)
    inventory = Tuple{WorkerNodeSpec,Int}[]

    lines = readlines(machinegroups_inventory_csv)
    header = strip.(split(lines[1], ','))
    column = Dict{String,Int}(name => i for (i, name) in enumerate(header))
    getfield_(row, name) = strip(get(row, get(column, name, 0), ""))

    for row_line in lines[2:end]
        isempty(strip(row_line)) && continue
        row = split(row_line, ',')

        row_cluster_name = getfield_(row, "cluster(main_Puppet_hostgroup)")
        if cluster_name !== nothing && row_cluster_name != cluster_name
            continue
        end

        node_type = getfield_(row, "type")
        node_subtype = getfield_(row, "subtype")
        node_key = "$(node_type)_$(node_subtype)"

        freq_dep_specs = get(frequencies_by_node, node_key, nothing)
        if freq_dep_specs === nothing
            message = "No frequency dependence data for node type $node_key; " *
                      "row representative=$(getfield_(row, "representative")) skipped"
            strict && error(message)
            log_warning(get_logger(), message)
            continue
        end

        quantity = threads = 0
        memory_gb = idle_power_w = 0.0
        try
            quantity = Int(floor(parse(Float64, getfield_(row, "number_machines"))))
            threads = Int(floor(parse(Float64, getfield_(row, "total_threads"))))
            memory_gb = parse(Float64, getfield_(row, "total_mem_in_Gb"))
            idle_power_w = parse(Float64, getfield_(row, "power_min_60d"))
        catch exc
            message = "Invalid numeric value in inventory row for $node_key: $exc"
            strict && error(message)
            log_warning(get_logger(), message)
            continue
        end

        spec = WorkerNodeSpec(node_key, threads, memory_gb, idle_power_w, freq_dep_specs;
                              system = getfield_(row, "model"),
                              cpu_model = getfield_(row, "cpu_model"),
                              install_year = getfield_(row, "installation_date"))
        push!(inventory, (spec, quantity))
    end

    log_info(get_logger(),
             "Loaded $(length(inventory)) worker node types from $machinegroups_inventory_csv and $frequency_dependence_csv")
    return inventory
end
