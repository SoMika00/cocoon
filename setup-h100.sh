#!/bin/bash
# Setup script for 2 H100 GPUs on COCOON

set -e

DRY_RUN=false
INTERACTIVE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        --dry-run)
            DRY_RUN=true
            shift
            ;;
        --interactive)
            INTERACTIVE=true
            shift
            ;;
        --help|-h)
            echo "Usage: $0 [--dry-run] [--interactive]"
            echo "  --dry-run     Show what would be generated without modifying files"
            echo "  --interactive Prompt before generating keys"
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done


echo "=== COCOON H100 Setup ==="
echo ""

# Detect GPUs
echo "Detecting H100 GPUs..."
GPU1=$(lspci | grep -i "H100\|GH100" | head -n1 | awk '{print "0000:" $1}')
GPU2=$(lspci | grep -i "H100\|GH100" | tail -n1 | awk '{print "0000:" $1}')

if [ -z "$GPU1" ] || [ -z "$GPU2" ]; then
    echo "Error: Could not detect 2 H100 GPUs"
    exit 1
fi

echo "Found GPU 1: $GPU1"
echo "Found GPU 2: $GPU2"
echo ""

# Check if COCOON distribution exists
if [ ! -d "./cocoon-worker" ]; then
    echo "COCOON worker distribution not found."
    echo "Downloading from https://ci.cocoon.org/cocoon-worker-release-latest.tar.xz"
    echo ""
    if [ "$INTERACTIVE" = true ]; then
        read -p "Download now? (y/n) " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            wget https://ci.cocoon.org/cocoon-worker-release-latest.tar.xz
            tar xzf cocoon-worker-release-latest.tar.xz
            cd cocoon-worker
        else
            echo "Please download and extract the COCOON distribution first."
            exit 1
        fi
    else
        echo "Please download and extract the COCOON distribution first."
        exit 1
    fi
else
    cd cocoon-worker
fi

# Function to ensure secure node_wallet_key
generate_wallet_key() {
    local conf_file=$1
    local key_line
    key_line=$(grep "^node_wallet_key" "$conf_file" 2>/dev/null || true)
    if [ -z "$key_line" ] || echo "$key_line" | grep -q "YOUR_\|YOUR_NODE\|placeholder\|^node_wallet_key = $"; then
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
echo "=== Configuration Files Created ==="
echo ""
echo "Next steps:"
echo "1. Edit worker-0.conf and worker-1.conf with your credentials"
echo "2. Start seal-server: ./bin/seal-server --enclave-path ./bin/enclave.signed.so"
echo "3. Launch workers using: ./launch-workers.sh"
