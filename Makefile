# ============================================================================
# Harvester Image Builder
# ============================================================================

# --- Configuration ---
# Set to 'true' to inject the Ironic hook.
# Default is 'false' (Standard Harvester build).
PATCH_IRONIC ?= false

VERSION    ?= v1.7.1
ARCH       ?= amd64
BOOT_MODE  ?= efi
FORMAT     ?= qcow2

# --- Paths & Directories ---
DOWNLOAD_DIR := harvester-$(VERSION)-artifacts
STAGING_DIR  := build-staging-$(VERSION)

# --- Filenames ---
ISO_NAME     := harvester-$(VERSION)-$(ARCH).iso
KERNEL_NAME  := harvester-$(VERSION)-vmlinuz-$(ARCH)
INITRD_NAME  := harvester-$(VERSION)-initrd-$(ARCH)
FINAL_IMAGE  := $(STAGING_DIR)/harvester-$(VERSION)-$(ARCH).$(FORMAT)

# --- Scripts ---
SCRIPT_DOWNLOAD     := ./download-harvester-artefacts.sh
SCRIPT_PATCH        := ./ironic-patch/patch_harvester_iso_ironic_hook.sh
SCRIPT_BUILD        := ./build-raw-image.sh
SCRIPT_PATCH_DEVICE := ./misc/patch_qcow2_remove_install_device.sh

# --- Prerequisites ---
# Added guestmount to ensure libguestfs-tools is installed
REQUIRED_TOOLS := curl xorriso unsquashfs mksquashfs qemu-img qemu-system-x86_64 guestmount

# ============================================================================
# Targets
# ============================================================================

.PHONY: all help clean download prepare-iso image check-deps

all: check-deps image
	@echo "✅ Build Complete. Final image available at: $(FINAL_IMAGE)"

# 0. Check Prerequisites
check-deps:
	@echo "🔍 Checking system prerequisites..."
	@$(foreach tool,$(REQUIRED_TOOLS),\
		if ! command -v $(tool) > /dev/null; then \
			echo "❌ Error: '$(tool)' is missing."; \
			exit 1; \
		fi;)
	@echo "✅ All required tools are installed."

# 1. Download Artifacts
download: check-deps $(DOWNLOAD_DIR)/$(ISO_NAME)

$(DOWNLOAD_DIR)/$(ISO_NAME):
	@echo "📥 Step 1: Downloading Harvester Artifacts ($(VERSION))..."
	bash $(SCRIPT_DOWNLOAD) $(VERSION)

# 2. Prepare Staging ISO (Patched OR Original)
# This target creates the ISO used for building the image.
prepare-iso: check-deps $(STAGING_DIR)/$(ISO_NAME)

$(STAGING_DIR)/$(ISO_NAME): $(DOWNLOAD_DIR)/$(ISO_NAME)
	@echo "🔧 Step 2: Preparing Staging Area..."
	@mkdir -p $(STAGING_DIR)
	
	@echo "   -> Copying Kernel and Initrd to staging..."
	@cp $(DOWNLOAD_DIR)/$(KERNEL_NAME) $(STAGING_DIR)/
	@cp $(DOWNLOAD_DIR)/$(INITRD_NAME) $(STAGING_DIR)/
	
	@if [ "$(PATCH_IRONIC)" = "true" ]; then \
		echo "   -> 💉 Injecting Ironic Hook (PATCH_IRONIC=true)..."; \
		sudo bash $(SCRIPT_PATCH) $(DOWNLOAD_DIR)/$(ISO_NAME) $(STAGING_DIR)/$(ISO_NAME); \
	else \
		echo "   -> ⚠️  Using Standard ISO (PATCH_IRONIC=false)..."; \
		cp $(DOWNLOAD_DIR)/$(ISO_NAME) $(STAGING_DIR)/$(ISO_NAME); \
	fi

# 3. Build QCOW2 Image & Patch Device
image: check-deps $(FINAL_IMAGE)

$(FINAL_IMAGE): $(STAGING_DIR)/$(ISO_NAME)
	@echo "🏗️  Step 3: Building $(FORMAT) Image..."
	sudo bash $(SCRIPT_BUILD) \
		-v $(VERSION) \
		-d $(STAGING_DIR) \
		-f $(FORMAT) \
		-b $(BOOT_MODE)
	@echo "🔧 Step 4: Post-processing image..."
	@if [ "$(FORMAT)" = "qcow2" ]; then \
		echo "   -> Removing hardcoded install device from Harvester config..."; \
		sudo bash $(SCRIPT_PATCH_DEVICE) $(FINAL_IMAGE); \
	else \
		echo "   -> ⚠️ Skipping device patch (only supported for qcow2 format)."; \
	fi

# Utilities
clean:
	@echo "🧹 Cleaning up staging and artifacts..."
	rm -rf $(STAGING_DIR)
	rm -rf $(DOWNLOAD_DIR)
	rm -rf harvester-installer.log

help:
	@echo "Usage: make [target] [variables]"
	@echo ""
	@echo "Variables:"
	@echo "  PATCH_IRONIC  Inject Ironic hook? true/false (default: false)"
	@echo "  VERSION       Harvester version (default: v1.7.1)"
	@echo "  FORMAT        Output format: qcow2 or raw-zst (default: qcow2)"
	@echo ""
	@echo "Examples:"
	@echo "  make                          # Build STANDARD Harvester QCOW2"
	@echo "  make PATCH_IRONIC=true        # Build PATCHED Harvester QCOW2"
	@echo "  make clean                    # Remove artifacts"
