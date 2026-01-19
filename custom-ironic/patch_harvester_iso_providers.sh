#!/bin/bash
# ============================================================================
# Script: patch_harvester_iso_providers.sh
# Description: Patches 02_datasource.yaml inside Harvester ISO to enable extra providers
# ============================================================================

set -e

INPUT_ISO="$1"
OUTPUT_ISO="${2:-harvester-providers-patched.iso}"

if [ -z "$INPUT_ISO" ]; then
    echo "Usage: sudo $0 <input.iso> [output.iso]"
    exit 1
fi

# Check for required tools
for tool in xorriso unsquashfs mksquashfs; do
    if ! command -v "$tool" &> /dev/null; then
        echo "❌ Error: '$tool' is required."
        exit 1
    fi
done

echo "🔧 Processing: $INPUT_ISO"

# 1. Extract rootfs.squashfs
echo "📦 Extracting rootfs.squashfs from ISO..."
# We assume the file is at /rootfs.squashfs based on your previous checks
xorriso -osirrox on -indev "$INPUT_ISO" -extract /rootfs.squashfs original_rootfs.squashfs 2>/dev/null

if [ ! -f "original_rootfs.squashfs" ]; then
    echo "❌ Error: Failed to extract /rootfs.squashfs."
    exit 1
fi

# 2. Unpack
echo "📂 Unpacking filesystem..."
[ -d "squashfs-root" ] && rm -rf squashfs-root
unsquashfs original_rootfs.squashfs > /dev/null

# 3. Modify the configuration
CONFIG_PATH="squashfs-root/system/oem/02_datasource.yaml"

if [ ! -f "$CONFIG_PATH" ]; then
    echo "❌ Error: Could not find $CONFIG_PATH inside the extracted image."
    exit 1
fi

echo "📝 Found config file. Current 'providers' lines:"
grep "providers" "$CONFIG_PATH"

echo "🛠️  Applying patch to ALL providers lines..."

# EXPLANATION OF SED COMMAND:
# -E  : Extended regex support
# -i  : Edit file in-place
# ^   : Start of line
# ([[:space:]]*) : Capture group 1 -> Matches all leading spaces
# providers:.* : Matches the key and everything after it
# \1  : Puts back the captured spaces (Preserves indentation)
#
# TYPO FIX APPLIED: "configdrive" -> "config-drive"
sudo sed -E -i 's/^([[:space:]]*)providers:.*$/\1providers: ["nocloud", "config-drive", "openstack", "cdrom"]/' "$CONFIG_PATH"

# 4. Verify changes
echo "🔎 Verifying changes..."
# We look for the corrected string "config-drive"
MATCH_COUNT=$(grep -c "config-drive" "$CONFIG_PATH")

if [ "$MATCH_COUNT" -ge 2 ]; then
    echo "   ✅ Success: Updated $MATCH_COUNT locations."
    grep "providers" "$CONFIG_PATH"
else
    echo "   ❌ Error: Expected at least 2 updates, found $MATCH_COUNT."
    echo "   Dumping file content:"
    cat "$CONFIG_PATH"
    exit 1
fi

# 5. Repack SquashFS
echo "🔒 Repacking SquashFS (XZ compression)..."
if [ -f "modified_rootfs.squashfs" ]; then rm "modified_rootfs.squashfs"; fi
# Harvester requires XZ compression
mksquashfs squashfs-root modified_rootfs.squashfs -comp xz -noappend -processors 4 > /dev/null

# 6. Build New ISO
echo "💿 Building new ISO: $OUTPUT_ISO"
# Map the NEW local file to the OLD path in the ISO
xorriso -indev "$INPUT_ISO" \
        -outdev "$OUTPUT_ISO" \
        -boot_image any replay \
        -map modified_rootfs.squashfs /rootfs.squashfs \
        -padding 0 \
        -compliance no_emul_toc \
        2>/dev/null

echo "🎉 Success! Patched ISO created at: $OUTPUT_ISO"

# Cleanup
rm -rf squashfs-root original_rootfs.squashfs modified_rootfs.squashfs
