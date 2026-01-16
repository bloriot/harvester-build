# Harvester deployment configuration

## Apply configuration via cloud-init

The raw image you built with `BUILD_QCOW="true"` is a **pre-installed Harvester OS image**. It contains the binaries and filesystem but lacks the configuration (network, cluster role, token, VIP) required to form a cluster.

To configure the installation upon booting this image, you must inject the configuration using **Cloud-Init**.

Here is the process to configure Harvester via Cloud-Init using an ISO file.

### 1. Create the Configuration File (`user-data`)

Create a file named `user-data` (no extension). This file must start with `#cloud-config` and uses the Harvester configuration schema, not standard Linux cloud-init keys.

**Example `user-data` for creating a new cluster:**

```yaml
#cloud-config
scheme_version: 1

# The secret token shared by all nodes in the cluster.
# Required for other nodes to join this cluster later.
token: "my-secret-token"

os:
  # The unique hostname for this specific node.
  hostname: harvester-node-01

  # The password for the default 'rancher' user (used for console/SSH access).
  password: "password123"

  # Network Time Protocol servers to ensure cluster synchronization.
  ntp_servers:
    - 0.suse.pool.ntp.org
    - 1.suse.pool.ntp.org

  # Public SSH keys allowed to log in as the 'rancher' user.
  ssh_authorized_keys:
    - ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQCn2ICnMAAN30uiSXhmYmHTx0JNZzeGpPnw4+5glkp088orRlWsMg5g7rWFMG94KD6YcJvhoFKf7v+bYM5ZU+H7p5C7JwafRuxwRR0Z++jUNMkfLwDEbrbNZp3y9sTLDJDBEICE0mzv2pvZIQU6M/r6va1j1FST8R5y2ZcpmoL9Kz4heTJ7wvDzhrpqOd4Ac3VJmyUadJ9TS/B+pdZksbamuss1G6eb7k+7lKprcrHO4+G1SR2R9zHGYoBcJUhS09V5vBdDra/Q1GAeRpPy0vkZJh0IkTmyKJ4wdKjFpxjonEuQMZCTOonLn74xzepTAc7TeFcJ9S85c/gw7HOBA19r rsa-key-zbox-bloriot

install:
  # 'create' initializes a new cluster. Use 'join' for subsequent nodes.
  mode: create

  # Run installer  without asking for interactive confirmation.
  automatic: true

  # Defines how this node connects to the network.
  management_interface:
    # The list of physical interfaces to use for the management network.
    interfaces:
      - name: enp1s0

    # Ensure this interface is used as the default gateway for the OS.
    default_route: true

    # Network configuration method: 'static' or 'dhcp'.
    method: static
    
    # Static IP details for THIS specific node.
    ip: 10.6.110.101
    subnet_mask: 255.255.255.0
    gateway: 10.6.110.1

    # Link Aggregation settings. Harvester creates a bond interface even for a single NIC.
    bond_options:
      mode: balance-tlb
      miimon: 100

  # The Virtual IP (Floating IP) for accessing the Harvester Dashboard/API.
  # This IP floats between control plane nodes if one goes down.
  vip: 10.6.110.100
  vip_mode: static
```

Check the documentation for more configuration options: https://docs.harvesterhci.io/v1.7/install/harvester-configuration

### 2. Create the Metadata File (`meta-data`)

Create an empty file named `meta-data`. This is required by the cloud-init standard.

```bash
touch meta-data
```

### 3. Generate the `cidata` ISO

Package these two files into a small ISO image with the specific label `cidata`. You can use `mkisofs` (or `genisoimage` on some systems).

```bash
mkisofs -output cidata.iso -volid cidata -joliet -rock user-data meta-data
```

### 4. Boot the VM

You now have two files:

1. **Your Raw Image:** `harvester-amd64.raw` (or `.qcow2` if you converted it)
2. **Config ISO:** `cidata.iso`

Attach **both** to your virtual machine. The raw image should be the primary boot disk (VirtIO), and the `cidata.iso` should be attached as a CD-ROM or second disk.


### 5. Verification

When the VM boots:

1. Harvester will detect the `cidata` volume.
2. It will read the `user-data`.
3. The `install.automatic: true` flag will trigger the configuration application.
4. The node will eventually come up as "Ready," and you will see the management URL on the console (or be able to access it via the IP assigned).
