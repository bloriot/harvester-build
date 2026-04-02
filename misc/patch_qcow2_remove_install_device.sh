#!/bin/bash
# ============================================================================
# Script: patch_qcow2_remove_install_device.sh
# Description: Removes the hardcoded 'device:' line from harvester.config
#              so the installation falls back to the userdata provided by Cloud-Init.
# Usage: sudo ./patch_qcow2_remove_install_device.sh <path-to-image.qcow2>
# ============================================================================

set -e

# 1. Inputs
QCOW_IMAGE="$1"

if [ -z "$QCOW_IMAGE" ]; then
    echo "Usage: sudo $0 <path-to-image.qcow2>"
    echo "Example: sudo $0 build-staging-v1.7.1/harvester-v1.7.1-amd64.qcow2"
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

# 3. Mount the OEM Partition directly (/dev/sda2)
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
echo "   🔍 Before patch (checking for 'device:'):"
grep "device:" "$TARGET_FILE" || echo "      (No 'device:' line found)"

# Run sed to delete the device line
# /^[[:space:]]*device:/ matches 'device:' with any leading spaces
# d deletes the matched line
sudo sed -i '/^[[:space:]]*device:/d' "$TARGET_FILE"

# Show after
echo "   ✅ After patch (verifying removal):"
grep "device:" "$TARGET_FILE" || echo "      (Line successfully removed!)"

# 5. Unmount
echo "🔒 Unmounting image..."
sudo guestunmount "$IMG_MOUNT"

echo "🎉 Success! The hardcoded device has been removed from the image."
