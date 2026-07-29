#!/bin/bash
# Script to check COCOON prerequisites for H100 GPUs

set -e

# Colors for output (consistent with other scripts)
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

 echo "=== COCOON Prerequisites Check ==="
echo ""

# Check Linux kernel version (need 6.16+ for full TDX support)
echo "1. Checking Linux kernel version..."
KERNEL_VERSION=$(uname -r | cut -d. -f1,2)
KERNEL_MAJOR=$(echo $KERNEL_VERSION | cut -d. -f1)
KERNEL_MINOR=$(echo $KERNEL_VERSION | cut -d. -f2)

if [ "$KERNEL_MAJOR" -gt 6 ] || ([ "$KERNEL_MAJOR" -eq 6 ] && [ "$KERNEL_MINOR" -ge 16 ]); then
    echo -e "   ${GREEN}✓${NC} Kernel version: $(uname -r) (OK - 6.16+ required)"
else
    echo -e "   ${YELLOW}⚠${NC} Kernel version: $(uname -r) (WARNING - 6.16+ recommended for full TDX support)"
fi
echo ""

# Check for Intel TDX-capable CPU
echo "2. Checking Intel TDX support..."
if grep -q "tdx" /proc/cpuinfo 2>/dev/null; then
    echo -e "   ${GREEN}✓${NC} TDX support detected in CPU"
else
    echo -e "   ${YELLOW}⚠${NC} TDX support not clearly detected (may need BIOS/UEFI configuration)"
fi

# Check for TDX in kernel
if [ -d "/sys/firmware/tdx" ]; then
    echo -e "   ${GREEN}✓${NC} TDX kernel support detected"
else
    echo -e "   ${YELLOW}⚠${NC} TDX kernel support not detected (may need kernel modules)"
fi
echo ""

# Check for NVIDIA GPUs
echo "3. Checking NVIDIA GPUs..."
GPU_COUNT=$(lspci | grep -i nvidia | wc -l)
if [ "$GPU_COUNT" -gt 0 ]; then
    echo -e "   ${GREEN}✓${NC} Found $GPU_COUNT NVIDIA GPU(s):"
    lspci | grep -i nvidia | while read line; do
        PCI_ID=$(echo "$line" | awk '{print $1}')
        GPU_NAME=$(echo "$line" | sed 's/.*: //')
        echo "     - $PCI_ID: $GPU_NAME"
    done
    
    # Check for H100 specifically
    H100_COUNT=$(lspci | grep -i "H100\|GH100" | wc -l)
    if [ "$H100_COUNT" -gt 0 ]; then
        echo -e "   ${GREEN}✓${NC} Found $H100_COUNT H100 GPU(s) (CC support required)"
    fi
else
    echo -e "   ${RED}✗${NC} No NVIDIA GPUs found"
fi
echo ""

# Check QEMU version (need 10.1+) and TDX capability
 echo "4. Checking QEMU version and TDX support..."
QEMU_TDX_OK=0
KVM_TDX_OK=0
if command -v qemu-system-x86_64 &> /dev/null; then
    QEMU_VERSION=$(qemu-system-x86_64 --version | head -n1 | grep -oP '\d+\.\d+' | head -n1)
    QEMU_MAJOR=$(echo $QEMU_VERSION | cut -d. -f1)
    QEMU_MINOR=$(echo $QEMU_VERSION | cut -d. -f2)
    
    if [ "$QEMU_MAJOR" -gt 10 ] || ([ "$QEMU_MAJOR" -eq 10 ] && [ "$QEMU_MINOR" -ge 1 ]); then
        echo -e "   ${GREEN}✓${NC} QEMU version: $QEMU_VERSION (OK - 10.1+ required)"
    else
        echo -e "   ${YELLOW}⚠${NC} QEMU version: $QEMU_VERSION (WARNING - 10.1+ required for TDX support)"
    fi

    # TDX machine support check (non-fatal, always report)
    if qemu-system-x86_64 -machine help 2>/dev/null | grep -qi tdx; then
        echo -e "   ${GREEN}✓${NC} QEMU TDX machine support"
        QEMU_TDX_OK=1
    else
        echo -e "   ${RED}✗${NC} QEMU TDX machine support"
    fi
else
    echo -e "   ${RED}✗${NC} QEMU not found (required for TDX support)"
fi
echo ""

# Kernel modules check for TDX/KVM (non-fatal, always report)
echo "5. Checking kernel modules for TDX..."
if lsmod | grep -q "^kvm " && lsmod | grep -q "^tdx "; then
    echo -e "   ${GREEN}✓${NC} Kernel TDX/KVM modules"
    KVM_TDX_OK=1
else
    echo -e "   ${YELLOW}⚠${NC} Kernel TDX/KVM modules (kvm and/or tdx not loaded)"
fi
echo ""

# Check for seal-server binary
echo "6. Checking COCOON binaries..."
if [ -f "./bin/seal-server" ]; then
    echo -e "   ${GREEN}✓${NC} seal-server found"
else
    echo -e "   ${YELLOW}⚠${NC} seal-server not found (will need to download COCOON distribution)"
fi

if [ -f "./bin/enclave.signed.so" ]; then
    echo -e "   ${GREEN}✓${NC} enclave.signed.so found"
else
    echo -e "   ${YELLOW}⚠${NC} enclave.signed.so not found (will need to download COCOON distribution)"
fi

if [ -f "./scripts/cocoon-launch" ]; then
    echo -e "   ${GREEN}✓${NC} cocoon-launch script found"
else
    echo -e "   ${YELLOW}⚠${NC} cocoon-launch script not found (will need to download COCOON distribution)"
fi
echo ""

# Check GPU PCI addresses
echo "7. GPU PCI Addresses for configuration:"
lspci | grep -i nvidia | awk '{print "   GPU " NR-1 ": 0000:" $1}' | while read line; do
    echo "$line"
done
echo ""

 echo "=== Summary ==="
echo "If all checks pass, you're ready to configure COCOON workers!"
echo "Next steps:"
echo "1. Download COCOON worker distribution"
echo "2. Configure worker.conf with your settings"
echo "3. Start seal-server"
echo "4. Launch workers for each GPU"

# Exit non-zero only on hard failures (QEMU missing); TDX status is always reported
if ! command -v qemu-system-x86_64 &> /dev/null; then
    exit 1
fi
exit 0
