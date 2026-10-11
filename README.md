# fwlab-proxmox

**A reproducible two-VM iptables firewall lab on Proxmox VE, provisioned with Terraform and cloud-init.**

## Overview

`fwlab-proxmox` is the infrastructure part of a university lab on firewall configuration and network traffic analysis. It automatically builds an isolated test environment on Proxmox VE: a **server** VM that runs services protected by an `iptables` firewall, and a **client** VM that generates test traffic against it.

Terraform creates the network bridge, downloads the Ubuntu cloud image, uploads the cloud-init files, and deploys both VMs. Cloud-init then installs the required packages and starts the services, so the environment can be created, destroyed, and recreated in the same state at any time.

> The firewall rules themselves are applied manually on the server VM during the lab. Terraform only provisions the environment.

## Architecture

```text
                 Proxmox VE node
 ┌────────────────────────────────────────────────┐
 │                                                │
 │   ┌──────────────┐          ┌───────────────┐  │
 │   │  fw-client   │          │   fw-server   │  │
 │   │              │          │               │  │
 │   │ nc, nmap,    │          │ SSH     :22   │  │
 │   │ curl, ab,    │          │ nginx   :80   │  │
 │   │ tcpdump      │          │ test    :8080 │  │
 │   │              │          │ iptables      │  │
 │   └──┬────────┬──┘          └──┬─────────┬──┘  │
 │      │        │                │         │     │
 │  10.40.0.10   │           10.40.0.20     │     │
 │      │        │                │         │     │
 │   ═══╧════════╪════════════════╧═════════╪═══  │
 │         lab bridge (isolated, no uplink)       │
 │               │                          │     │
 │   ════════════╧══════════════════════════╧═══  │
 │         management bridge (DHCP, internet)     │
 └────────────────────────────────────────────────┘
```

| VM | Role | Lab network address | Resources |
|---|---|---|---|
| `fw-server` | Target host with firewall | `10.40.0.20/24` | 2 vCPU, 2 GiB RAM, 20 GiB disk |
| `fw-client` | Test traffic source | `10.40.0.10/24` | 2 vCPU, 1 GiB RAM, 12 GiB disk |

Each VM has two network interfaces:

- **Management interface** on an existing bridge (DHCP). It provides internet access for package installation and SSH access from your workstation.
- **Lab interface** on a dedicated bridge created by Terraform, with a static address. Test traffic between the VMs goes through it.

## What gets deployed

- A Linux bridge for the lab network, with no physical ports and no IP address on the host.
- The Ubuntu 24.04 (Noble) cloud image, imported into the Proxmox datastore.
- Two cloud-init snippets, rendered from templates with your public SSH key.
- The `fw-server` VM with `openssh-server`, `nginx` on port 80, a test HTTP service on port 8080 (a systemd unit running `python3 -m http.server`), `iptables`, `iptables-persistent`, `netcat`, `nmap`, `tcpdump`, and `curl`.
- The `fw-client` VM with `netcat`, `nmap`, `tcpdump`, `curl`, and `apache2-utils` (`ab`).

## Requirements

**On your workstation**

- Terraform `>= 1.5.0` (OpenTofu should also work)
- An SSH client and `ssh-agent`
- Wireshark, optional, for analyzing captures

**On the Proxmox VE node**

- Proxmox VE with a node reachable over HTTPS (port 8006) and SSH (port 22)
- A datastore (default `local`) with the **Snippets** and **Import** content types enabled
  (Datacenter → Storage → *your datastore* → Content)
- A VM disk datastore (default `local-lvm`)
- An existing management bridge (default `vmbr0`) with DHCP and internet access
- A user and API token for Terraform with enough permissions to manage nodes, VMs, storage, and networks

## Repository structure

```text
.
├── cloud-init/
│   ├── client.yaml.tftpl      # Cloud-init template for the client VM
│   └── server.yaml.tftpl      # Cloud-init template for the server VM
├── main.tf                    # Image download, cloud-init files, VMs
├── network.tf                 # Lab network bridge
├── outputs.tf                 # Output values
├── providers.tf               # Proxmox provider configuration
├── variables.tf               # Input variables
├── versions.tf                # Terraform and provider version constraints
├── terraform.tfvars.example   # Example variable values
└── .terraform.lock.hcl        # Provider version lock
```

## Configuration

### Variables

| Variable | Description | Default |
|---|---|---|
| `pm_endpoint` | Proxmox API URL, for example `https://PVE_IP:8006/` | required |
| `pm_api_token` | API token in the form `user@realm!tokenid=secret` | required, sensitive |
| `pm_ssh_user` | SSH user on the Proxmox node (used to upload snippets) | `root` |
| `node_name` | Proxmox node name | see `variables.tf` |
| `vm_datastore` | Datastore for VM disks | see `variables.tf` |
| `iso_datastore` | Datastore for the image and snippets | `local` |
| `mgmt_bridge` | Existing management bridge | see `variables.tf` |
| `lab_bridge` | Name of the lab bridge to create | see `variables.tf` |
| `ssh_public_key_path` | Path to the public key injected into the VMs | `./id_ed25519.pub` |
| `server_lab_ip` | Server address on the lab network | `10.40.0.20/24` |
| `client_lab_ip` | Client address on the lab network | `10.40.0.10/24` |

### Credentials

Never commit secrets. Pass the API token through an environment variable:

```bash
export TF_VAR_pm_api_token='user@pve!tokenid=SECRET'
```

Copy the example variables file and edit it:

```bash
cp terraform.tfvars.example terraform.tfvars
```

## Deployment

**1. Generate an SSH key** (skip if you already have one at the configured path):

```bash
ssh-keygen -t ed25519 -f ./id_ed25519 -C "fw-lab"
```

**2. Authorize the key on the Proxmox node and load it into the agent.**
The provider uploads snippets over SSH, so the key must be accepted by the Proxmox node and available in `ssh-agent`:

```bash
ssh-copy-id -i ./id_ed25519.pub root@PVE_IP
eval "$(ssh-agent -s)"
ssh-add ./id_ed25519
```

**3. Set variables and the token** as described in the Configuration section.

**4. Initialize, review, and apply:**

```bash
terraform init
terraform validate
terraform plan -out=tfplan
terraform apply tfplan
```

If you hit lock errors from the Proxmox API, apply with `-parallelism=1`.

**5. Wait for cloud-init to finish**, then connect to the VMs using the addresses printed by Terraform:

```bash
ssh -i ./id_ed25519 lab@<VM_MANAGEMENT_IP>
cloud-init status --wait
```

The default user on both VMs is `lab` (key authentication only, passwordless sudo).

## Verifying the environment

On the server:

```bash
sudo ss -lntp          # expect listeners on 22, 80 and 8080
iptables --version
```

On the client:

```bash
nc -zvw3 10.40.0.20 22
nc -zvw3 10.40.0.20 80
nc -zvw3 10.40.0.20 8080
curl --connect-timeout 3 http://10.40.0.20/
```

Before any firewall rules are applied, all three ports should be reachable.

## Lab scenarios

The environment is designed for the following exercises, performed manually on the server:

1. **Baseline filtering.** Allow SSH (22) and HTTP (80), drop everything else, and verify with `nc`, `nmap`, `curl`, and a browser.
2. **Logging.** Log dropped packets (with rate-limited `LOG` rules) and analyze the journal.
3. **Traffic analysis.** Capture traffic with `tcpdump` on the lab interface and inspect it in Wireshark.
4. **ICMP filtering.** Block ICMP echo requests and compare behavior before and after.
5. **Time-based access.** Allow new SSH connections only in a defined UTC time window (`-m time`).
6. **Rate limiting.** Limit new TCP connections to port 80 per source IP (`-m hashlimit`) and test with `ab`.
7. **Persistence.** Save the rules with `netfilter-persistent` and verify them after a reboot.

## Cleanup

```bash
terraform destroy
```

This removes the VMs, the cloud-init snippets, the imported image, and the lab bridge.

## Security notes

This project is intended for an isolated lab and makes several simplifications:

- `insecure = true` in the provider disables TLS certificate verification for the self-signed Proxmox certificate.
- The Terraform user may have broad privileges (for example, the `Administrator` role) for convenience. In real environments, create a custom role with minimal privileges and keep API token privilege separation enabled.
- The `.gitignore` excludes `terraform.tfvars`, state files, and SSH keys. Do not commit them: state files can contain sensitive data.
- The firewall rules cover IPv4 only and do not restrict outbound traffic.

## License

This project is licensed under the [MIT License](./LICENSE).
