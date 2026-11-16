#!/bin/bash

# Repository configuration
REPO_OWNER="harvester"
REPO_NAME="harvester"
BASE_URL="https://releases.rancher.com/harvester"

# Function to get the latest version from GitHub API
get_latest_version() {
    # Send status message to stderr (>&2) so it isn't captured in the variable
    echo "🔍 Detecting latest version from GitHub..." >&2
    
    # Fetch latest release data
    # 1. curl fetches the JSON
    # 2. grep finds the "tag_name" line
    # 3. cut/tr cleans up quotes and commas to extract just v1.x.y
    LATEST_TAG=$(curl -s "https://api.github.com/repos/$REPO_OWNER/$REPO_NAME/releases/latest" \
                 | grep '"tag_name":' \
                 | cut -d '"' -f 4)
    
    if [ -z "$LATEST_TAG" ]; then
        echo "❌ Error: Could not detect latest version." >&2
        exit 1
    fi
    
    # Return ONLY the clean version string
    echo "$LATEST_TAG"
}

# 1. Determine which version to use
if [ -z "$1" ]; then
    VERSION=$(get_latest_version)
    echo "✅ Selected latest version: $VERSION"
else
    VERSION=$1
    echo "✅ Using specified version: $VERSION"
fi

# Clean up any potential whitespace/newlines in the version variable
VERSION=$(echo "$VERSION" | xargs)

# Create a directory for the downloads
DOWNLOAD_DIR="harvester-$VERSION-artifacts"
mkdir -p "$DOWNLOAD_DIR"
cd "$DOWNLOAD_DIR" || exit

echo "📂 Downloading files to ./$DOWNLOAD_DIR/"
echo "----------------------------------------"

# 2. Define the list of artifacts
FILES=(
    "harvester-$VERSION-amd64.iso"
    "harvester-$VERSION-vmlinuz-amd64"
    "harvester-$VERSION-initrd-amd64"
    "harvester-$VERSION-rootfs-amd64.squashfs"
    "harvester-$VERSION-amd64.sha512"
    "version.yaml"
)

# 3. Loop through files and download
FAILED=0
for FILE in "${FILES[@]}"; do
    FILE_URL="$BASE_URL/$VERSION/$FILE"
    
    echo "⬇️  Downloading $FILE..."
    
    # -f: Fail silently (HTTP 404), -L: Follow redirects, -O: Save as file
    if curl -f -L -O "$FILE_URL"; then
        echo "   [OK] Download complete"
    else
        echo "   [ERROR] Failed to download $FILE."
        echo "           URL was: $FILE_URL"
        rm -f "$FILE"
        FAILED=1
    fi
done

# 4. Verify the ISO against the published SHA512 checksum
ISO_FILE="harvester-$VERSION-amd64.iso"
SHA_FILE="harvester-$VERSION-amd64.sha512"
if [ "$FAILED" -eq 0 ]; then
    echo "🔐 Verifying $ISO_FILE checksum..."
    if grep " $ISO_FILE\$" "$SHA_FILE" | sha512sum -c -; then
        echo "   [OK] Checksum valid"
    else
        echo "   [ERROR] Checksum mismatch for $ISO_FILE"
        rm -f "$ISO_FILE"
        FAILED=1
    fi
fi

echo "----------------------------------------"
if [ "$FAILED" -ne 0 ]; then
    echo "❌ One or more artifacts failed."
    exit 1
fi
echo "🎉 All tasks finished."
