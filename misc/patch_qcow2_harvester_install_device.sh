#!/bin/bash
# ============================================================================
# Script: patch_qcow2_harvester_install_device.sh
# Description: Updates the target install device in harvester.config
# Usage: sudo ./patch_qcow2_harvester_install_device.sh <image.qcow2> <target-device>
# Example: sudo ./patch_qcow2_harvester_install_device.sh harvester.qcow2 /dev/nvme0n1
# ============================================================================

set -e

# 1. Inputs
QCOW_IMAGE="$1"
TARGET_DEVICE="$2"

if [ -z "$QCOW_IMAGE" ] || [ -z "$TARGET_DEVICE" ]; then
    echo "Usage: sudo $0 <path-to-image.qcow2> <target-device>"
    echo "Example: sudo $0 build-staging-v1.7.1/harvester-v1.7.1-amd64.qcow2 /dev/sda"
    exit 1
fi

if [ ! -f "$QCOW_IMAGE" ]; then
    echo "❌ Error: QCOW2 file '$QCOW_IMAGE' not found."
    exit 1
fi

# 2. Setup
IMG_MOUNT="mnt_oem"
[ -d "$IMG_MOUNT" ] || mkdir -p "$IMG_MOUNT"

cleanup() {
    echo "🧹 Cleaning up..."
    if mountpoint -q "$IMG_MOUNT"; then
        sudo guestunmount "$IMG_MOUNT"
    fi
    [ -d "$IMG_MOUNT" ] && rmdir "$IMG_MOUNT"
}
trap cleanup EXIT

echo "🔧 Processing Image: $QCOW_IMAGE"
echo "🎯 Target Device:   $TARGET_DEVICE"

# 3. Mount the OEM Partition directly (/dev/sda2 based on our virt-filesystems check)
echo "📂 Mounting OEM partition (/dev/sda2)..."
sudo guestmount -a "$QCOW_IMAGE" -m /dev/sda2 --rw "$IMG_MOUNT"

# 4. Apply the Patch
TARGET_FILE="$IMG_MOUNT/harvester.config"
echo "📝 Patching $TARGET_FILE..."

if [ ! -f "$TARGET_FILE" ]; then
    echo "❌ Error: '$TARGET_FILE' not found in the OEM partition!"
    ls -l "$IMG_MOUNT"
    exit 1
fi

# Show before
echo "   🔍 Before patch:"
grep "device:" "$TARGET_FILE" || echo "      (No 'device:' line found yet)"

# Run sed to replace the device line while preserving indentation
sudo sed -i "s|^\([[:space:]]*\)device:.*|\1device: $TARGET_DEVICE|" "$TARGET_FILE"

# Show after
echo "   ✅ After patch:"
grep "device:" "$TARGET_FILE"

# 5. Unmount
echo "🔒 Unmounting image..."
sudo guestunmount "$IMG_MOUNT"

echo "🎉 Success! The image is ready to be deployed to $TARGET_DEVICE."
