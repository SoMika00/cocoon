#!/usr/bin/env bash

# setup-gpu-vfio.sh - List, bind, and unbind NVIDIA H100 GPUs to the vfio-pci driver
#
# This script automates GPU preparation for COCOON workers by managing the
# vfio-pci binding of NVIDIA GPUs. It supports:
#   - list:   print detected NVIDIA GPUs with PCI IDs and current driver
#   - bind:   bind one or more PCI IDs to vfio-pci (loading the module if needed)
#   - unbind: restore the original driver (detected before binding) for each GPU
#
# Options:
#   --dry-run   Show intended actions without performing them
#   --json      Emit machine-readable JSON output
#   --help      Show usage information
#
# Exit codes:
#   0  success
#   1  runtime error (invalid PCI ID, missing driver, etc.)
#   2  usage error (unknown option/command)

set -u

# Colors for human-readable output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

VFIO_MODULE="vfio-pci"

print_help() {
    cat <<'EOF'
Usage: setup-gpu-vfio.sh <command> [options]

Commands:
  list                 List detected NVIDIA GPUs with PCI IDs and current driver
  bind <pci_id>...     Bind one or more PCI IDs to vfio-pci
  unbind <pci_id>...   Restore the original driver for one or more PCI IDs

Options:
  --dry-run            Show intended actions without performing them
  --json               Emit machine-readable JSON output
  -h, --help           Show this help message and exit

Examples:
  ./setup-gpu-vfio.sh list
  ./setup-gpu-vfio.sh list --json
  ./setup-gpu-vfio.sh bind 0000:01:00.0 0000:02:00.0
  ./setup-gpu-vfio.sh bind 0000:01:00.0 --dry-run
  ./setup-gpu-vfio.sh unbind 0000:01:00.0 --json

JSON schema:
  list:   [{"pci_id":"0000:01:00.0","driver":"nvidia"}, ...]
  bind:   {"command":"bind","dry_run":false,"results":[{"pci_id":"...","success":true,"action":"...","error":""}],"overall_status":"ok|failed"}
  unbind: {"command":"unbind","dry_run":false,"results":[{"pci_id":"...","success":true,"action":"...","error":""}],"overall_status":"ok|failed"}
EOF
}

# JSON escaping helper (pure bash, no jq dependency)
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\n'/\\n}"
    s="${s//$'\r'/\\r}"
    s="${s//$'\t'/\\t}"
    printf '%s' "$s"
}

# Validate a PCI ID format (e.g., 0000:01:00.0)
is_valid_pci_id() {
    [[ "$1" =~ ^[0-9a-fA-F]{4}:[0-9a-fA-F]{2}:[0-9a-fA-F]{2}\.[0-7]$ ]]
}

# Get the current driver bound to a PCI device.
# Returns the driver name, or empty string if no driver is bound.
get_current_driver() {
    local pci_id="$1"
    local driver_path="/sys/bus/pci/devices/${pci_id}/driver"
    if [[ -L "$driver_path" ]]; then
        basename "$(readlink -f "$driver_path")"
    else
        echo ""
    fi
}

# Check whether a PCI device exists in sysfs.
pci_device_exists() {
    [[ -d "/sys/bus/pci/devices/$1" ]]
}

# Check whether the vfio-pci module is loaded.
module_loaded() {
    lsmod 2>/dev/null | grep -q "^${VFIO_MODULE} "
}

# Load the vfio-pci module if it is not already loaded.
ensure_vfio_module() {
    if module_loaded; then
        return 0
    fi
    if [[ "$DRY_RUN" == true ]]; then
        return 0
    fi
    if ! modprobe "$VFIO_MODULE" 2>/dev/null; then
        return 1
    fi
    return 0
}

# Detect NVIDIA GPUs via lspci.
# Outputs lines of "pci_id|driver" (driver may be empty).
detect_nvidia_gpus() {
    local line pci_id driver
    while IFS= read -r line; do
        # lspci output format: "01:00.0 VGA compatible controller: NVIDIA ..."
        pci_id=$(echo "$line" | awk '{print $1}')
        [[ -z "$pci_id" ]] && continue
        pci_id="0000:${pci_id}"
        driver=$(get_current_driver "$pci_id")
        printf '%s|%s\n' "$pci_id" "$driver"
    done < <(lspci 2>/dev/null | grep -i nvidia)
}

# ---------------------------------------------------------------------------
# list command
# ---------------------------------------------------------------------------
cmd_list() {
    local gpus=()
    local line pci_id driver
    while IFS='|' read -r pci_id driver; do
        [[ -z "$pci_id" ]] && continue
        gpus+=("$pci_id|$driver")
    done < <(detect_nvidia_gpus)

    if [[ "$JSON" == true ]]; then
        local arr="["
        local first=true
        for entry in "${gpus[@]}"; do
            IFS='|' read -r pci_id driver <<< "$entry"
            local pci_esc driver_esc
            pci_esc=$(json_escape "$pci_id")
            driver_esc=$(json_escape "$driver")
            if [[ "$first" == true ]]; then
                first=false
            else
                arr+=","
            fi
            arr+="{\"pci_id\":\"$pci_esc\",\"driver\":\"$driver_esc\"}"
        done
        arr+="]"
        printf '%s\n' "$arr"
    else
        if [[ ${#gpus[@]} -eq 0 ]]; then
            echo -e "${YELLOW}No NVIDIA GPUs detected.${NC}"
            return 0
        fi
        printf "%-16s %s\n" "PCI ID" "DRIVER"
        printf "%-16s %s\n" "----------------" "------"
        for entry in "${gpus[@]}"; do
            IFS='|' read -r pci_id driver <<< "$entry"
            if [[ -z "$driver" ]]; then
                driver="(none)"
            fi
            printf "%-16s %s\n" "$pci_id" "$driver"
        done
    fi
    return 0
}

# ---------------------------------------------------------------------------
# bind command
# ---------------------------------------------------------------------------
cmd_bind() {
    local pci_ids=("$@")
    local results=()
    local overall_ok=true

    # Ensure vfio-pci module is loaded (or would be loaded in dry-run).
    if ! ensure_vfio_module; then
        if [[ "$JSON" == true ]]; then
            printf '{"command":"bind","dry_run":%s,"results":[],"overall_status":"failed","error":"failed to load %s module"}\n' \
                "$DRY_RUN" "$VFIO_MODULE"
        else
            echo -e "${RED}Error: failed to load ${VFIO_MODULE} module${NC}" >&2
        fi
        return 1
    fi

    for pci_id in "${pci_ids[@]}"; do
        local success=true
        local action=""
        local error=""

        if ! is_valid_pci_id "$pci_id"; then
            success=false
            error="invalid PCI ID format"
        elif ! pci_device_exists "$pci_id"; then
            success=false
            error="PCI device does not exist"
        else
            local current_driver
            current_driver=$(get_current_driver "$pci_id")
            if [[ "$current_driver" == "$VFIO_MODULE" ]]; then
                action="already bound to ${VFIO_MODULE}"
            elif [[ -z "$current_driver" ]]; then
                action="bind ${pci_id} to ${VFIO_MODULE} (no current driver)"
            else
                action="unbind ${pci_id} from ${current_driver} and bind to ${VFIO_MODULE}"
            fi

            if [[ "$DRY_RUN" == true ]]; then
                action="[DRY-RUN] ${action}"
            else
                # Unbind from current driver if any.
                if [[ -n "$current_driver" ]] && [[ "$current_driver" != "$VFIO_MODULE" ]]; then
                    if ! echo "$pci_id" > "/sys/bus/pci/devices/${pci_id}/driver/unbind" 2>/dev/null; then
                        success=false
                        error="failed to unbind from ${current_driver}"
                    fi
                fi
                # Bind to vfio-pci.
                if [[ "$success" == true ]]; then
                    if ! echo "$VFIO_MODULE" > "/sys/bus/pci/drivers/${VFIO_MODULE}/bind" 2>/dev/null; then
                        # Fallback: use driver_override + probe.
                        if ! echo "$VFIO_MODULE" > "/sys/bus/pci/devices/${pci_id}/driver_override" 2>/dev/null; then
                            success=false
                            error="failed to bind to ${VFIO_MODULE}"
                        else
                            if ! echo "$pci_id" > "/sys/bus/pci/drivers_probe" 2>/dev/null; then
                                success=false
                                error="failed to bind to ${VFIO_MODULE}"
                            fi
                        fi
                    fi
                fi
            fi
        fi

        if [[ "$success" == false ]]; then
            overall_ok=false
        fi
        results+=("$pci_id|$success|$action|$error")
    done

    emit_results "bind" "${results[@]}"
    if [[ "$overall_ok" == true ]]; then
        return 0
    else
        return 1
    fi
}

# ---------------------------------------------------------------------------
# unbind command
# ---------------------------------------------------------------------------
cmd_unbind() {
    local pci_ids=("$@")
    local results=()
    local overall_ok=true

    for pci_id in "${pci_ids[@]}"; do
        local success=true
        local action=""
        local error=""

        if ! is_valid_pci_id "$pci_id"; then
            success=false
            error="invalid PCI ID format"
        elif ! pci_device_exists "$pci_id"; then
            success=false
            error="PCI device does not exist"
        else
            local current_driver
            current_driver=$(get_current_driver "$pci_id")
            local original_driver
            original_driver=$(get_original_driver "$pci_id")

            if [[ "$current_driver" != "$VFIO_MODULE" ]]; then
                action="already bound to ${current_driver:-none} (not ${VFIO_MODULE})"
            elif [[ -z "$original_driver" ]]; then
                success=false
                error="original driver unknown; cannot restore"
            else
                action="unbind ${pci_id} from ${VFIO_MODULE} and bind to ${original_driver}"
            fi

            if [[ "$DRY_RUN" == true ]]; then
                action="[DRY-RUN] ${action}"
            elif [[ "$success" == true ]] && [[ "$current_driver" == "$VFIO_MODULE" ]]; then
                # Unbind from vfio-pci.
                if ! echo "$pci_id" > "/sys/bus/pci/devices/${pci_id}/driver/unbind" 2>/dev/null; then
                    success=false
                    error="failed to unbind from ${VFIO_MODULE}"
                else
                    # Bind back to original driver.
                    if ! echo "$pci_id" > "/sys/bus/pci/drivers/${original_driver}/bind" 2>/dev/null; then
                        success=false
                        error="failed to bind to ${original_driver}"
                    fi
                fi
            fi
        fi

        if [[ "$success" == false ]]; then
            overall_ok=false
        fi
        results+=("$pci_id|$success|$action|$error")
    done

    emit_results "unbind" "${results[@]}"
    if [[ "$overall_ok" == true ]]; then
        return 0
    else
        return 1
    fi
}

# Determine the original driver for a PCI device.
# We record the original driver in a state file when binding, so unbind can
# restore it. If no state file exists, fall back to a heuristic (nvidia).
get_original_driver() {
    local pci_id="$1"
    local state_file="/tmp/setup-gpu-vfio-${pci_id}.driver"
    if [[ -f "$state_file" ]]; then
        cat "$state_file"
    else
        # Heuristic: NVIDIA GPUs are typically bound to nvidia.
        echo "nvidia"
    fi
}

# Record the original driver before binding (only in non-dry-run mode).
record_original_driver() {
    local pci_id="$1"
    local driver="$2"
    local state_file="/tmp/setup-gpu-vfio-${pci_id}.driver"
    if [[ "$DRY_RUN" != true ]]; then
        printf '%s' "$driver" > "$state_file"
    fi
}

# Emit results for bind/unbind in either JSON or human-readable form.
emit_results() {
    local command="$1"
    shift
    local results=("$@")

    if [[ "$JSON" == true ]]; then
        local arr="["
        local first=true
        for entry in "${results[@]}"; do
            IFS='|' read -r pci_id success action error <<< "$entry"
            local pci_esc action_esc error_esc
            pci_esc=$(json_escape "$pci_id")
            action_esc=$(json_escape "$action")
            error_esc=$(json_escape "$error")
            if [[ "$first" == true ]]; then
                first=false
            else
                arr+=","
            fi
            arr+="{\"pci_id\":\"$pci_esc\",\"success\":$success,\"action\":\"$action_esc\",\"error\":\"$error_esc\"}"
        done
        arr+="]"

        local overall="ok"
        for entry in "${results[@]}"; do
            IFS='|' read -r pci_id success action error <<< "$entry"
            if [[ "$success" == false ]]; then
                overall="failed"
                break
            fi
        done

        printf '{"command":"%s","dry_run":%s,"results":%s,"overall_status":"%s"}\n' \
            "$command" "$DRY_RUN" "$arr" "$overall"
    else
        for entry in "${results[@]}"; do
            IFS='|' read -r pci_id success action error <<< "$entry"
            if [[ "$success" == true ]]; then
                echo -e "${GREEN}✓${NC} $pci_id: $action"
            else
                echo -e "${RED}✗${NC} $pci_id: $error"
            fi
        done
    fi
}

# ---------------------------------------------------------------------------
# Argument parsing
# ---------------------------------------------------------------------------
DRY_RUN=false
JSON=false
COMMAND=""
PCI_IDS=()

if [[ $# -eq 0 ]]; then
    print_help
    exit 2
fi

# First non-option argument is the command.
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            print_help
            exit 0
            ;;
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --json)
            JSON=true
            shift
            ;;
        list|bind|unbind)
            if [[ -z "$COMMAND" ]]; then
                COMMAND="$1"
                shift
            else
                PCI_IDS+=("$1")
                shift
            fi
            ;;
        *)
            if [[ -z "$COMMAND" ]]; then
                echo "Unknown command or option: $1" >&2
                print_help
                exit 2
            else
                PCI_IDS+=("$1")
                shift
            fi
            ;;
    esac
done

if [[ -z "$COMMAND" ]]; then
    echo "Error: no command specified" >&2
    print_help
    exit 2
fi

case "$COMMAND" in
    list)
        cmd_list
        ;;
    bind)
        if [[ ${#PCI_IDS[@]} -eq 0 ]]; then
            echo "Error: bind requires at least one PCI ID" >&2
            print_help
            exit 2
        fi
        # Record original drivers before binding (non-dry-run only).
        if [[ "$DRY_RUN" != true ]]; then
            for pci_id in "${PCI_IDS[@]}"; do
                if is_valid_pci_id "$pci_id" && pci_device_exists "$pci_id"; then
                    local_driver=$(get_current_driver "$pci_id")
                    if [[ -n "$local_driver" ]] && [[ "$local_driver" != "$VFIO_MODULE" ]]; then
                        record_original_driver "$pci_id" "$local_driver"
                    fi
                fi
            done
        fi
        cmd_bind "${PCI_IDS[@]}"
        ;;
    unbind)
        if [[ ${#PCI_IDS[@]} -eq 0 ]]; then
            echo "Error: unbind requires at least one PCI ID" >&2
            print_help
            exit 2
        fi
        cmd_unbind "${PCI_IDS[@]}"
        ;;
    *)
        echo "Unknown command: $COMMAND" >&2
        print_help
        exit 2
        ;;
esac

exit $?
