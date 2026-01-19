### How to use it

1. **Create your config file** (e.g., `harvester-config`):

2. **Run the script:**
```bash
chmod +x build-nocloud.sh
./build-nocloud.sh
```

*(You can also specify arguments: `./build-nocloud.sh my-cluster.yaml my-drive.iso`)*

3. **Deploy:**
Attach the resulting `nocloud-drive.iso` to your server.
Harvester supports the CIDATA label and user-data file path out-of-the-box. This is the "standard" way to inject configuration without modifying the Harvester OS image.
