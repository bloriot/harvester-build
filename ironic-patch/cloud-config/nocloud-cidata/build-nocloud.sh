#!/bin/bash
# ============================================================================
# Script: build-nocloud.sh
# Description: Generates a NoCloud (CIDATA) ISO from a config snippet
# Usage: ./build-nocloud.sh [input_file] [output_iso]
# ============================================================================

set -e

# --- Configuration ---
INPUT_FILE="${1:-harvester-config}"
OUTPUT_ISO="${2:-nocloud-drive.iso}"
WORK_DIR="nocloud-build"
LABEL="CIDATA"  # STRICT REQUIREMENT for NoCloud datasource

# --- Pre-flight Checks ---
if [ ! -f "$INPUT_FILE" ]; then
    echo "❌ Error: Input file '$INPUT_FILE' not found."
    echo "   Please create a file named '$INPUT_FILE' with your YAML config."
    exit 1
fi

if command -v mkisofs &> /dev/null; then
    MKISOFS="mkisofs"
elif command -v genisoimage &> /dev/null; then
    MKISOFS="genisoimage"
else
    echo "❌ Error: 'mkisofs' or 'genisoimage' is required."
    exit 1
fi

echo "🔧 Processing Input: $INPUT_FILE"

# --- 1. Prepare Directory Structure ---
# NoCloud expects files at the root of the drive
echo "📂 Creating NoCloud directory structure..."
[ -d "$WORK_DIR" ] && rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR"

# --- 2. Process user-data ---
TARGET_USER_DATA="$WORK_DIR/user-data"

echo "📝 Processing user-data..."
if grep -q "^#cloud-config" "$INPUT_FILE"; then
    echo "   Header detected. Copying as-is."
    cp "$INPUT_FILE" "$TARGET_USER_DATA"
else
    echo "   Header missing. Prepending '#cloud-config'."
    echo "#cloud-config" > "$TARGET_USER_DATA"
    cat "$INPUT_FILE" >> "$TARGET_USER_DATA"
fi

# --- 3. Generate meta-data (Required) ---
# NoCloud often refuses to run if this file is missing, even if empty.
# We provide a minimal valid configuration.
TARGET_META_DATA="$WORK_DIR/meta-data"
echo "📝 Generating meta-data..."
cat <<EOF > "$TARGET_META_DATA"
instance-id: harvester-install-$(date +%s)
local-hostname: harvester-node
EOF

# Ensure permissions
chmod 644 "$TARGET_USER_DATA" "$TARGET_META_DATA"

# --- 4. Build the ISO ---
echo "💿 Building ISO image: $OUTPUT_ISO"
# -J: Joliet (Windows compatibility, often helps with long filenames)
# -R: Rock Ridge (Linux permissions)
# -V: Volume ID (Must be 'CIDATA')
"$MKISOFS" -J -R -V "$LABEL" -o "$OUTPUT_ISO" "$WORK_DIR" 2>/dev/null

if [ -f "$OUTPUT_ISO" ]; then
    echo "--------------------------------------------------------"
    echo "🎉 Success! NoCloud ISO created: $OUTPUT_ISO"
    echo "   Volume Label: $LABEL"
    echo "   Contents:     /user-data, /meta-data"
    echo "--------------------------------------------------------"
else
    echo "❌ Error: ISO creation failed."
    exit 1
fi

# --- Cleanup ---
rm -rf "$WORK_DIR"
