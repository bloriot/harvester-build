#!/bin/bash
# ============================================================================
# Script: start-harvester-vnc-only.sh
# Description: Starts Harvester VM with VNC and custom keyboard layout
# ============================================================================

set -e

# 1. Configuration
# Change 'en-us' to your layout: 'fr' (French), 'de' (German), 'es' (Spanish), etc.
KEYBOARD="fr" 

SOURCE_IMG="${1:-../harvester-v1.7.0-artifacts/harvester-v1.7.0-amd64.qcow2}"
VM_NAME="harvester-ironic"
DISK_IMG="${VM_NAME}.qcow2"
CONFIG_ISO="config-drive.iso"
LOG_FILE="${VM_NAME}.log"
OVMF_BIOS="/usr/share/ovmf/OVMF.fd"

# 2. Check Prerequisites
if [ ! -f "$SOURCE_IMG" ]; then
    echo "❌ Error: Source image not found at: $SOURCE_IMG"
    exit 1
fi

if [ ! -f "$CONFIG_ISO" ]; then
    echo "❌ Error: Config ISO not found at: $CONFIG_ISO"
    exit 1
fi

# Locate OVMF
if [ ! -f "$OVMF_BIOS" ]; then
    if [ -f "/usr/share/qemu/ovmf-x86_64-code.bin" ]; then
        OVMF_BIOS="/usr/share/qemu/ovmf-x86_64-code.bin"
    elif [ -f "/usr/share/OVMF/OVMF.fd" ]; then
        OVMF_BIOS="/usr/share/OVMF/OVMF.fd"
    else
        echo "❌ Error: OVMF BIOS not found."
        exit 1
    fi
fi

# 3. Find a free VNC port
VNC_DISPLAY=0
while netstat -tuln | grep -q ":$((5900 + VNC_DISPLAY)) "; do
    ((VNC_DISPLAY++))
done
VNC_PORT=$((5900 + VNC_DISPLAY))

# 4. Prepare Disk
echo "💿 Creating disk overlay..."
rm -f "$DISK_IMG"
qemu-img create -f qcow2 -F qcow2 -b "$SOURCE_IMG" "$DISK_IMG" 250G > /dev/null

echo "--------------------------------------------------------"
echo "🚀 VM Started!"
echo "   VNC Address: 0.0.0.0:$VNC_PORT"
echo "   Keyboard:    $KEYBOARD"
echo "   Log File:    $LOG_FILE"
echo "--------------------------------------------------------"

# 5. Start QEMU
# Added -k "$KEYBOARD" to fix mapping issues
qemu-system-x86_64 \
  -name "$VM_NAME" \
  -enable-kvm \
  -m 4G \
  -smp 4 \
  -cpu host \
  -bios "$OVMF_BIOS" \
  -drive file="$DISK_IMG",format=qcow2,if=virtio \
  -drive file="$CONFIG_ISO",media=cdrom,readonly=on \
  -vnc "0.0.0.0:$VNC_DISPLAY" \
  -k "$KEYBOARD" \
  -vga std \
  -serial file:"$LOG_FILE" \
  -nic none
