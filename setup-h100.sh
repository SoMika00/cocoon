#!/bin/bash
# Setup script for 2 H100 GPUs on COCOON
#
# Downloads the latest COCOON worker distribution when missing, verifies its
# SHA256 checksum (if a .sha256 file is available), extracts it safely, and
# prepares the working directory.
#
# Usage: ./setup-h100.sh [--dry-run] [--json] [--interactive]
#
# Exit codes:
#   0  success (setup complete or dry-run simulation)
#   1  download/checksum/extraction failure
#   2  usage error (unknown option)

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

DRY_RUN=false
INTERACTIVE=false
JSON=false

# Predefined distribution URL and tarball name
TAR="cocoon-worker-release-latest.tar.xz"
URL="https://cocoon.org/releases/${TAR}"

print_help() {
    cat <<EOF
Usage: $0 [--dry-run] [--json] [--interactive]

Options:
  --dry-run      Simulate actions without downloading, extracting, or modifying files
  --json         Emit a single machine-readable JSON object on stdout
  --interactive  Prompt before generating secure node_wallet_key values
  --help, -h     Show this help message and exit

JSON schema (when --json is set):
  {
    "downloaded": true|false,
    "checksum_verified": true|false,
    "extracted": true|false,
    "working_dir": "<path>",
    "message": "<human-readable message>",
    "exit_code": 0|1
  }

Exit codes:
  0  success (setup complete or dry-run simulation)
  1  download/checksum/extraction failure
  2  usage error (unknown option)
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

# Emit a JSON result object and exit with the given code.
emit_json() {
    local downloaded="$1"
    local checksum_verified="$2"
    local extracted="$3"
    local working_dir="$4"
    local message="$5"
    local exit_code="$6"

    local wd_esc msg_esc
    wd_esc=$(json_escape "$working_dir")
    msg_esc=$(json_escape "$message")

    printf '{"downloaded":%s,"checksum_verified":%s,"extracted":%s,"working_dir":"%s","message":"%s","exit_code":%d}\n' \
        "$downloaded" "$checksum_verified" "$extracted" "$wd_esc" "$msg_esc" "$exit_code"
    exit "$exit_code"
}

# Parse arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --json)
            JSON=true
            shift
            ;;
        --interactive)
            INTERACTIVE=true
            shift
            ;;
        --help|-h)
            print_help
            exit 0
            ;;
        *)
            echo "Unknown option: $1" >&2
            print_help >&2
            exit 2
            ;;
    esac
done

# ---------------------------------------------------------------------------
# Detect existing distribution (cocoon-worker/ or release-*/)
# ---------------------------------------------------------------------------
DIST_DIR=""
if [ -d "./cocoon-worker" ]; then
    DIST_DIR="cocoon-worker"
elif ls -d release-* >/dev/null 2>&1; then
    DIST_DIR=$(ls -d release-* 2>/dev/null | head -n1)
fi

# ---------------------------------------------------------------------------
# Already set up: skip download and extraction
# ---------------------------------------------------------------------------
if [ -n "$DIST_DIR" ]; then
    if [ "$JSON" = true ]; then
        emit_json false false false "$DIST_DIR" "Setup already complete; using existing distribution in $DIST_DIR" 0
    fi
    echo -e "${GREEN}Setup already complete.${NC} Using existing distribution in ${BLUE}$DIST_DIR${NC}"
    cd "$DIST_DIR"
    exit 0
fi

# ---------------------------------------------------------------------------
# Distribution missing: download, verify, extract
# ---------------------------------------------------------------------------
if [ "$JSON" != true ]; then
    echo -e "${BLUE}=== COCOON H100 Setup ===${NC}"
    echo ""
    echo "COCOON worker distribution not found."
fi

# Dry-run: report intended actions without performing them
if [ "$DRY_RUN" = true ]; then
    if [ "$JSON" = true ]; then
        emit_json false false false "" "[DRY-RUN] Would download $URL, verify checksum if available, and extract $TAR" 0
    fi
    echo -e "[DRY-RUN] Would download: ${YELLOW}$URL${NC}"
    echo -e "[DRY-RUN] Would verify SHA256 checksum if ${TAR}.sha256 is available"
    echo -e "[DRY-RUN] Would extract: ${YELLOW}$TAR${NC} (preserving permissions)"
    echo -e "[DRY-RUN] Would change into the extracted directory"
    echo -e "[DRY-RUN] Completed simulation - no network or file changes"
    exit 0
fi

# Download the tarball
if [ "$JSON" != true ]; then
    echo "Downloading $TAR via wget..."
fi
if ! wget -q "$URL" -O "$TAR"; then
    if [ "$JSON" = true ]; then
        emit_json false false false "" "Failed to download distribution from $URL" 1
    fi
    echo -e "${RED}Error: Failed to download distribution from $URL${NC}" >&2
    exit 1
fi

# Verify SHA256 checksum if a .sha256 file is available alongside the tarball
CHECKSUM_VERIFIED=false
SHA_FILE="${TAR}.sha256"
if [ -f "$SHA_FILE" ]; then
    if [ "$JSON" != true ]; then
        echo "Verifying SHA256 checksum..."
    fi
    EXPECTED=$(awk '{print $1}' "$SHA_FILE" | head -n1)
    ACTUAL=$(sha256sum "$TAR" | awk '{print $1}')
    if [ "$EXPECTED" != "$ACTUAL" ]; then
        if [ "$JSON" = true ]; then
            emit_json true false false "" "Checksum mismatch: expected $EXPECTED, got $ACTUAL" 1
        fi
        echo -e "${RED}Error: Checksum mismatch for $TAR${NC}" >&2
        echo -e "  Expected: $EXPECTED" >&2
        echo -e "  Actual:   $ACTUAL" >&2
        rm -f "$TAR"
        exit 1
    fi
    CHECKSUM_VERIFIED=true
    if [ "$JSON" != true ]; then
        echo -e "${GREEN}✓${NC} Checksum verified"
    fi
else
    if [ "$JSON" != true ]; then
        echo -e "${YELLOW}⚠${NC} No .sha256 file found; skipping checksum verification"
    fi
fi

# Extract the tarball safely (preserve permissions)
if [ "$JSON" != true ]; then
    echo "Extracting $TAR..."
fi
if ! tar -xJf "$TAR"; then
    if [ "$JSON" = true ]; then
        emit_json true "$CHECKSUM_VERIFIED" false "" "Failed to extract $TAR" 1
    fi
    echo -e "${RED}Error: Failed to extract $TAR${NC}" >&2
    exit 1
fi

# Determine the extracted directory
if [ -d "./cocoon-worker" ]; then
    DIST_DIR="cocoon-worker"
elif ls -d release-* >/dev/null 2>&1; then
    DIST_DIR=$(ls -d release-* 2>/dev/null | head -n1)
else
    if [ "$JSON" = true ]; then
        emit_json true "$CHECKSUM_VERIFIED" true "" "Could not find extracted cocoon-worker or release-* directory" 1
    fi
    echo -e "${RED}Error: Could not find extracted cocoon-worker or release-* directory${NC}" >&2
    exit 1
fi

cd "$DIST_DIR"

if [ "$JSON" = true ]; then
    emit_json true "$CHECKSUM_VERIFIED" true "$DIST_DIR" "Downloaded, verified, and extracted distribution into $DIST_DIR" 0
fi

echo -e "${GREEN}Extracted and changed into ${BLUE}$DIST_DIR${NC}"

# ---------------------------------------------------------------------------
# Prepare configuration files (unchanged behavior)
# ---------------------------------------------------------------------------

# Detect GPUs
echo "Detecting H100 GPUs..."
GPU1=$(lspci | grep -i "H100\|GH100" | head -n1 | awk '{print "0000:" $1}')
GPU2=$(lspci | grep -i "H100\|GH100" | tail -n1 | awk '{print "0000:" $1}')

if [ -z "$GPU1" ] || [ -z "$GPU2" ]; then
    echo -e "${RED}Error: Could not detect 2 H100 GPUs${NC}" >&2
    exit 1
fi

echo "Found GPU 1: $GPU1"
echo "Found GPU 2: $GPU2"
echo ""

# Function to ensure secure node_wallet_key
generate_wallet_key() {
    local conf_file=$1
    local key_line
    key_line=$(grep "^node_wallet_key" "$conf_file" 2>/dev/null || true)
    if [ -z "$key_line" ] || echo "$key_line" | grep -q "YOUR_\|YOUR_NODE\|placeholder|^node_wallet_key = $"; then
        local new_key
        new_key=$(openssl rand -base64 32)
        if [ "$DRY_RUN" = true ]; then
            echo "  [DRY-RUN] Would generate unique key for $conf_file"
            return 0
        fi
        if [ "$INTERACTIVE" = true ]; then
            read -p "Generate secure node_wallet_key for $conf_file? (y/n) " -n 1 -r
            echo
            if [[ ! $REPLY =~ ^[Yy]$ ]]; then
                echo "Skipping key generation for $conf_file"
                return 0
            fi
        fi
        # Replace or append with auto-generated marker
        if grep -q "^node_wallet_key" "$conf_file"; then
            sed -i "/^node_wallet_key/d" "$conf_file"
        fi
        echo "# AUTO-GENERATED - keep secret" >> "$conf_file"
        echo "node_wallet_key = $new_key" >> "$conf_file"
        echo "  Generated secure key for $conf_file (marked AUTO-GENERATED)"
    fi
}

# Create configuration files
echo "Creating configuration files..."

# Worker 0 configuration
if [ ! -f "worker-0.conf" ]; then
    cp worker.conf.example worker-0.conf
    echo ""
    echo "Created worker-0.conf - Please edit with your settings:"
    echo "  - owner_address: Your TON wallet address"
    echo "  - node_wallet_key: Generate with: openssl rand -base64 32"
    echo "  - hf_token: Your Hugging Face token"
    echo "  - root_contract_address: From distribution"
    echo "  - gpu: $GPU1 (already set)"
    echo "  - instance: 0 (already set)"
fi

generate_wallet_key worker-0.conf

# Worker 1 configuration
if [ ! -f "worker-1.conf" ]; then
    cp worker.conf.example worker-1.conf
    # Update GPU and instance for worker 1
    sed -i "s/gpu = .*/gpu = $GPU2/" worker-1.conf
    sed -i "s/instance = .*/instance = 1/" worker-1.conf
    sed -i "s/persistent = .*/persistent = persistent-worker-1.img/" worker-1.conf
    echo ""
    echo "Created worker-1.conf - Please edit with your settings:"
    echo "  - Same settings as worker-0.conf"
    echo "  - gpu: $GPU2 (already set)"
    echo "  - instance: 1 (already set)"
fi

generate_wallet_key worker-1.conf

if [ "$DRY_RUN" = true ]; then
    echo ""
    echo "[DRY-RUN] Completed - no files modified"
    exit 0
fi

echo ""
echo -e "${GREEN}=== Configuration Files Created ===${NC}"
echo ""
echo "Next steps:"
echo "1. Edit worker-0.conf and worker-1.conf with your credentials"
echo "2. Start seal-server: ./bin/seal-server --enclave-path ./bin/enclave.signed.so"
echo "3. Launch workers using: ./launch-workers.sh"
