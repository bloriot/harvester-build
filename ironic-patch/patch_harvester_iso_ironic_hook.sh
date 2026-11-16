#!/bin/bash
# ============================================================================
# Script: patch_harvester_iso_final.sh
# Description: Injects Ironic ConfigDrive support into Harvester ISO
# ============================================================================

set -e

INPUT_ISO="$1"
OUTPUT_ISO="${2:-harvester-ironic-patched.iso}"

if [ -z "$INPUT_ISO" ]; then
    echo "Usage: sudo $0 <input.iso> [output.iso]"
    exit 1
fi

# Never leave a partial ISO behind if the patch fails
on_exit() {
    if [ $? -ne 0 ]; then rm -f "$OUTPUT_ISO"; fi
}
trap on_exit EXIT

echo "🔧 Processing: $INPUT_ISO"

# 1. Extract rootfs.squashfs
echo "📦 Extracting rootfs.squashfs..."
if ! xorriso -osirrox on -indev "$INPUT_ISO" -extract /rootfs.squashfs original_rootfs.squashfs; then
    echo "❌ Error: xorriso failed to read $INPUT_ISO."
    exit 1
fi

if [ ! -f "original_rootfs.squashfs" ]; then
    echo "❌ Error: Failed to extract /rootfs.squashfs. Please check the ISO path."
    exit 1
fi

# 2. Unpack
echo "📂 Unpacking filesystem..."
[ -d "squashfs-root" ] && rm -rf squashfs-root
unsquashfs original_rootfs.squashfs > /dev/null

# 3. Inject Ironic Hook (The bridge between ConfigDrive and Harvester)
HOOK_FILE="squashfs-root/system/oem/15_ironic_configdrive.yaml"
echo "💉 Injecting Ironic Hook at: $HOOK_FILE"

cat <<EOF > "$HOOK_FILE"
name: "Ironic ConfigDrive Support"
stages:
  initramfs:
    - name: "Mount ConfigDrive and Inject Config"
      commands:
        - |
          mkdir -p /tmp/ironic_config
          # Search for Ironic label 'config-2'
          CONFIG_DEV=\$(blkid -L config-2)
          
          # Fallback: Scan devices if label lookup failed
          if [ -z "\$CONFIG_DEV" ]; then
             for dev in /dev/sd* /dev/vd* /dev/sr*; do
                if blkid \$dev | grep -q "config-2"; then
                   CONFIG_DEV=\$dev
                   break
                fi
             done
          fi

          if [ -n "\$CONFIG_DEV" ]; then
             echo "Ironic: Found config drive at \$CONFIG_DEV"
             mount \$CONFIG_DEV /tmp/ironic_config
             
             # Copy user_data to where Harvester expects it (/oem)
             if [ -f "/tmp/ironic_config/openstack/latest/user_data" ]; then
                cp /tmp/ironic_config/openstack/latest/user_data /oem/userdata.yaml
                chmod 600 /oem/userdata.yaml
             elif [ -f "/tmp/ironic_config/user_data" ]; then
                cp /tmp/ironic_config/user_data /oem/userdata.yaml
                chmod 600 /oem/userdata.yaml
             fi
             umount /tmp/ironic_config
          fi
EOF

# 4. Repack SquashFS
echo "🔒 Repacking SquashFS (XZ compression)..."
if [ -f "modified_rootfs.squashfs" ]; then rm "modified_rootfs.squashfs"; fi
mksquashfs squashfs-root modified_rootfs.squashfs -comp xz -noappend -processors 4 > /dev/null

# 5. Build New ISO
echo "💿 Building new ISO: $OUTPUT_ISO"
# We map the NEW local file (modified_rootfs.squashfs) to the OLD path in the ISO (/rootfs.squashfs)
xorriso -indev "$INPUT_ISO" \
        -outdev "$OUTPUT_ISO" \
        -boot_image any replay \
        -map modified_rootfs.squashfs /rootfs.squashfs \
        -padding 0 \
        -compliance no_emul_toc
if [ ! -s "$OUTPUT_ISO" ]; then
    echo "❌ Error: patched ISO was not created: $OUTPUT_ISO"
    exit 1
fi
echo "🎉 Success! Patched ISO created at: $OUTPUT_ISO"

# Cleanup
rm -rf squashfs-root original_rootfs.squashfs modified_rootfs.squashfs

# Run under sudo: give the patched ISO back to the invoking user
if [ -n "$SUDO_UID" ]; then
    chown "$SUDO_UID:$SUDO_GID" "$OUTPUT_ISO"
fi
