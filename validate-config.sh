#!/usr/bin/env bash

# validate-config.sh - Validate worker configuration files
#
# Checks for required keys and basic format validation.
# Supports optional file list, --dry-run, and --help.

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NC='\033[0m'

usage() {
  cat <<EOF
Usage: ${0##*/} [options] [files...]

Options:
  --help        Show this help message and exit
  --dry-run     Report issues but always exit with status 0

If no files are specified, all files matching 'worker-*.conf' in the current directory are validated.
EOF
}

# Parse options
DRY_RUN=false
FILES=()
while (( "$#" )); do
  case "$1" in
    --help)
      usage
      exit 0
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    --*)
      echo -e "${RED}Error:${NC} Unknown option: $1" >&2
      usage
      exit 1
      ;;
    *)
      FILES+=("$1")
      shift
      ;;
  esac
done

# If no files provided, find default worker config files
if [ ${#FILES[@]} -eq 0 ]; then
  mapfile -t FILES < <(printf "%s\n" worker-*.conf 2>/dev/null | grep -v "*\.conf")
fi

if [ ${#FILES[@]} -eq 0 ]; then
  echo -e "${YELLOW}Warning:${NC} No configuration files found to validate."
  exit 0
fi

# Validation helpers
required_keys=(owner_address node_wallet_key hf_token root_contract_address)

has_error=false

for cfg in "${FILES[@]}"; do
  if [ ! -f "$cfg" ]; then
    echo -e "${RED}Error:${NC} File not found: $cfg"
    has_error=true
    continue
  fi
  # Read key values (strip spaces, ignore comments)
  declare -A values
  while IFS='=' read -r key val; do
    # Remove leading/trailing whitespace
    key=$(echo "$key" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    val=$(echo "$val" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')
    # Skip empty lines or comments
    [[ -z "$key" ]] && continue
    [[ "$key" =~ ^# ]] && continue
    values["$key"]="$val"
  done < <(grep -E "^[[:space:]]*[^#]" "$cfg" || true)

  for k in "${required_keys[@]}"; do
    if [[ -z "${values[$k]:-}" ]]; then
      echo -e "${RED}Error:${NC} $cfg: Missing required key '$k'"
      has_error=true
    fi
  done

  # Specific format checks only if present
  if [[ -n "${values[owner_address]:-}" ]]; then
    if [[ "${values[owner_address]}" != EQD* ]]; then
      echo -e "${RED}Error:${NC} $cfg: 'owner_address' must start with 'EQD'"
      has_error=true
    fi
  fi

  if [[ -n "${values[root_contract_address]:-}" ]]; then
    if [[ "${values[root_contract_address]}" != EQD* ]]; then
      echo -e "${RED}Error:${NC} $cfg: 'root_contract_address' must start with 'EQD'"
      has_error=true
    fi
  fi

  if [[ -n "${values[node_wallet_key]:-}" ]]; then
    if [[ ! "${values[node_wallet_key]}" =~ ^[A-Za-z0-9+/=]+$ ]]; then
      echo -e "${RED}Error:${NC} $cfg: 'node_wallet_key' is not a valid base64 string"
      has_error=true
    fi
  fi

done

if $has_error; then
  if $DRY_RUN; then
    echo -e "${YELLOW}Dry-run mode:${NC} validation issues reported above."
    exit 0
  else
    echo -e "${RED}Validation failed.${NC}"
    exit 1
  fi
else
  echo -e "${GREEN}All configuration files are valid.${NC}"
  exit 0
fi
