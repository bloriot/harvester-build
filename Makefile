# ============================================================================
# Harvester Ironic Image Builder
# ============================================================================

# --- Configuration ---
# You can override these from the command line: make VERSION=v1.7.0
VERSION    ?= v1.7.0
ARCH       ?= amd64
BOOT_MODE  ?= efi
FORMAT     ?= qcow2

# --- Paths & Directories ---
# The directory created by the download script
DOWNLOAD_DIR := harvester-$(VERSION)-artifacts

# A temporary staging directory where we assemble the patched ISO + Kernel
STAGING_DIR  := build-staging-$(VERSION)

# --- Filenames (Based on Harvester Naming Conventions) ---
ISO_NAME     := harvester-$(VERSION)-$(ARCH).iso
KERNEL_NAME  := harvester-$(VERSION)-vmlinuz-$(ARCH)
INITRD_NAME  := harvester-$(VERSION)-initrd-$(ARCH)

# The final output file created by build-raw-image.sh
FINAL_IMAGE  := $(STAGING_DIR)/harvester-$(VERSION)-$(ARCH).$(FORMAT)

# --- Scripts ---
SCRIPT_DOWNLOAD := ./download-harvester-artefacts.sh
SCRIPT_PATCH    := ./ironic-patch/patch_harvester_iso_ironic_hook.sh
SCRIPT_BUILD    := ./build-raw-image.sh

# ============================================================================
# Targets
# ============================================================================

.PHONY: all help clean download patch image

# Default target: Build the final image
all: image
	@echo "✅ Build Complete. Final image available at: $(FINAL_IMAGE)"

# 1. Download Artifacts
# Checks if the ISO exists to avoid re-downloading
download: $(DOWNLOAD_DIR)/$(ISO_NAME)

$(DOWNLOAD_DIR)/$(ISO_NAME):
	@echo "📥 Step 1: Downloading Harvester Artifacts ($(VERSION))..."
	bash $(SCRIPT_DOWNLOAD) $(VERSION)

# 2. Patch ISO & Prepare Staging Area
# We rely on the download step first.
# We patch the ISO and save it to STAGING_DIR with the original name.
# We also copy the kernel and initrd so the build script finds everything in one place.
patch: $(STAGING_DIR)/$(ISO_NAME)

$(STAGING_DIR)/$(ISO_NAME): $(DOWNLOAD_DIR)/$(ISO_NAME)
	@echo "🔧 Step 2: Preparing Staging Area & Patching ISO..."
	@mkdir -p $(STAGING_DIR)
	
	@# Copy Kernel and Initrd (Required by build-raw-image.sh)
	@echo "   -> Copying Kernel and Initrd to staging..."
	@cp $(DOWNLOAD_DIR)/$(KERNEL_NAME) $(STAGING_DIR)/
	@cp $(DOWNLOAD_DIR)/$(INITRD_NAME) $(STAGING_DIR)/
	
	@# Run the Patch Script
	@# Input: Original ISO | Output: Staging ISO (named same as original)
	@echo "   -> Injecting Ironic Hook..."
	@# We use sudo here because xorriso/mounting often requires it, 
	@# and the script usage suggests it.
	sudo bash $(SCRIPT_PATCH) \
		$(DOWNLOAD_DIR)/$(ISO_NAME) \
		$(STAGING_DIR)/$(ISO_NAME)

# 3. Build QCOW2 Image
# Points the build script to the STAGING_DIR where the Patched ISO lives.
image: $(FINAL_IMAGE)

$(FINAL_IMAGE): $(STAGING_DIR)/$(ISO_NAME)
	@echo "🏗️  Step 3: Building QCOW2 Image (This may take a while)..."
	@# -v: Version
	@# -d: Directory (We point to staging so it uses the PATCHED iso)
	@# -f: Format
	@# -b: Boot Mode
	sudo bash $(SCRIPT_BUILD) \
		-v $(VERSION) \
		-d $(STAGING_DIR) \
		-f $(FORMAT) \
		-b $(BOOT_MODE)

# Utilities
clean:
	@echo "🧹 Cleaning up staging and artifacts..."
	rm -rf $(STAGING_DIR)
	rm -rf $(DOWNLOAD_DIR)

help:
	@echo "Usage: make [target] [variables]"
	@echo ""
	@echo "Variables:"
	@echo "  VERSION    Harvester version to build (default: v1.7.0)"
	@echo "  FORMAT     Output format: qcow2 or raw-zst (default: qcow2)"
	@echo ""
	@echo "Targets:"
	@echo "  make       Download -> Patch -> Build QCOW2"
	@echo "  make download  Only download artifacts"
	@echo "  make patch     Download and Patch ISO (creates staging dir)"
	@echo "  make clean     Remove all artifacts and build files"
