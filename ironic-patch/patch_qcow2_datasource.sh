#!/bin/bash
# ============================================================================
# Script: patch_qcow2_datasource.sh
# Description: Directly patches 02_datasource.yaml inside a Harvester QCOW2 image
# Usage: sudo ./patch_qcow2_datasource.sh <path-to-image.qcow2>
# ============================================================================

set -e

# 1. Input Argument Check
QCOW_IMAGE="$1"

if [ -z "$QCOW_IMAGE" ]; then
    echo "Usage: sudo $0 <path-to-image.qcow2>"
    exit 1
fi

if [ ! -f "$QCOW_IMAGE" ]; then
    echo "❌ Error: QCOW2 file '$QCOW_IMAGE' not found."
    exit 1
fi

# 2. Dependency Check
if ! command -v guestmount &> /dev/null; then
    echo "❌ Error: 'guestmount' tool not found."
    echo "   Please install: sudo apt-get install libguestfs-tools"
    exit 1
fi

# 3. Setup Directories & Cleanup Trap
QCOW_MOUNT="/mnt/harvester-state"
IMG_MOUNT="mnt_edit"

# Ensure clean start
[ -d "$QCOW_MOUNT" ] || sudo mkdir -p "$QCOW_MOUNT"
[ -d "$IMG_MOUNT" ] || mkdir -p "$IMG_MOUNT"

# Trap to ensure we unmount everything if the script crashes or exits
cleanup() {
    echo "🧹 Cleaning up..."
    if mountpoint -q "$IMG_MOUNT"; then
        sudo umount "$IMG_MOUNT"
    fi
    
    if mountpoint -q "$QCOW_MOUNT"; then
        sudo guestunmount "$QCOW_MOUNT"
    fi
    
    # Remove temporary active.img if it exists
    if [ -f "active.img" ]; then
        rm "active.img"
    fi
    
    # Remove mount directories (optional, keeps system clean)
    [ -d "$IMG_MOUNT" ] && rmdir "$IMG_MOUNT"
    [ -d "$QCOW_MOUNT" ] && sudo rmdir "$QCOW_MOUNT"
}
trap cleanup EXIT

echo "🔧 Processing Image: $QCOW_IMAGE"

# 4. Mount the QCOW2 Image (COS_STATE partition)
echo "📂 Mounting QCOW2 partition (COS_STATE)..."
sudo guestmount -a "$QCOW_IMAGE" -m /dev/disk/by-label/COS_STATE --rw "$QCOW_MOUNT"

# 5. Extract active.img
echo "⬇️  Copying active.img to local workspace..."
if [ ! -f "$QCOW_MOUNT/cOS/active.img" ]; then
    echo "❌ Error: Could not find 'cOS/active.img' inside the QCOW2."
    exit 1
fi
sudo cp "$QCOW_MOUNT/cOS/active.img" .

# 6. Mount active.img (Ext2 Loop)
echo "📂 Mounting active.img..."
sudo mount -t ext2 -o loop,rw active.img "$IMG_MOUNT"

# 7. Apply the Patch
TARGET_FILE="$IMG_MOUNT/system/oem/02_datasource.yaml"
echo "📝 Patching $TARGET_FILE..."

if [ ! -f "$TARGET_FILE" ]; then
    echo "❌ Error: Target file '$TARGET_FILE' not found inside active.img."
    exit 1
fi

# Write new file content
sudo bash -c "cat > $TARGET_FILE" <<EOF
stages:
  rootfs.before:
    - name: "Pull data from provider"
      datasource:
        providers: ["config-drive"]
        path: "/oem"
  initramfs:
  - name: "Pull data from provider"
    datasource:
      providers: ["config-drive"]
      path: "/oem"
EOF

# 8. Unmount active.img (Writes changes to the file)
echo "🔒 Unmounting active.img..."
sudo umount "$IMG_MOUNT"

# 9. Copy modified image back to QCOW2
echo "⬆️  Copying patched active.img back to QCOW2..."
sudo cp active.img "$QCOW_MOUNT/cOS/active.img"

# 10. Unmount QCOW2
echo "🔒 Unmounting QCOW2..."
sudo guestunmount "$QCOW_MOUNT"

echo "🎉 Success! The QCOW2 image has been patched."
