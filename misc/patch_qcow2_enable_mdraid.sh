#!/bin/bash
# ============================================================================
# Script: patch_qcow2_enable_mdraid.sh
# Description: Updates the third_party_kernel_args in grubenv to enable MDRAID
#              by adding rd.auto and rd.auto=1 kernel parameters.
# Usage: sudo ./patch_qcow2_enable_mdraid.sh <path-to-image.qcow2>
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
TARGET_FILE="$IMG_MOUNT/grubenv"
echo "📝 Patching $TARGET_FILE..."

if [ ! -f "$TARGET_FILE" ]; then
    echo "❌ Error: '$TARGET_FILE' not found in the OEM partition!"
    ls -l "$IMG_MOUNT"
    exit 1
fi

# Show before
echo "   🔍 Before patch (checking for 'third_party_kernel_args'):"
grep "third_party_kernel_args" "$TARGET_FILE" || echo "      (No 'third_party_kernel_args' line found)"

# Run sed to update the third_party_kernel_args line
# This changes: third_party_kernel_args=multipath=off
# To:          third_party_kernel_args=multipath=off rd.auto rd.auto=1
sudo sed -i 's/third_party_kernel_args=multipath=off/third_party_kernel_args=multipath=off rd.auto rd.auto=1/' "$TARGET_FILE"

# Show after
echo "   ✅ After patch (verifying update):"
grep "third_party_kernel_args" "$TARGET_FILE" || echo "      (Line not found after patch!)"

# 5. Unmount
echo "🔒 Unmounting image..."
sudo guestunmount "$IMG_MOUNT"

echo "🎉 Success! The grubenv has been updated with MDRAID kernel parameters."
