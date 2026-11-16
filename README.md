# Harvester Image Builder

A toolkit for automating the creation of custom [Harvester](https://harvesterhci.io/) disk images.

This repository provides scripts and a Makefile to:
1.  **Download** official Harvester artifacts (ISO, Kernel, Initrd) and verify the ISO checksum.
2.  **Patch** the ISO to inject custom hooks (e.g., for OpenStack Ironic ConfigDrive support).
3.  **Build** bootable raw or QCOW2 disk images for direct VM or bare-metal deployment.
4.  **Post-Process** QCOW2 images to remove hardcoded installation devices, enabling dynamic target provisioning via userdata.

## 🚀 Quick Start

### 1. Prerequisites
The build needs KVM (`/dev/kvm`), and the Makefile runs the image steps with `sudo`.
Ubuntu's `/boot/vmlinuz*` is readable only by root, and libguestfs needs it, so `sudo` is required for the post-processing step.

* **SLES/openSUSE:**
    ```bash
    sudo zypper install curl xorriso squashfs qemu-img qemu-x86 ovmf guestfs-tools make zstd
    ```

* **Debian/Ubuntu:**
    ```bash
    sudo apt install curl xorriso squashfs-tools qemu-utils qemu-system-x86 ovmf libguestfs-tools make zstd
    ```
* **RHEL/CentOS/Fedora:**
    ```bash
    sudo dnf install curl xorriso squashfs-tools qemu-img qemu-system-x86 ovmf guestfs-tools make zstd
    ```

`zstd` is only needed for `FORMAT=raw-zst`.

### 2. Build a Standard Image
To download Harvester v1.9.1 and convert it to a bootable QCOW2 image (automatically stripping the hardcoded installation device):

```bash
make
```

### 3. Build an Ironic-Compatible Image

To inject the **Ironic ConfigDrive Hook** (required for OpenStack Ironic deployments using `config-2` labels) and generate the QCOW2 image:

```bash
make PATCH_IRONIC=true
```

---

## ⚙️ Configuration Variables

You can customize the build by passing variables to `make`.

| Variable | Default | Description |
| --- | --- | --- |
| `VERSION` | `v1.9.1` | The Harvester version to download and build. |
| `PATCH_IRONIC` | `false` | Set to `true` to inject the Ironic compatibility hook. |
| `FORMAT` | `qcow2` | Output disk format. Options: `qcow2`, `raw-zst` (produces `*.raw.zst`). |
| `ARCH` | `amd64` | Architecture to build for. |
| `BOOT_MODE` | `efi` | Boot firmware type (`efi` or `bios`). |
| `CPUS` | 2 cores x 2 threads | Number of vCPUs of the installer VM. |
| `MEMORY` | `8192` (`4096` if the host has less than 8.5 GB RAM) | Memory of the installer VM, in MB. |
| `DISK_SIZE` | `250G` | Virtual size of the target disk (qemu-img format, e.g. `200G`). |
| `LOG_DIR` | `logs` | Directory where each installation log is written. |

When `CPUS`, `MEMORY` or `DISK_SIZE` are not set, the defaults above are used.

**Examples:**

```bash
make FORMAT=raw-zst
make CPUS=4 MEMORY=6144 DISK_SIZE=200G
make VERSION=v1.9.1 BOOT_MODE=bios
```

Each build writes its installer log to `logs/install-<version>-<timestamp>.log`.

---

## 🛠️ Alternative: build from source

`build-harvester.sh` installs the build dependencies (Docker and tools, depending on the OS) and builds Harvester from the [harvester-installer](https://github.com/harvester/harvester-installer) repository. It is independent from the Makefile and needs root. The branch or tag is set with `HARVESTER_BRANCH` (default `v1.7.0`), and `BUILD_QCOW=true` also builds a QCOW2 image.

```bash
sudo HARVESTER_BRANCH=v1.9.1 BUILD_QCOW=true ./build-harvester.sh
```

If `/etc/docker/daemon.json` already exists, it is backed up before being replaced.

---

## 📂 Repository Structure

```text
.
├── Makefile                                     # Main orchestrator
├── download-harvester-artefacts.sh              # Download and checksum-verify ISO/Kernel/Initrd
├── build-raw-image.sh                           # Install Harvester into a raw/QCOW2 image using QEMU
├── build-harvester.sh                           # Alternative: build Harvester from source
├── ironic-patch/
│   ├── patch_harvester_iso_ironic_hook.sh       # Inject the Ironic/Yip hook into the ISO (used by make PATCH_IRONIC=true)
│   ├── patch_harvester_iso_providers.sh         # Enable extra cloud-init datasource providers in the ISO
│   ├── patch_qcow2_datasource.sh                # Patch 02_datasource.yaml inside a QCOW2 image
│   └── start-harvester-vm.sh                    # Start a Harvester QCOW2 with VNC and a keyboard layout
├── misc/
│   ├── patch_qcow2_remove_install_device.sh     # Remove the hardcoded device from harvester.config (used by make)
│   ├── patch_qcow2_enable_mdraid.sh             # Enable MDRAID kernel arguments in grubenv
│   └── auto-iso-install/
│       └── config-create.yaml                   # Example installation configuration
└── cloud-config/
    ├── nocloud-cidata/                          # Build a NoCloud (CIDATA) config ISO
    └── configdrive-ironic/                      # Build an Ironic ConfigDrive (config-2) ISO
```

### Script Details

* **`download-harvester-artefacts.sh`**: Auto-detects the latest version (or accepts a specific tag) and downloads all required files to `harvester-<version>-artifacts/`. The ISO is checked against the published SHA512 and the script exits with an error if a download or the checksum fails.
* **`build-raw-image.sh`**: Uses QEMU/KVM to boot the Harvester installer in a headless VM and installs the OS onto a virtual disk file. It supports exporting to `qcow2` or compressed raw (`raw-zst`). Options: `-c` (vCPUs), `-m` (memory), `-s` (disk size), `-l` (log directory).
* **`ironic-patch/patch_harvester_iso_ironic_hook.sh`**: Unpacks the Harvester ISO `rootfs.squashfs`, injects a custom hook into `/system/oem`, and repacks the ISO. This hook allows Harvester to read configuration from OpenStack Ironic `config-2` drives, which are normally ignored by the OS.
* **`misc/patch_qcow2_remove_install_device.sh`**: Uses `guestmount` to modify `harvester.config` within the partition labelled `COS_OEM` of the generated QCOW2 image. It removes the hardcoded `device:` parameter, allowing the installation target (e.g., `/dev/sda`, `/dev/nvme0n1`) to be provided dynamically via Cloud-Init `userdata`.
* **`ironic-patch/start-harvester-vm.sh`**: Starts a Harvester QCOW2 image in a VM with VNC access and a configurable keyboard layout (edit `KEYBOARD` in the script).

### Cloud-config helpers

Both scripts take an optional config file and output ISO name, and must be run from their own directory:

```bash
cd cloud-config/nocloud-cidata && ./build-nocloud.sh my-cluster.yaml nocloud-drive.iso
cd cloud-config/configdrive-ironic && ./build-configdrive.sh my-cluster.yaml config-drive.iso
```

* **NoCloud** (`CIDATA` label): the standard way to inject configuration without modifying the Harvester OS image.
* **ConfigDrive** (`config-2` label): for Ironic deployments. Harvester reads `/openstack/latest/user_data` when the Ironic hook or the ConfigDrive datasource is available.

---

## 🧹 Cleanup

To remove all generated images, staging areas, downloaded artifacts and installer logs:

```bash
make clean
```

If you only want to remove the generated images but **keep the downloaded ISOs** (to avoid re-downloading next time), delete the staging directory only:

```bash
rm -rf build-staging-*
```
