#!/bin/bash
# Script to check COCOON prerequisites for H100 GPUs

set -e

# Colors for output (consistent with other scripts)
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_help() {
    cat <<'EOF'
Usage: check-prerequisites.sh [OPTIONS]

Options:
  -h, --help       Show this help message and exit
  --json           Emit a single machine-readable JSON object on stdout
                   describing every prerequisite check with status, detail,
                   and remediation hint.

JSON schema (when --json is set):
  {
    "checks": [
      {"name":"kernel","status":"pass|warn|fail","detail":"6.16.0","hint":"..."},
      {"name":"tdx_cpu","status":"pass|warn|fail","detail":"...","hint":"..."},
      {"name":"tdx_kernel","status":"pass|warn|fail","detail":"...","hint":"..."},
      {"name":"nvidia_gpus","status":"pass|warn|fail","detail":"...","hint":"..."},
      {"name":"h100_count","status":"pass|warn|fail","detail":"...","hint":"..."},
      {"name":"qemu_version","status":"pass|warn|fail","detail":"...","hint":"..."},
      {"name":"qemu_tdx","status":"pass|warn|fail","detail":"...","hint":"..."},
      {"name":"kernel_modules","status":"pass|warn|fail","detail":"...","hint":"..."},
      {"name":"cocoon_binaries","status":"pass|warn|fail","detail":"...","hint":"..."}
    ],
    "summary": {"passed":N,"warned":N,"failed":N,"total":N},
    "overall_status": "ok|degraded|failed",
    "exit_code": 0|1
  }

Exit code is 0 unless a hard failure occurs (QEMU missing), matching current
behavior. overall_status is "failed" when any check is fail, "degraded" when
only warnings are present, and "ok" otherwise.
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

# Parse arguments
JSON=false
while [[ $# -gt 0 ]]; do
    case $1 in
        --help|-h)
            print_help
            exit 0
            ;;
        --json)
            JSON=true
            shift
            ;;
        *)
            echo "Unknown option: $1" >&2
            print_help
            exit 2
            ;;
    esac
done

# Per-check result storage: name, status (pass|warn|fail), detail, hint
CHECK_NAMES=()
CHECK_STATUS=()
CHECK_DETAIL=()
CHECK_HINT=()

add_check() {
    local name="$1"
    local status="$2"
    local detail="$3"
    local hint="$4"
    CHECK_NAMES+=("$name")
    CHECK_STATUS+=("$status")
    CHECK_DETAIL+=("$detail")
    CHECK_HINT+=("$hint")
}

# Hard failure flag (QEMU missing)
HARD_FAILURE=0

# ---------------------------------------------------------------------------
# 1. Linux kernel version (need 6.16+ for full TDX support)
# ---------------------------------------------------------------------------
KERNEL_VERSION=$(uname -r | cut -d. -f1,2)
KERNEL_MAJOR=$(echo "$KERNEL_VERSION" | cut -d. -f1)
KERNEL_MINOR=$(echo "$KERNEL_VERSION" | cut -d. -f2)

if [ "$KERNEL_MAJOR" -gt 6 ] || ([ "$KERNEL_MAJOR" -eq 6 ] && [ "$KERNEL_MINOR" -ge 16 ]); then
    KERNEL_STATUS="pass"
    KERNEL_DETAIL="$(uname -r)"
    KERNEL_HINT="No action required"
else
    KERNEL_STATUS="warn"
    KERNEL_DETAIL="$(uname -r)"
    KERNEL_HINT="Upgrade to kernel 6.16+ for full TDX support"
fi
add_check "kernel" "$KERNEL_STATUS" "$KERNEL_DETAIL" "$KERNEL_HINT"

# ---------------------------------------------------------------------------
# 2. Intel TDX-capable CPU
# ---------------------------------------------------------------------------
if grep -q "tdx" /proc/cpuinfo 2>/dev/null; then
    TDX_CPU_STATUS="pass"
    TDX_CPU_DETAIL="TDX support detected in CPU"
    TDX_CPU_HINT="No action required"
else
    TDX_CPU_STATUS="warn"
    TDX_CPU_DETAIL="TDX support not clearly detected"
    TDX_CPU_HINT="May need BIOS/UEFI configuration"
fi
add_check "tdx_cpu" "$TDX_CPU_STATUS" "$TDX_CPU_DETAIL" "$TDX_CPU_HINT"

# ---------------------------------------------------------------------------
# 3. TDX kernel support
# ---------------------------------------------------------------------------
if [ -d "/sys/firmware/tdx" ]; then
    TDX_KERNEL_STATUS="pass"
    TDX_KERNEL_DETAIL="TDX kernel support detected"
    TDX_KERNEL_HINT="No action required"
else
    TDX_KERNEL_STATUS="warn"
    TDX_KERNEL_DETAIL="TDX kernel support not detected"
    TDX_KERNEL_HINT="May need kernel modules"
fi
add_check "tdx_kernel" "$TDX_KERNEL_STATUS" "$TDX_KERNEL_DETAIL" "$TDX_KERNEL_HINT"

# ---------------------------------------------------------------------------
# 4. NVIDIA GPUs
# ---------------------------------------------------------------------------
GPU_COUNT=$(lspci | grep -i nvidia | wc -l)
if [ "$GPU_COUNT" -gt 0 ]; then
    NVIDIA_STATUS="pass"
    NVIDIA_DETAIL="Found $GPU_COUNT NVIDIA GPU(s)"
    NVIDIA_HINT="No action required"
else
    NVIDIA_STATUS="fail"
    NVIDIA_DETAIL="No NVIDIA GPUs found"
    NVIDIA_HINT="Install NVIDIA drivers and verify hardware"
fi
add_check "nvidia_gpus" "$NVIDIA_STATUS" "$NVIDIA_DETAIL" "$NVIDIA_HINT"

# ---------------------------------------------------------------------------
# 5. H100 count
# ---------------------------------------------------------------------------
H100_COUNT=$(lspci | grep -i "H100\|GH100" | wc -l)
if [ "$H100_COUNT" -gt 0 ]; then
    H100_STATUS="pass"
    H100_DETAIL="Found $H100_COUNT H100 GPU(s)"
    H100_HINT="No action required"
else
    H100_STATUS="warn"
    H100_DETAIL="No H100 GPUs detected"
    H100_HINT="CC support requires H100+ GPUs"
fi
add_check "h100_count" "$H100_STATUS" "$H100_DETAIL" "$H100_HINT"

# ---------------------------------------------------------------------------
# 6. QEMU version (need 10.1+)
# ---------------------------------------------------------------------------
QEMU_TDX_OK=0
KVM_TDX_OK=0
if command -v qemu-system-x86_64 &> /dev/null; then
    QEMU_VERSION=$(qemu-system-x86_64 --version | head -n1 | grep -oP '\d+\.\d+' | head -n1)
    QEMU_MAJOR=$(echo "$QEMU_VERSION" | cut -d. -f1)
    QEMU_MINOR=$(echo "$QEMU_VERSION" | cut -d. -f2)

    if [ "$QEMU_MAJOR" -gt 10 ] || ([ "$QEMU_MAJOR" -eq 10 ] && [ "$QEMU_MINOR" -ge 1 ]); then
        QEMU_VERSION_STATUS="pass"
        QEMU_VERSION_DETAIL="$QEMU_VERSION"
        QEMU_VERSION_HINT="No action required"
    else
        QEMU_VERSION_STATUS="warn"
        QEMU_VERSION_DETAIL="$QEMU_VERSION"
        QEMU_VERSION_HINT="10.1+ required for TDX support"
    fi
else
    QEMU_VERSION_STATUS="fail"
    QEMU_VERSION_DETAIL="QEMU not found"
    QEMU_VERSION_HINT="Install QEMU 10.1+ (see INSTALL-QEMU.md)"
    HARD_FAILURE=1
fi
add_check "qemu_version" "$QEMU_VERSION_STATUS" "$QEMU_VERSION_DETAIL" "$QEMU_VERSION_HINT"

# ---------------------------------------------------------------------------
# 7. QEMU TDX support
# ---------------------------------------------------------------------------
if command -v qemu-system-x86_64 &> /dev/null; then
    if qemu-system-x86_64 -machine help 2>/dev/null | grep -qi tdx; then
        QEMU_TDX_STATUS="pass"
        QEMU_TDX_DETAIL="QEMU TDX machine support"
        QEMU_TDX_HINT="No action required"
        QEMU_TDX_OK=1
    else
        QEMU_TDX_STATUS="fail"
        QEMU_TDX_DETAIL="QEMU TDX machine support missing"
        QEMU_TDX_HINT="Rebuild QEMU with TDX support (see compile-qemu-tdx.sh)"
    fi
else
    QEMU_TDX_STATUS="fail"
    QEMU_TDX_DETAIL="QEMU not found"
    QEMU_TDX_HINT="Install QEMU 10.1+ with TDX support"
fi
add_check "qemu_tdx" "$QEMU_TDX_STATUS" "$QEMU_TDX_DETAIL" "$QEMU_TDX_HINT"

# ---------------------------------------------------------------------------
# 8. Kernel modules for TDX/KVM
# ---------------------------------------------------------------------------
if lsmod | grep -q "^kvm " && lsmod | grep -q "^tdx "; then
    KMOD_STATUS="pass"
    KMOD_DETAIL="Kernel TDX/KVM modules loaded"
    KMOD_HINT="No action required"
    KVM_TDX_OK=1
else
    KMOD_STATUS="warn"
    KMOD_DETAIL="kvm and/or tdx modules not loaded"
    KMOD_HINT="Load kernel modules (modprobe kvm tdx)"
fi
add_check "kernel_modules" "$KMOD_STATUS" "$KMOD_DETAIL" "$KMOD_HINT"

# ---------------------------------------------------------------------------
# 9. COCOON binaries
# ---------------------------------------------------------------------------
COCOON_MISSING=0
COCOON_DETAILS=()
if [ -f "./bin/seal-server" ]; then
    COCOON_DETAILS+=("seal-server:found")
else
    COCOON_DETAILS+=("seal-server:missing")
    COCOON_MISSING=1
fi
if [ -f "./bin/enclave.signed.so" ]; then
    COCOON_DETAILS+=("enclave.signed.so:found")
else
    COCOON_DETAILS+=("enclave.signed.so:missing")
    COCOON_MISSING=1
fi
if [ -f "./scripts/cocoon-launch" ]; then
    COCOON_DETAILS+=("cocoon-launch:found")
else
    COCOON_DETAILS+=("cocoon-launch:missing")
    COCOON_MISSING=1
fi

COCOON_DETAIL=$(printf '%s ' "${COCOON_DETAILS[@]}")
COCOON_DETAIL="${COCOON_DETAIL% }"
if [ "$COCOON_MISSING" -eq 0 ]; then
    COCOON_STATUS="pass"
    COCOON_HINT="No action required"
else
    COCOON_STATUS="warn"
    COCOON_HINT="Download COCOON distribution (see setup-h100.sh)"
fi
add_check "cocoon_binaries" "$COCOON_STATUS" "$COCOON_DETAIL" "$COCOON_HINT"

# ---------------------------------------------------------------------------
# Output handling – human or JSON
# ---------------------------------------------------------------------------
if [ "$JSON" = true ]; then
    checks_json="["
    passed=0
    warned=0
    failed=0
    for idx in "${!CHECK_NAMES[@]}"; do
        name_esc=$(json_escape "${CHECK_NAMES[$idx]}")
        status_esc=$(json_escape "${CHECK_STATUS[$idx]}")
        detail_esc=$(json_escape "${CHECK_DETAIL[$idx]}")
        hint_esc=$(json_escape "${CHECK_HINT[$idx]}")
        case "${CHECK_STATUS[$idx]}" in
            pass) ((passed++)) ;;
            warn) ((warned++)) ;;
            fail) ((failed++)) ;;
        esac
        if [[ $idx -gt 0 ]]; then
            checks_json+=","
        fi
        checks_json+="{\"name\":\"$name_esc\",\"status\":\"$status_esc\",\"detail\":\"$detail_esc\",\"hint\":\"$hint_esc\"}"
    done
    checks_json+="]"

    total=${#CHECK_NAMES[@]}
    if [ "$failed" -gt 0 ]; then
        overall="failed"
    elif [ "$warned" -gt 0 ]; then
        overall="degraded"
    else
        overall="ok"
    fi

    exit_code=0
    if [ "$HARD_FAILURE" -eq 1 ]; then
        exit_code=1
    fi

    printf '{"checks":%s,"summary":{"passed":%d,"warned":%d,"failed":%d,"total":%d},"overall_status":"%s","exit_code":%d}\n' \
        "$checks_json" "$passed" "$warned" "$failed" "$total" "$overall" "$exit_code"
    exit $exit_code
fi

# ---------------------------------------------------------------------------
# Human-readable mode (unchanged)
# ---------------------------------------------------------------------------
echo "=== COCOON Prerequisites Check ==="
echo ""

# Check Linux kernel version (need 6.16+ for full TDX support)
echo "1. Checking Linux kernel version..."
if [ "$KERNEL_STATUS" = "pass" ]; then
    echo -e "   ${GREEN}✓${NC} Kernel version: $(uname -r) (OK - 6.16+ required)"
else
    echo -e "   ${YELLOW}⚠${NC} Kernel version: $(uname -r) (WARNING - 6.16+ recommended for full TDX support)"
fi
echo ""

# Check for Intel TDX-capable CPU
echo "2. Checking Intel TDX support..."
if [ "$TDX_CPU_STATUS" = "pass" ]; then
    echo -e "   ${GREEN}✓${NC} TDX support detected in CPU"
else
    echo -e "   ${YELLOW}⚠${NC} TDX support not clearly detected (may need BIOS/UEFI configuration)"
fi

# Check for TDX in kernel
if [ "$TDX_KERNEL_STATUS" = "pass" ]; then
    echo -e "   ${GREEN}✓${NC} TDX kernel support detected"
else
    echo -e "   ${YELLOW}⚠${NC} TDX kernel support not detected (may need kernel modules)"
fi
echo ""

# Check for NVIDIA GPUs
echo "3. Checking NVIDIA GPUs..."
if [ "$GPU_COUNT" -gt 0 ]; then
    echo -e "   ${GREEN}✓${NC} Found $GPU_COUNT NVIDIA GPU(s):"
    lspci | grep -i nvidia | while read line; do
        PCI_ID=$(echo "$line" | awk '{print $1}')
        GPU_NAME=$(echo "$line" | sed 's/.*: //')
        echo "     - $PCI_ID: $GPU_NAME"
    done

    # Check for H100 specifically
    if [ "$H100_COUNT" -gt 0 ]; then
        echo -e "   ${GREEN}✓${NC} Found $H100_COUNT H100 GPU(s) (CC support required)"
    fi
else
    echo -e "   ${RED}✗${NC} No NVIDIA GPUs found"
fi
echo ""

# Check QEMU version (need 10.1+) and TDX capability
echo "4. Checking QEMU version and TDX support..."
if command -v qemu-system-x86_64 &> /dev/null; then
    if [ "$QEMU_VERSION_STATUS" = "pass" ]; then
        echo -e "   ${GREEN}✓${NC} QEMU version: $QEMU_VERSION (OK - 10.1+ required)"
    else
        echo -e "   ${YELLOW}⚠${NC} QEMU version: $QEMU_VERSION (WARNING - 10.1+ required for TDX support)"
    fi

    # TDX machine support check (non-fatal, always report)
    if [ "$QEMU_TDX_OK" -eq 1 ]; then
        echo -e "   ${GREEN}✓${NC} QEMU TDX machine support"
    else
        echo -e "   ${RED}✗${NC} QEMU TDX machine support"
    fi
else
    echo -e "   ${RED}✗${NC} QEMU not found (required for TDX support)"
fi
echo ""

# Kernel modules check for TDX/KVM (non-fatal, always report)
echo "5. Checking kernel modules for TDX..."
if [ "$KVM_TDX_OK" -eq 1 ]; then
    echo -e "   ${GREEN}✓${NC} Kernel TDX/KVM modules"
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
if [ "$HARD_FAILURE" -eq 1 ]; then
    exit 1
fi
exit 0
