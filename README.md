# Harvester Image Builder

A toolkit for automating the creation of custom [Harvester](https://harvesterhci.io/) disk images.

This repository provides scripts and a Makefile to:
1.  **Download** official Harvester artifacts (ISO, Kernel, Initrd).
2.  **Patch** the ISO to inject custom hooks (e.g., for OpenStack Ironic ConfigDrive support).
3.  **Build** bootable raw or QCOW2 disk images for direct VM or bare-metal deployment.
4.  **Post-Process** QCOW2 images to remove hardcoded installation devices, enabling dynamic target provisioning via userdata.

## 🚀 Quick Start

### 1. Prerequisites
Ensure you have the required tools installed, including `guestmount` for image post-processing.

* **SLES/openSUSE:**
    ```bash
    sudo zypper install curl xorriso squashfs qemu-img qemu-x86 ovmf guestfs-tools make
    ```

* **Debian/Ubuntu:**
    ```bash
    sudo apt install curl xorriso squashfs-tools qemu-utils qemu-system-x86 ovmf libguestfs-tools make
    ```
* **RHEL/CentOS/Fedora:**
    ```bash
    sudo dnf install curl xorriso squashfs-tools qemu-img qemu-system-x86 ovmf guestfs-tools make
    ```

### 2. Build a Standard Image
To download the latest Harvester ISO and convert it to a bootable QCOW2 image (automatically stripping the hardcoded installation device):

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
| `VERSION` | `v1.7.1` | The Harvester version to download and build. |
| `PATCH_IRONIC` | `false` | Set to `true` to inject the Ironic compatibility hook. |
| `FORMAT` | `qcow2` | Output disk format. Options: `qcow2`, `raw-zst`. |
| `ARCH` | `amd64` | Architecture to build for. |
| `BOOT_MODE` | `efi` | Boot firmware type (`efi` or `bios`). |

**Example:** Build a specific version for EFI boot:

```bash
make VERSION=v1.7.1 BOOT_MODE=efi
```

---
## 📂 Repository Structure

```text
.
├── Makefile                                     # Main orchestrator
├── download-harvester-artefacts.sh              # Script to fetch ISO/Kernel/Initrd
├── build-raw-image.sh                           # Script to install Harvester into a QCOW2 image
├── ironic-patch/
│   └── patch_harvester_iso_ironic_hook.sh       # Script to inject the Ironic/Yip hook
└── misc/
    └── patch_qcow2_remove_install_device.sh     # Script to remove hardcoded device from Harvester config
```

### Script Details

* **`download-harvester-artefacts.sh`**: Auto-detects the latest version (or accepts a specific tag) and downloads all required files to a local directory.
* **`build-raw-image.sh`**: Uses QEMU/KVM to boot the Harvester installer in a headless VM and installs the OS onto a virtual disk file. It supports exporting to `qcow2` or compressed raw (`raw-zst`).
* **`ironic-patch/patch_harvester_iso_ironic_hook.sh`**: Unpacks the Harvester ISO `rootfs.squashfs`, injects a custom hook into `/system/oem`, and repacks the ISO. This hook allows Harvester to read configuration from OpenStack Ironic `config-2` drives, which are normally ignored by the OS.
* **`misc/patch_qcow2_remove_install_device.sh`**: Uses `guestmount` to modify `harvester.config` within the `COS_OEM` partition of the generated QCOW2 image. It safely removes the hardcoded `device:` parameter, allowing the installation target (e.g., `/dev/sda`, `/dev/nvme0n1`) to be provided dynamically via Cloud-Init `userdata`.

---

## 🧹 Cleanup

To remove all generated images, staging areas, and downloaded artifacts:

```bash
make clean
```

If you only want to remove the generated images but **keep the downloaded ISOs** (to avoid re-downloading next time), simply delete the `build-staging-*` directory manually or modify the `clean` target in the Makefile.

```bash
rm -rf build-staging-*
```
