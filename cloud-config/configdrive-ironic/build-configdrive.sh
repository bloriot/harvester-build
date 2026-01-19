#!/bin/bash
# ============================================================================
# Script: build-configdrive.sh
# Description: Generates an Ironic ConfigDrive ISO from a config snippet
# Usage: ./build-configdrive.sh [input_file] [output_iso]
# ============================================================================

set -e

# --- Configuration ---
INPUT_FILE="${1:-harvester-config.yaml}"
OUTPUT_ISO="${2:-config-drive.iso}"
WORK_DIR="config-drive-build"
LABEL="config-2"  # STRICT REQUIREMENT for Ironic/Cloud-Init logic

# --- Pre-flight Checks ---
if [ ! -f "$INPUT_FILE" ]; then
    echo "❌ Error: Input file '$INPUT_FILE' not found."
    echo "   Please create a file named '$INPUT_FILE' with your YAML config."
    echo "   (Do not include the '#cloud-config' header, it will be added automatically)"
    exit 1
fi

# Detect available ISO builder
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
# ConfigDrive standard path: /openstack/latest/user_data
echo "📂 Creating ConfigDrive directory structure..."
[ -d "$WORK_DIR" ] && rm -rf "$WORK_DIR"
mkdir -p "$WORK_DIR/openstack/latest"

# --- 2. Process the Config File ---
TARGET_FILE="$WORK_DIR/openstack/latest/user_data"

echo "📝 Processing configuration..."
# Check if input already has the header to avoid duplication
if grep -q "^#cloud-config" "$INPUT_FILE"; then
    echo "   Header detected. Copying as-is."
    cp "$INPUT_FILE" "$TARGET_FILE"
else
    echo "   Header missing. Prepending '#cloud-config'."
    echo "#cloud-config" > "$TARGET_FILE"
    cat "$INPUT_FILE" >> "$TARGET_FILE"
fi

# Ensure correct permissions (standard practice for config drives)
chmod 644 "$TARGET_FILE"

# --- 3. Build the ISO ---
echo "💿 Building ISO image: $OUTPUT_ISO"
# -R: Rock Ridge (Linux permissions support)
# -V: Volume ID (Critical: MUST be 'config-2')
# -quiet: Suppress standard output
"$MKISOFS" -R -V "$LABEL" -o "$OUTPUT_ISO" "$WORK_DIR" 2>/dev/null

if [ -f "$OUTPUT_ISO" ]; then
    echo "--------------------------------------------------------"
    echo "🎉 Success! ConfigDrive ISO created: $OUTPUT_ISO"
    echo "   Volume Label: $LABEL"
    echo "   Content Path: /openstack/latest/user_data"
    echo "--------------------------------------------------------"
else
    echo "❌ Error: ISO creation failed."
    exit 1
fi

# --- Cleanup ---
rm -rf "$WORK_DIR"
