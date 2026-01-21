# Harvester Build & Config Toolkit

This toolkit provides scripts to build bootable Harvester raw disk image (or QCOW2) for direct VM deployment, patch Harvester ISO for OpenStack Ironic support, and generate compatible configuration drives.

## Scripts Overview

| Script | Purpose |
| --- | --- |
| **`download-harvester-artefacts.sh`** | Download the Harvester artefacts (ISO, vmlinuz, initrd, rootfs...). |
| **`build-raw-image.sh`** | Converts the Harvester ISO into a bootable raw disk image (or QCOW2) for direct VM deployment. |
| **`ironic-patch/patch_harvester_iso_ironic_hook.sh`** | Patches the Harvester ISO to support **Ironic ConfigDrive** (label `config-2`) by injecting a compatibility hook. |
| **`cloud-config/build-configdrive.sh`** | Generates an **Ironic-compatible** ISO (Label: `config-2`) containing your Harvester configuration. |
| **`cloud-config/build-nocloud.sh`** | Generates a **Standard NoCloud** ISO (Label: `CIDATA`) containing your Harvester configuration. |

---

## 1. Patch ISO for Ironic Support

Standard Harvester does not support the Ironic `config-2` label. Use this script to inject a hook into the ISO's `rootfs.squashfs` that bridges `config-2` to Harvester's cloud-init compatibility layer.

**Usage:**

```bash
sudo ./patch_harvester_iso_ironic_hook.sh <input_iso> [output_iso]
```

**Example:**

```bash
sudo ./patch_harvester_iso.sh harvester-v1.7.0.iso harvester-ironic.iso
```

---

## 2. Build Raw/QCOW2 Image

Use this if you need a pre-installed disk image instead of an installer ISO (e.g., for direct KVM/QEMU booting).

**Usage:**

```bash
sudo ./build-raw-image.sh [options]
```

**Options:**

* `-b, --boot-mode [efi|bios]`: Set boot firmware (default: `efi`).
* `-f, --format [raw-zst|qcow2]`: Output format (default: `raw-zst`).
* `-d, --dir [DIRECTORY]`: Directory containing artifacts (ISO, vmlinuz, initrd).

**Example:**

```bash
# Create a EFI-bootable QCOW2 image
sudo ./build-raw-image.sh -b efi -f qcow2 -d harvester-v1.7.0-artifacts
```
---

## 3. Generate Configuration Drives (for testing)

These scripts convert a simple YAML Harvester configuration file into a bootable ISO.

### A. For Patched ISOs (Ironic/ConfigDrive)

Use this if you applied the patch in step #2. It creates an ISO with label `config-2` and path `/openstack/latest/user_data`.

```bash
# Usage: ./build-configdrive.sh <config_file> [output_iso]
./build-configdrive.sh harvester-config.yaml config-drive.iso
```

### B. For Unmodified ISOs (NoCloud)

Use this for standard Harvester. It creates an ISO with label `CIDATA` and path `/user-data`.

```bash
# Usage: ./build-nocloud.sh <config_file> [output_iso]
./build-nocloud.sh harvester-config.yaml nocloud.iso
```
