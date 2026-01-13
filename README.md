# Harvester Build Automation

This script automates the process of building Harvester ISO and image. It handles dependency installation (Docker, KVM, Make) and the build process for both **SLES** and **Ubuntu** environments.

## Prerequisites

* **Root Privileges:** The script must be run with `sudo` to install packages and configure Docker.
* **Operating System:**
    * SUSE Linux Enterprise Server (SLES)
    * Ubuntu
* **Internet Connection:** To download Docker packages and clone the GitHub repository.

## Usage

### 1. Basic Usage (Build ISO)
By default, the script builds the Harvester ISO for version `v1.7.0`.

```bash
sudo ./build_harvester.sh
```

### 2. Build Raw QCOW Image
To build a raw image (useful for virtualization testing), set the BUILD_QCOW flag.
Note: This installs additional KVM/QEMU dependencies.

```bash
sudo BUILD_QCOW="true" ./build_harvester.sh
```

### 3. Building a Specific Version
By default, the script builds v1.7.0. To build a different tag or branch (e.g., master), set HARVESTER_BRANCH.

```bash
sudo HARVESTER_BRANCH="master" ./build_harvester.sh
```
