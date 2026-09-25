#!/usr/bin/env bash

# validate-config.sh
# Validates all worker-*.conf files in the current directory.
# Checks for required keys and validates their formats.
# Exits with status 0 if all configs are valid, otherwise non-zero.
# Usage: ./validate-config.sh [--help]

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_help() {
    cat <<EOF
Usage: $0 [options]

Options:
  --help        Show this help message and exit

The script scans all files matching 'worker-*.conf' in the current directory and validates:
  - owner_address: must start with 'EQ' and be at least 10 characters long
  - node_wallet_key: must be valid base64
  - hf_token: must start with 'hf_'
  - root_contract_address: must start with 'EQ' and be at least 10 characters long

If any validation fails, a summary table is printed and the script exits with status 1.
EOF
}

# Parse arguments
if [[ "${1-}" == "--help" ]]; then
    print_help
    exit 0
fi

# Helper functions
is_base64() {
    # Returns 0 if input is valid base64, 1 otherwise
    # Use openssl to attempt decode; suppress output
    if command -v openssl >/dev/null 2>&1; then
        echo "$1" | openssl base64 -d -A >/dev/null 2>&1
    else
        # Fallback: use base64 command if openssl not available
        echo "$1" | base64 -d >/dev/null 2>&1
    fi
}

# Collect results
declare -a errors

shopt -s nullglob
conf_files=(worker-*.conf)
shopt -u nullglob

if [[ ${#conf_files[@]} -eq 0 ]]; then
    echo -e "${YELLOW}⚠ No worker-*.conf files found in the current directory.${NC}"
    exit 0
fi

for cfg in "${conf_files[@]}"; do
    # Read key=value pairs, ignoring comments and empty lines
    while IFS='=' read -r key value; do
        # Trim whitespace
        key=$(echo "$key" | tr -d ' \t')
        value=$(echo "$value" | sed -e 's/^ *//' -e 's/ *$//')
        # Skip empty lines or comments
        [[ -z "$key" ]] && continue
        [[ "$key" == \#* ]] && continue
        case "$key" in
            owner_address)
                OWNER_ADDRESS="$value"
                ;;
            node_wallet_key)
                NODE_WALLET_KEY="$value"
                ;;
            hf_token)
                HF_TOKEN="$value"
                ;;
            root_contract_address)
                ROOT_CONTRACT_ADDRESS="$value"
                ;;
        esac
    done < "$cfg"

    # Validate presence
    [[ -z "${OWNER_ADDRESS-}" ]] && errors+=("$cfg: missing owner_address")
    [[ -z "${NODE_WALLET_KEY-}" ]] && errors+=("$cfg: missing node_wallet_key")
    [[ -z "${HF_TOKEN-}" ]] && errors+=("$cfg: missing hf_token")
    [[ -z "${ROOT_CONTRACT_ADDRESS-}" ]] && errors+=("$cfg: missing root_contract_address")

    # Validate formats only if present
    if [[ -n "${OWNER_ADDRESS-}" ]]; then
        if [[ "$OWNER_ADDRESS" != EQ* ]] || (( ${#OWNER_ADDRESS} < 10 )); then
            errors+=("$cfg: invalid owner_address (must start with 'EQ' and be >=10 chars)")
        fi
    fi
    if [[ -n "${ROOT_CONTRACT_ADDRESS-}" ]]; then
        if [[ "$ROOT_CONTRACT_ADDRESS" != EQ* ]] || (( ${#ROOT_CONTRACT_ADDRESS} < 10 )); then
            errors+=("$cfg: invalid root_contract_address (must start with 'EQ' and be >=10 chars)")
        fi
    fi
    if [[ -n "${NODE_WALLET_KEY-}" ]]; then
        if ! is_base64 "$NODE_WALLET_KEY"; then
            errors+=("$cfg: invalid node_wallet_key (not valid base64)")
        fi
    fi
    if [[ -n "${HF_TOKEN-}" ]]; then
        if [[ "$HF_TOKEN" != hf_* ]]; then
            errors+=("$cfg: invalid hf_token (must start with 'hf_')")
        fi
    fi

    # Unset variables for next file
    unset OWNER_ADDRESS NODE_WALLET_KEY HF_TOKEN ROOT_CONTRACT_ADDRESS
done

if [[ ${#errors[@]} -eq 0 ]]; then
    echo -e "${GREEN}All configuration files are valid.${NC}"
    # Print a simple PASS table
    printf "\n${BLUE}%-30s %s${NC}\n" "File" "Status"
    for cfg in "${conf_files[@]}"; do
        printf "${GREEN}%-30s %s${NC}\n" "$cfg" "PASS"
    done
    exit 0
else
    echo -e "${RED}Configuration validation failed with ${#errors[@]} issue(s):${NC}"
    printf "\n${BLUE}%-30s %s${NC}\n" "File" "Error"
    for err in "${errors[@]}"; do
        # Split at first colon to separate file and message
        file=$(echo "$err" | cut -d':' -f1)
        message=$(echo "$err" | cut -d':' -f2-)
        printf "${RED}%-30s %s${NC}\n" "$file" "$message"
    done
    exit 1
fi
