#!/usr/bin/env bash

# gpu-utilization.sh - Monitor NVIDIA H100 GPU utilization, memory, and temperature
#
# This script queries NVIDIA GPUs via `nvidia-smi` and displays a human‑readable table.
# It also supports a `--json` flag for machine‑parsing and exits with a non‑zero
# status code if any GPU temperature exceeds 85°C.

set -euo pipefail

# Temperature threshold (°C) above which the script exits with status 1
TEMP_THRESHOLD=85

print_help() {
    cat <<'EOF'
Usage: gpu-utilization.sh [OPTIONS]

Options:
  -h, --help       Show this help message and exit
  --json           Output GPU information as JSON array

The script queries `nvidia-smi` for each detected GPU and displays:
  Index  Name               Util(%)  MemTotal(MiB)  MemUsed(MiB)  Temp(C)
If any GPU temperature exceeds ${TEMP_THRESHOLD}°C, the script exits with status 1.
EOF
}

# Parse arguments
OUTPUT_JSON=false
while (("$#")); do
    case "$1" in
        -h|--help)
            print_help
            exit 0
            ;;
        --json)
            OUTPUT_JSON=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            print_help
            exit 2
            ;;
    esac
done

# Ensure nvidia-smi is available
if ! command -v nvidia-smi >/dev/null 2>&1; then
    echo "Error: nvidia-smi not found in PATH" >&2
    exit 3
fi

# Query required fields in CSV format without headers or units
QUERY="index,name,utilization.gpu,memory.total,memory.used,temperature.gpu"
CSV_OUTPUT=$(nvidia-smi --query-gpu=$QUERY --format=csv,noheader,nounits)

# If no GPUs detected, exit gracefully
if [[ -z "$CSV_OUTPUT" ]]; then
    echo "No NVIDIA GPUs detected." >&2
    exit 4
fi

# Process each line
exit_code=0
if $OUTPUT_JSON; then
    # Build JSON array
    json='['
    first=true
    while IFS=',' read -r idx name util mem_total mem_used temp; do
        # Trim leading/trailing whitespace
        idx=$(echo "$idx" | xargs)
        name=$(echo "$name" | xargs)
        util=$(echo "$util" | xargs)
        mem_total=$(echo "$mem_total" | xargs)
        mem_used=$(echo "$mem_used" | xargs)
        temp=$(echo "$temp" | xargs)

        # Temperature check
        if (( temp > TEMP_THRESHOLD )); then
            exit_code=1
        fi

        # Escape double quotes in name
        esc_name=$(printf '%s' "$name" | sed 's/"/\\"/g')
        if $first; then
            first=false
        else
            json+=','
        fi
        json+="{\"index\":$idx,\"name\":\"$esc_name\",\"utilization\":$util,\"memory_total\":$mem_total,\"memory_used\":$mem_used,\"temperature\":$temp}"
    done <<< "$CSV_OUTPUT"
    json+=']'
    printf '%s\n' "$json"
    exit $exit_code
else
    # Human‑readable table
    printf "%-5s %-20s %8s %14s %14s %8s\n" "IDX" "NAME" "UTIL(%)" "MEM_TOTAL" "MEM_USED" "TEMP(C)"
    printf "%s\n" "--------------------------------------------------------------------------"
    while IFS=',' read -r idx name util mem_total mem_used temp; do
        idx=$(echo "$idx" | xargs)
        name=$(echo "$name" | xargs)
        util=$(echo "$util" | xargs)
        mem_total=$(echo "$mem_total" | xargs)
        mem_used=$(echo "$mem_used" | xargs)
        temp=$(echo "$temp" | xargs)

        if (( temp > TEMP_THRESHOLD )); then
            exit_code=1
        fi
        printf "%-5s %-20.20s %8s %14s %14s %8s\n" "$idx" "$name" "$util" "$mem_total" "$mem_used" "$temp"
    done <<< "$CSV_OUTPUT"
    exit $exit_code
fi
