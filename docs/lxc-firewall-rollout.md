# LXC firewall rollout inventory

Inventory supplied by Rog on 2026-09-09. All guests were running. Application
ports must be confirmed before a restrictive policy is applied; names alone
are not port evidence. Only 105 has been changed during this development task.

| VMID | Name | Use | Rollout treatment |
| --- | --- | --- | --- |
| 100 | tob-bambuddy | Bambuddy UI on 8080; unknown inbound printer traffic from BambuLabs H2D | Keep unrestricted; do not guess printer ports |
| 101 | tob-gateway | Tailscale exit/subnet routing and Caddy | Separate gateway policy required; do not apply an application profile |
| 102 | tob-notifications | Bark APNS and Bambuddy-to-Bark bridge | Confirm listeners and upstream connections before choosing ports |
| 103 | tob-webserver | Existing HTTPS sites; future Instablog HTTPS | Confirm actual guest listening ports, not just Caddy public port |
| 104 | tob-files | Samba shares from ZFS | `lan-smb --service-source gateway`: TCP 445 from gateway only; LAN SSH retained |
| 105 | tob-test-lxc | Disposable test host | Keep ssh-only between live tests |
| 106 | restaurant-radar | Restaurant Radar HTTPS/RSS | Confirm actual guest listening port behind Caddy |
| 107 | tob-dev | Development services on arbitrary ports | `development`: all TCP from gateway only; LAN SSH retained |

Tailscale subnet connections arrive with source 192.168.68.71 due to gateway
SNAT. A guest firewall can allow that source, but cannot distinguish Tailnet
clients from Caddy or other gateway-originated traffic. It cannot identify
HTTPS from a TCP port allowance. Direct LAN SSH is useful for .local setup and
remains separate from more restricted application/SMB access. Rog approved
gateway-only services with LAN SSH for 104 and 107. This intentionally excludes
direct LAN application access over both IPv4 and IPv6; SSH still allows both
configured LAN subnets. Discovery rules remain in place.

Read-only inspection of Caddy found these upstreams, which need matching to
guest listeners before rollout:

- Bambuddy: `192.168.68.56:8000` (differs from the supplied port 8080).
- Homepage: `192.168.68.73:80`.
- Restaurant Radar: `192.168.68.75:8765`.

No production firewall has been applied from this inventory.

## Bambuddy Virtual Printer follow-up

Rog confirmed Virtual Printer is in use. The supplied live listener inventory
shows UI TCP 8000, UDP discovery 2021, TCP 21/80/322/443/990/2024–2026/3000/3002/
6000/8883, and TCP passive file transfer 50000–50100. This reflects the installed
version rather than assuming every upstream release has identical listeners.
Proposed preview with the range-support release (not applied):

```sh
sudo configure-lxc-firewall 100 application \
  --port 8000 --port 21 --port 80 --port 322 --port 443 --port 990 \
  --port 2024-2026 --port 3000 --port 3002 --port 6000 --port 8883 \
  --port 50000-50100 --udp-port 2021 --dry-run
```

Before applying to 100, test TCP range endpoints/outside ports and UDP request/
response with disposable listeners on 105, then restore ssh-only. Validate
Virtual Printer discovery, sending a print/file and camera access in an attended
Bambuddy session. A listener inventory alone does not prove these behaviours.
Gateway 101 remains unchanged by agreement.
