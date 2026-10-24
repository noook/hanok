# CI runner (hanok-ci)

The VM that runs GitHub Actions jobs for my private repositories. Why it looks like this: ADR 0004. Its files: `hosts/hanok-ci/`.

## The VM as built

| | |
|---|---|
| Proxmox | VM 101, name `hanok-ci`, start at boot |
| Image | Debian 13 generic cloud image (`debian-13-genericcloud-amd64.qcow2`) |
| System | q35, SeaBIOS, VirtIO SCSI single, QEMU agent on, serial console (`serial0`) |
| CPU | 3 cores, type `host`, `cpuunits` 50 |
| Memory | 8192 MiB, ballooning off |
| Disk | `local-lvm`, 70 GB, discard + iothread + SSD emulation |
| Network | `vmbr0`, VirtIO, firewall on, DHCP (reserved on the box) |
| Login | cloud-init user with my Mac's SSH key, no password |

## Create (or rebuild) it

On the Proxmox host shell, after creating an empty VM in the wizard with the settings above (OS: no media; Disks: delete the default disk):

```bash
VMID=101
cd /root
wget https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2
wget https://cloud.debian.org/images/cloud/trixie/latest/SHA512SUMS
sha512sum -c SHA512SUMS --ignore-missing

qm disk import $VMID debian-13-genericcloud-amd64.qcow2 local-lvm
qm set $VMID --scsi0 local-lvm:vm-$VMID-disk-0,discard=on,iothread=1,ssd=1
qm resize $VMID scsi0 70G
qm set $VMID --ide2 local-lvm:cloudinit --boot order=scsi0 --serial0 socket --vga serial0
qm set $VMID --ciuser <admin user> --sshkeys /root/mac.pub --ipconfig0 ip=dhcp
```

- `serial0` matters: the cloud image writes its console there, so without it the console stays black.
- After any change on the Cloud-Init tab, click **Regenerate Image**. Proxmox then gives cloud-init a new instance id and the VM applies it at the next boot.
- "Guest agent not running" is expected until `setup.sh` has run.

**Firewall**, before the first boot: copy `hosts/hanok-ci/firewall.fw.example` to `/etc/pve/firewall/$VMID.fw` and fill in the box, Mac and Tailscale-router addresses (or click the same rules in VM > Firewall). The Datacenter firewall must be on for VM rules to apply. If you turn it on for the first time, set its input policy to ACCEPT first, or the host itself becomes unreachable except on 8006 and 22. In the UI, put the port in **Dest. port**, not Source port: a rule with 22 as source port matches nothing and SSH times out.

**SSH from anywhere.** The name `hanok-ci` only resolves through the box's DNS, so it fails away from home. The VM is not on the tailnet (ADR 0004); the subnet router advertises the LAN, so its LAN address works from anywhere on the tailnet. In the Mac's `~/.ssh/config`:

```
Host hanok-ci
  HostName <VM LAN IP>
  User <admin user>
```

Reserve that address for the VM on the box so it never changes.

**Software**, from the Mac:

```bash
scp -r hosts/hanok-ci hanok-ci:
ssh hanok-ci 'sudo hanok-ci/setup.sh'
```

**Check the isolation** with the firewall on. A job runs as `runner` and its containers leave through the same NIC, so these test what a job can reach:

```bash
ssh hanok-ci
sudo -u runner curl -sm 5 -o /dev/null -w '%{http_code}\n' https://api.github.com    # 200
sudo -u runner curl -m 5 http://<docker-host IP>                                     # must time out
sudo -u runner curl -m 5 -k https://<Proxmox IP>:8006                                # must time out
sudo -u runner docker run --rm curlimages/curl -m 5 http://<docker-host IP>           # must time out
ip -6 addr show scope global                                   # prints nothing once setup.sh has run
sudo -u runner curl -6 -m 5 http://[<docker-host global IPv6>]   # must fail (no IPv6 route, or a timeout)
```

Then take a Proxmox snapshot named `clean`: a restore point with no runner credentials.

## Register a repository

Only private repositories (ADR 0004). On GitHub: the repository > Settings > Actions > Runners > **New self-hosted runner**, copy the `--token` value (valid for one hour). Then:

```bash
ssh hanok-ci 'sudo hanok-ci/add-repo.sh noook/<repo> <count>'
```

`<count>` is the number of jobs the workflow runs in parallel. The runners show as Idle on the Runners page. Then set the repository variable `CI_RUNNER=hanok-ci` and use it in the workflows (`docs/conventions.md`, "Using the CI runner").

Runners registered by hand before `add-repo.sh` existed (Plouf's two): run `add-repo.sh noook/plouf 2` and press Enter at the token prompt. It only adds the cleanup hook and restarts them.

To unregister: Settings > Actions > Runners > the runner > Remove, copy the token, then `sudo hanok-ci/remove-repo.sh noook/<repo>`.

## Jobs stay "Queued"

GitHub keeps a queued job for 24 hours, then fails it.

1. Settings > Actions > Runners: are the runners Offline?
2. `ssh hanok-ci 'systemctl status "actions.runner.*"'`, and `journalctl -u 'actions.runner.*' -n 50`.
3. Is the job's `runs-on` exactly `hanok-ci`, and the repository variable set?
4. For CI right now: unset the repository's `CI_RUNNER` variable and re-run the workflow. It runs on GitHub, which costs minutes.

## Disk full or dirty VM

- `docker system df`, then `sudo systemctl start docker-prune` for the weekly prune now.
- If it still looks wrong, rebuild: roll back to the `clean` snapshot, or delete the VM and recreate it with this runbook. Then register the repositories again (the old runners show Offline; remove them from the Runners page).
