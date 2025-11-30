#!/bin/bash
# Generate keys for COCOON worker configuration

echo "=== COCOON Key Generation ==="
echo ""

# Generate node_wallet_key (base64)
echo "Generating node_wallet_key..."
NODE_KEY=$(openssl rand -base64 32)
echo ""
echo "Add this to your worker-0.conf and worker-1.conf:"
echo "node_wallet_key = $NODE_KEY"
echo ""
echo "⚠️  IMPORTANT: Keep this key secret and secure!"
echo ""

# Instructions for other required values
echo "=== Other Required Configuration Values ==="
echo ""
echo "1. owner_address:"
echo "   Your TON wallet address that will receive payments"
echo "   Format: EQD... (TON address)"
echo ""
echo "2. hf_token:"
echo "   Get from: https://huggingface.co/settings/tokens"
echo "   Create a new token with 'read' permissions"
echo ""
echo "3. root_contract_address:"
echo "   This should be in the worker.conf.example from the COCOON distribution"
echo "   Check the downloaded cocoon-worker/worker.conf.example file"
echo ""

