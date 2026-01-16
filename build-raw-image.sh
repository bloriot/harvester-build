#!/bin/bash
# ============================================================================
# Script: build-raw-image.sh
# Description: Create a raw disk image with EFI/BIOS boot for Harvester
# ============================================================================

# Strict mode: stop the script on the first error
set -e

# ============================================================================
# Configuration Variables & Defaults
# ============================================================================
VERSION=""
PROJECT_PREFIX="harvester"
ARCH="amd64"
ARTIFACTS_DIR="harvester-build/harvester-installer/dist/artifacts" # Default path
VM_MEMORY=8192

# Default Settings (can be overridden by flags)
BOOT_MODE="efi"         # Options: efi, bios
OUTPUT_FORMAT="raw-zst" # Options: raw-zst, qcow2

# ============================================================================
# Helper Functions
# ============================================================================

log() { echo -e "\n\033[1;32m[INFO]\033[0m $1"; }
warn() { echo -e "\n\033[1;33m[WARN]\033[0m $1"; }
error() { echo -e "\n\033[1;31m[ERROR]\033[0m $1"; exit 1; }

usage() {
    echo "Usage: $0 [options]"
    echo "Options:"
    echo "  -b, --boot-mode [efi|bios]   Set boot mode (default: efi)"
    echo "  -f, --format [raw-zst|qcow2] Set output format (default: raw-zst)"
    echo "  -v, --version [VERSION]      Set specific version (auto-detected if empty)"
    echo "  -d, --dir [DIRECTORY]        Set artifacts directory"
    echo "  -h, --help                   Show this help message"
    exit 0
}

cleanup() {
    # Clean up temp files
    if [ -n "$TEMP_OVMF_VARS" ] && [ -f "$TEMP_OVMF_VARS" ]; then
        rm -f "$TEMP_OVMF_VARS"
    fi
}
trap cleanup EXIT

# ============================================================================
# Step 0: Argument Parsing
# ============================================================================
while [[ "$#" -gt 0 ]]; do
    case $1 in
        -b|--boot-mode) BOOT_MODE="$2"; shift ;;
        -f|--format) OUTPUT_FORMAT="$2"; shift ;;
        -v|--version) VERSION="$2"; shift ;;
        -d|--dir) ARTIFACTS_DIR="$2"; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown parameter passed: $1"; usage ;;
    esac
    shift
done

# Validate inputs
if [[ "$BOOT_MODE" != "efi" && "$BOOT_MODE" != "bios" ]]; then
    error "Invalid boot mode: $BOOT_MODE. Use 'efi' or 'bios'."
fi

if [[ "$OUTPUT_FORMAT" != "raw-zst" && "$OUTPUT_FORMAT" != "qcow2" ]]; then
    error "Invalid format: $OUTPUT_FORMAT. Use 'raw-zst' or 'qcow2'."
fi

# Remove trailing slash from ARTIFACTS_DIR if present
ARTIFACTS_DIR="${ARTIFACTS_DIR%/}"

# ============================================================================
# Step 1: Pre-flight Checks
# ============================================================================
log "Step 1: Pre-flight checks..."
echo "  Boot Mode: $BOOT_MODE"
echo "  Output Format: $OUTPUT_FORMAT"
echo "  Artifacts Directory: $ARTIFACTS_DIR"

if [ ! -d "$ARTIFACTS_DIR" ]; then
    error "Artifacts directory not found: $ARTIFACTS_DIR"
fi

for tool in qemu-system-x86_64 qemu-img; do
    if ! command -v "$tool" &> /dev/null; then
        error "Required tool '$tool' is not installed."
    fi
done

if [[ "$OUTPUT_FORMAT" == "raw-zst" ]] && ! command -v zstd &> /dev/null; then
    error "'zstd' is required for raw-zst format."
fi

if [ -e /dev/kvm ] && [ -r /dev/kvm ] && [ -w /dev/kvm ]; then
    echo "  KVM is available and accessible."
else
    error "KVM (/dev/kvm) is not accessible."
fi

# ============================================================================
# Step 2: Version Detection & File Paths
# ============================================================================
if [ -z "$VERSION" ]; then
  # FIX: Wildcard * must be OUTSIDE quotes to expand correctly
  ISO_FILE=$(ls -t "${ARTIFACTS_DIR}"/harvester-*-"${ARCH}".iso 2>/dev/null | head -1)
  
  if [ -n "$ISO_FILE" ]; then
    # Extract version: harvester-(v1.7.0)-amd64.iso
    VERSION=$(basename "$ISO_FILE" | sed "s/harvester-\(.*\)-${ARCH}\.iso/\1/")
    PROJECT_PREFIX="harvester-${VERSION}"
    log "Auto-detected version: $VERSION"
  else
    error "Could not find ISO file in ${ARTIFACTS_DIR}/ matching pattern 'harvester-*-${ARCH}.iso'"
  fi
else
  PROJECT_PREFIX="harvester-${VERSION}"
fi

ISO_FILE="${ARTIFACTS_DIR}/${PROJECT_PREFIX}-${ARCH}.iso"
KERNEL_FILE="${ARTIFACTS_DIR}/${PROJECT_PREFIX}-vmlinuz-${ARCH}"
INITRD_FILE="${ARTIFACTS_DIR}/${PROJECT_PREFIX}-initrd-${ARCH}"

# Verify files exist
for file in "$ISO_FILE" "$KERNEL_FILE" "$INITRD_FILE"; do
  if [ ! -f "$file" ]; then error "Required file not found: $file"; fi
done

# ============================================================================
# Step 3: Boot Mode Configuration (OVMF for EFI)
# ============================================================================
USE_SEPARATE_VARS=false
OVMF_CODE=""
OVMF_VARS=""

if [[ "$BOOT_MODE" == "efi" ]]; then
    log "Step 3: Configuring EFI (OVMF)..."
    
    OVMF_PATHS=(
        "/usr/share/qemu/ovmf-x86_64-code.bin:/usr/share/qemu/ovmf-x86_64-vars.bin"
        "/usr/share/OVMF/OVMF_CODE.fd:/usr/share/OVMF/OVMF_VARS.fd"
        "/usr/share/OVMF/OVMF_CODE_4M.fd:/usr/share/OVMF/OVMF_VARS_4M.fd"
        "/usr/share/edk2-ovmf/x64/OVMF_CODE.fd:/usr/share/edk2-ovmf/x64/OVMF_VARS.fd"
    )

    for path_pair in "${OVMF_PATHS[@]}"; do
        IFS=":" read -r code vars <<< "$path_pair"
        if [ -f "$code" ] && [ -f "$vars" ]; then
            OVMF_CODE="$code"; OVMF_VARS="$vars"; USE_SEPARATE_VARS=true
            echo "  Found separate OVMF files."
            break
        fi
    done

    # Fallback to combined
    if [ -z "$OVMF_CODE" ]; then
        if [ -f /usr/share/OVMF/OVMF.fd ]; then OVMF_CODE="/usr/share/OVMF/OVMF.fd";
        elif [ -f /usr/share/ovmf/OVMF.fd ]; then OVMF_CODE="/usr/share/ovmf/OVMF.fd";
        else error "OVMF firmware not found."; fi
        echo "  Found combined OVMF file."
    fi

    # Prepare VARS
    if [ "$USE_SEPARATE_VARS" = true ]; then
        TEMP_OVMF_VARS=$(mktemp)
        cp "$OVMF_VARS" "$TEMP_OVMF_VARS"
        chmod 644 "$TEMP_OVMF_VARS"
    fi
else
    log "Step 3: Configuring BIOS (Legacy Mode)..."
    echo "  Skipping OVMF setup."
fi

# ============================================================================
# Step 4: Create & Install QEMU VM
# ============================================================================
log "Step 4: Creating raw disk image and installing..."
RAW_FILE="${ARTIFACTS_DIR}/${PROJECT_PREFIX}-${ARCH}.raw"

if [ -f "$RAW_FILE" ]; then rm -f "$RAW_FILE"; fi

# Create sparse file
qemu-img create -f raw -o size=250G "$RAW_FILE"

HOST_RAM_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
if [ "$HOST_RAM_KB" -lt 8500000 ]; then VM_MEMORY=4096; fi

QEMU_CMD="qemu-system-x86_64 -machine q35,accel=kvm -cpu host -smp cores=2,threads=2,sockets=1 -m ${VM_MEMORY}"
QEMU_CMD="$QEMU_CMD -nographic -serial mon:stdio -serial file:harvester-installer.log -nic none"

# Firmware Selection
if [[ "$BOOT_MODE" == "efi" ]]; then
    if [ "$USE_SEPARATE_VARS" = true ]; then
        QEMU_CMD="$QEMU_CMD -drive if=pflash,format=raw,readonly=on,file=${OVMF_CODE}"
        QEMU_CMD="$QEMU_CMD -drive if=pflash,format=raw,file=${TEMP_OVMF_VARS}"
    else
        QEMU_CMD="$QEMU_CMD -bios ${OVMF_CODE}"
    fi
else
    # BIOS Mode: No specific flags needed for default SeaBIOS
    echo "  Using default SeaBIOS."
fi

# Storage & Kernel
QEMU_CMD="$QEMU_CMD -drive file=${RAW_FILE},if=virtio,cache=writeback,discard=ignore,format=raw"
QEMU_CMD="$QEMU_CMD -cdrom ${ISO_FILE} -kernel ${KERNEL_FILE}"

# Using CDLABEL=COS_LIVE to ensure the ISO is found regardless of the boot device name
# NOTE: rd.live.squashimg=rootfs.squashfs directs it to look for the squashfs file inside the ISO
CMDLINE="cdroot root=live:CDLABEL=COS_LIVE rd.live.dir=/ rd.live.squashimg=rootfs.squashfs console=ttyS1 rd.cos.disable net.ifnames=1 harvester.install.mode=install harvester.install.device=/dev/vda harvester.install.automatic=true harvester.install.powerOff=true harvester.os.password=rancher harvester.scheme_version=1 harvester.install.persistentPartitionSize=150Gi harvester.install.skipchecks=true"

QEMU_CMD="$QEMU_CMD -append \"$CMDLINE\" -initrd ${INITRD_FILE} -boot once=d"

echo "  Running installation (Check harvester-installer.log for details)..."
eval $QEMU_CMD

# ============================================================================
# Step 5: Post-Processing (Compress or Convert)
# ============================================================================
log "Step 5: Processing output..."

if [ ! -f "$RAW_FILE" ]; then error "Raw image creation failed."; fi

if [[ "$OUTPUT_FORMAT" == "qcow2" ]]; then
    QCOW_FILE="${RAW_FILE%.raw}.qcow2"
    echo "  Converting RAW to QCOW2 ($QCOW_FILE)..."
    
    # -c: compress, -p: show progress, -f raw: input format, -O qcow2: output format
    if [ -f "$QCOW_FILE" ]; then rm -f "$QCOW_FILE"; fi
    qemu-img convert -c -p -f raw -O qcow2 "$RAW_FILE" "$QCOW_FILE"
    
    echo "  Removing intermediate raw file..."
    rm -f "$RAW_FILE"
    echo "  ✅ Done: $QCOW_FILE"

elif [[ "$OUTPUT_FORMAT" == "raw-zst" ]]; then
    COMPRESSED_FILE="${RAW_FILE}.zst"
    echo "  Compressing RAW image ($COMPRESSED_FILE)..."
    
    if [ -f "$COMPRESSED_FILE" ]; then rm -f "$COMPRESSED_FILE"; fi
    zstd -T4 --rm "$RAW_FILE"
    echo "  ✅ Done: $COMPRESSED_FILE"
fi

log "Build completed successfully!"
