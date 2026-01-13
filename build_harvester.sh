#!/bin/bash

# ==============================================================================
# Harvester Build Automation Script
#
# This script automates the setup and build process for Harvester ISO and QCOW images.
# It supports SUSE Linux Enterprise Server (SLES) and Ubuntu.
#
# Reference: https://github.com/harvester/harvester/wiki/Build-OCI-and-ISO-images
# ==============================================================================

# ------------------------------------------------------------------------------
# Configuration Variables
# You can override these by passing them as environment variables.
# Example: HARVESTER_BRANCH="master" ./build_harvester.sh
# ------------------------------------------------------------------------------

# The Git branch or tag to build (default: v1.7.0)
: "${HARVESTER_BRANCH:=v1.7.0}"

# Set to "true" to build a raw QCOW image (requires KVM). 
# Default is "false" (builds ISO only).
: "${BUILD_QCOW:=false}"

# Directory where the repo will be cloned and artifacts built
WORK_DIR="$(pwd)/harvester-build"

# ------------------------------------------------------------------------------
# Helper Functions
# ------------------------------------------------------------------------------

log() {
    echo -e "\n\033[1;32m[INFO]\033[0m $1"
}

warn() {
    echo -e "\n\033[1;33m[WARN]\033[0m $1"
}

error() {
    echo -e "\n\033[1;31m[ERROR]\033[0m $1"
    exit 1
}

# Ensure the script is run with root privileges for package installation
check_root() {
    if [ "$EUID" -ne 0 ]; then
        error "This script requires root privileges to install Docker and build dependencies. Please run with sudo."
    fi
}

# ------------------------------------------------------------------------------
# OS-Specific Installation Logic
# ------------------------------------------------------------------------------

install_sles_deps() {
    log "Detected OS: SLES. Beginning dependency installation..."

    # CRITICAL WARNING: SLES requires 'kernel-default', not 'kernel-default-base'
    # for raw image building using KVM.
    if [ "$BUILD_QCOW" == "true" ]; then
        warn "Ensure you are running 'kernel-default' and not 'kernel-default-base' for KVM support."
    fi
    
    # 1. Install core build tools and Docker
    zypper in -y docker make git-core

    # 2. Enable and start the Docker service immediately
    systemctl enable --now docker

    # 3. Install KVM virtualization patterns if building a QCOW image
    # This is required for the raw image build process
    if [ "$BUILD_QCOW" == "true" ]; then
        log "QCOW build requested. Installing KVM server pattern..."
        zypper in -y -t pattern kvm_server
    fi
}

install_ubuntu_deps() {
    log "Detected OS: Ubuntu. Beginning dependency installation..."

    # 1. Install basic build tools
    apt-get update
    apt-get install -y git make ca-certificates curl

    # 2. Setup Official Docker Repository
    # This ensures we get the latest supported version of Docker
    install -m 0755 -d /etc/apt/keyrings
    curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
    chmod a+r /etc/apt/keyrings/docker.asc

    echo \
      "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
      $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
      tee /etc/apt/sources.list.d/docker.list > /dev/null

    apt-get update
    
    # 3. Install Docker Engine and plugins
    apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

    # 4. Configure Docker Daemon
    # Harvester build on Ubuntu specifically requires min-api-version 1.42
    log "Configuring /etc/docker/daemon.json for API compatibility..."
    tee /etc/docker/daemon.json <<EOF
{
  "min-api-version": "1.42"
}
EOF
    # Restart Docker to apply the daemon.json changes
    systemctl enable --now docker

    # 5. Install QEMU/KVM tools if building a QCOW image
    if [ "$BUILD_QCOW" == "true" ]; then
        log "QCOW build requested. Installing QEMU, OVMF, and utils..."
        apt-get install -y qemu-system-x86 ovmf qemu-utils
    fi
}

# ------------------------------------------------------------------------------
# Main Workflow
# ------------------------------------------------------------------------------

# A. OS Detection and Preparation
prepare_environment() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release
        case "$ID" in
            sles|opensuse*)
                install_sles_deps
                ;;
            ubuntu)
                install_ubuntu_deps
                ;;
            *)
                error "Unsupported OS detected: $ID. This script strictly supports SLES and Ubuntu."
                ;;
        esac
    else
        error "Cannot detect OS information (missing /etc/os-release)."
    fi
}

# B. Cloning and Building
perform_build() {
    log "Setting up workspace in: $WORK_DIR"
    mkdir -p "$WORK_DIR"
    cd "$WORK_DIR" || error "Could not enter directory $WORK_DIR"

    # Clean up previous runs to ensure a fresh build
    if [ -d "harvester-installer" ]; then
        log "Existing repository found. Removing to ensure clean state..."
        rm -rf harvester-installer
    fi

    # Clone the installer repo
    log "Cloning harvester-installer (Tag/Branch: $HARVESTER_BRANCH)..."
    git clone https://github.com/harvester/harvester-installer.git
    cd harvester-installer || error "Repo clone failed."
    
    # Checkout the specific version
    git checkout "$HARVESTER_BRANCH"

    # Execute the Make command
    log "Starting Build Process..."
    
    if [ "$BUILD_QCOW" == "true" ]; then
        log "Building Raw QCOW Image (KVM required)..."
        # Setting the variable explicitly for the make command
        export BUILD_QCOW=true
        make
    else
        log "Building Standard ISO Image..."
        make
    fi
    
    log "Build Process Complete!"
    log "Artifacts are located in: $WORK_DIR/harvester-installer/dist/artifacts"
}

# ------------------------------------------------------------------------------
# Execution Entry Point
# ------------------------------------------------------------------------------

check_root
prepare_environment
perform_build
