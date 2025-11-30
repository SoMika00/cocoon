#!/bin/bash
# Setup script for 2 H100 GPUs on COCOON

set -e

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
    cd cocoon-worker
fi

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

echo ""
echo "=== Configuration Files Created ==="
echo ""
echo "Next steps:"
echo "1. Edit worker-0.conf and worker-1.conf with your credentials"
echo "2. Start seal-server: ./bin/seal-server --enclave-path ./bin/enclave.signed.so"
echo "3. Launch workers using: ./launch-workers.sh"

