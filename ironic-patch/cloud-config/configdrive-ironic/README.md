### How to use it

1. **Create your config file** (e.g., `harvester-config`):

2. **Run the script:**
```bash
chmod +x build-configdrive.sh
./build-configdrive.sh
```

*(You can also specify arguments: `./build-configdrive.sh my-cluster.yaml my-drive.iso`)*

3. **Deploy:**
Attach the resulting `config-drive.iso` to your server.
With the "Hook" patch or if Harvester cloud-init providers supports ConfigDrive datasource, Harvester will detect the `config-2` label, find the file at `/openstack/latest/user_data`, and copy it to the correct location for installation.
