#!/bin/bash

# 1. Determine the input file
if [ -n "$1" ]; then
    SQUASH_FILE="$1"
else
    SQUASH_FILE=$(ls *.squashfs 2>/dev/null | head -n 1)
fi

if [ -z "$SQUASH_FILE" ]; then
    echo "❌ Error: No .squashfs file specified or found."
    exit 1
fi

echo "🔧 Processing: $SQUASH_FILE"

# 2. Cleanup previous work directory
if [ -d "squashfs-root" ]; then
    sudo rm -rf squashfs-root
fi

# 3. Unpack
echo "📦 Unpacking filesystem..."
sudo unsquashfs "$SQUASH_FILE" > /dev/null

# 4. Modify the configuration
CONFIG_PATH="squashfs-root/system/oem/02_datasource.yaml"

if [ ! -f "$CONFIG_PATH" ]; then
    echo "❌ Error: Could not find $CONFIG_PATH"
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
# \1  : Puts back the captured spaces from group 1 (Preserves indentation)
sudo sed -E -i 's/^([[:space:]]*)providers:.*$/\1providers: ["nocloud", "config-drive", "openstack", "cdrom"]/' "$CONFIG_PATH"

# 5. Verify changes
echo "🔎 Verifying changes..."
# We expect multiple matches now containing 'config-drive'
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

# 6. Repack
BACKUP_FILE="${SQUASH_FILE}.bak"
if [ -f "$BACKUP_FILE" ]; then
    echo "   (Overwriting existing backup...)"
fi
mv "$SQUASH_FILE" "$BACKUP_FILE"

echo "🔒 Repacking into SquashFS (XZ compression)..."
sudo mksquashfs squashfs-root "$SQUASH_FILE" -comp xz -noappend > /dev/null

# 7. Cleanup
sudo rm -rf squashfs-root

echo "🎉 Done! Modified file: $SQUASH_FILE"
