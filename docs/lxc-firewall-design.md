# Proxmox LXC firewall design

## Objective and scope

Add `scripts/configure-lxc-firewall`, run as root on the Proxmox host, to
configure native guest firewall policy. `setup.sh` continues to configure the
guest OS; `add-caddy-host` continues to publish applications through Caddy.
Neither command provisions guest firewalls.

This document revises the supplied specification with the agreed access model:
LAN and Tailscale form one trusted service-access tier. SSH is available directly
on the LAN, including through `.local` names. Caddy publication is optional and
never requires more guest firewall access than private application use.

Only VMID **105**, hostname **tob-test-lxc**, may be changed during initial live
testing. Production guests, including the real file server and Bambuddy, must
not be changed. Writing this design does not constitute live test execution.

## Environment and access model

Reported environment, to verify before implementation is exercised:

- PVE 9.2.2 with legacy `pve-firewall` / iptables; do not change backend.
- Datacenter firewall enabled; host firewall already configured separately.
- LAN: `192.168.68.0/22`; Proxmox host: `192.168.68.81`.
- Gateway running Caddy and Tailscale: `192.168.68.71`.
- Tailscale subnet traffic is SNATed to the gateway address.

```text
LAN clients -------------------------+---- SSH / selected service ports
                                     |
Tailscale --> tob-gateway (.71) -------+---- private LXCs
                                     |
Internet --> Caddy on tob-gateway ----+---- selected application ports
```

Allowing the LAN subnet includes both gateway-originated Caddy traffic and
SNATed Tailscale traffic. The guest firewall does not distinguish these uses.
An application may be accessible locally and over Tailscale without being
published through Caddy. Authentication enforced only by Caddy does not protect
direct application access; applications requiring authentication must account
for that access path.

Default trusted service sources are `192.168.68.0/22` and IPv6 link-local
`fe80::/10` on the guest's single interface. The IPv6 link-local allowance is a
design default to support local name-based access. Do not allow all IPv6 sources
or infer a trusted routed IPv6 prefix. Routed/global IPv6 service access requires
a future explicit source-policy extension. Verify the addresses actually used
by `.local` clients during testing; do not claim arbitrary AAAA records work.

## Command and profiles

```sh
configure-lxc-firewall VMID PROFILE [--port PORT ...] [--dry-run]
configure-lxc-firewall --help

configure-lxc-firewall 105 ssh-only --dry-run
configure-lxc-firewall 105 ssh-only
configure-lxc-firewall 105 application --port 8080 --port 9090 --dry-run
```

| Profile | Inbound service access from trusted sources |
| --- | --- |
| `ssh-only` | TCP 22 |
| `application` | TCP 22 and all explicitly supplied TCP ports |
| `lan-smb` | TCP 22 and TCP 445 for modern direct SMB |
| `unrestricted` | Guest enforcement disabled; no inbound isolation from this tool |

All restrictive profiles set `enable: 1`, `policy_in: DROP`, and
`policy_out: ACCEPT`, and preserve required network control traffic and local
mDNS discovery. SSH is always included in restrictive profiles for v1.
`application` replaces the original `caddy-backend` name; `ssh-only` replaces
`private-ssh`. There are no legacy aliases to maintain for these new commands.

`lan-smb` deliberately excludes legacy NetBIOS ports and Windows discovery
protocols. It supports direct SMB by address/name with local mDNS, rather than
every Samba configuration. Document this limitation; confirm service needs
before any later rollout to the actual file server.

`unrestricted` writes a managed configuration with `enable: 0` and ACCEPT
policies, preserving the NIC flag. It is an explicit profile transition, not
deletion of the policy file. Output must say that guest inbound isolation is
disabled; it does not promise reachability through other network controls.

VMID must be a valid numeric Proxmox identifier resolving to a local LXC.
Require at least one `--port` for `application`. Accept decimal integers
1–65535, normalize them, deduplicate and numerically sort ports. Reject unknown
profiles/options, missing option values, ranges, nonnumeric ports, and `--port`
on other profiles. `--help` requires no host privileges or Proxmox tools.

## Local discovery and network control traffic

Preserve the Avahi/mDNS service already installed by guest setup. The firewall
command does not install, start, or reconfigure Avahi.

Permit LAN mDNS using UDP 5353, with IPv4 multicast destination `224.0.0.251`
and IPv6 link-local multicast destination `ff02::fb`. Account for required
unicast mDNS exchanges as well; avoid a multicast-only rule set that resolves
names inconsistently. Scope source allowances to the trusted local sources.
Do not add a multicast reflector or promise `.local` discovery over Tailscale.

Inspect static/DHCP addressing and preserve required DHCP, IPv6 neighbour
discovery, router solicitation/received advertisements, and related ICMP error
traffic using verified native Proxmox behaviour. Do not turn the guest into a
router or add egress restrictions. Describe the policy as denying unlisted
unsolicited **application** traffic, rather than denying all inbound packets.

The exact mDNS/control rules must be checked against the installed legacy
compiler and active rules. IPv4 and IPv6 tests must confirm that service ports
remain restricted without breaking the intended local discovery path.

## Ownership and interfaces

Use `/etc/pve/firewall/<VMID>.fw` and the native `firewall=1` NIC property.
Never write generated `PVEFW-*` chains or an in-guest firewall.

For v1, require exactly one supported bridged `netN` interface, selected by
inspection of `pct config`, not by assuming `net0`. Refuse zero-NIC,
multi-NIC, unsupported-network, migrating, or otherwise ambiguous guests.
Do not offer `--interface` yet: guest-wide policy replacement could affect
other already-enabled NICs. Report this limitation explicitly.

Every generated file contains:

```text
# Managed by tob-lxc-setup configure-lxc-firewall
```

Include a format version and selected profile in deterministic comments.
The tool owns the whole managed file; document that manual edits to managed
files are replaced on the next apply. Refuse an existing unmarked file,
including an empty one. Do not include an unmanaged-file replacement override
in v1. Manual adoption remains a separate reviewed operation.

## Validation and application safety

Proxmox watches live firewall configuration and applies it automatically.
Writing the live file and then running `pve-firewall compile` is not a safe
pre-validation mechanism for an already-enabled guest.

Before implementing live apply, verify a way to parse and compile the proposed
complete configuration using the installed native compiler in isolation from
the live watched files. This is an implementation prerequisite, not permission
to assume a nonexistent CLI option. Record the supported mechanism and version
evidence in the implementation documentation. If no safe mechanism can be
verified, refuse live mutation and report the limitation. Never stop the
host-wide firewall or temporarily disable guest enforcement to validate.

The apply sequence is:

1. Validate arguments, root privileges, host identity, local LXC identity,
   network support, backend/service state, Datacenter enablement, and writable
   cluster configuration. Detect pre-existing native compiler errors and abort
   without trying to repair unrelated configuration.
2. Serialize invocations with a host-local lock. Capture the guest firewall
   file, its original presence/absence, and the complete selected NIC property.
3. Generate the deterministic candidate outside the watched configuration.
   Validate the candidate in the relevant complete configuration context,
   including the intended NIC firewall state. A successful exit alone is not
   sufficient if the native parser reports errors while returning success;
   verify its diagnostics contract with malformed fixtures.
4. Recheck captured state before mutation and abort if it changed. A tool lock
   does not exclude GUI/API edits: document that concurrent external editing
   or migration is unsupported during apply.
5. Save a durable, root-only recovery snapshot outside `/etc/pve`, under
   `/var/backups/tob-lxc-firewall/<VMID>/`. Keep one previous successful state
   plus any unresolved transaction snapshot; refuse to overwrite unresolved
   recovery state. Do not accumulate unlimited snapshots.
6. Replace the live firewall file using a complete-file publication mechanism
   verified for pmxcfs. Preserve all other configuration. For restrictive
   profiles, only then enable the NIC flag through native Proxmox tooling,
   preserving every other NIC property. Never temporarily disable an enabled
   NIC. Unrestricted leaves the NIC property unchanged.
7. Revalidate and wait for bounded evidence that the intended active rules
   have converged. Distinguish saved configuration from active enforcement.
   Do not claim success from compiler output alone.
8. On an apply failure or handled interruption, restore the original firewall
   file/presence and NIC property and verify recovery. Avoid overwriting a
   concurrent external edit during rollback; retain recovery data and report
   the conflict. On rollback failure, return nonzero with exact recovery paths
   and instructions. A later run detects incomplete transactions.

Validation failure leaves the live files and NIC untouched. Apply failure
triggers recovery, but the operation spans separate Proxmox objects and is not
an atomic transaction: transient policy changes and uncatchable interruptions
cannot be ruled out. Document this limit instead of promising uninterrupted
connectivity. Do not flush conntrack or reboot automatically during apply.

Identical reruns report no changes and avoid unnecessary writes/backups, while
still checking whether the desired policy is active. Profile changes replace
the owned policy predictably; they do not append stale allow rules.

## Dry-run and recovery

Dry-run performs read-only inspection and in-memory rendering only: no writes,
backups, lock files, NIC changes, service actions or staging in `/etc/pve`.
Show VMID, hostname, detected addresses, NIC name and full current property,
firewall flag, profile, trusted sources, existing file ownership, proposed full
file contents, and intended changes. Clearly distinguish a rendered proposal
from a natively validated candidate. Refusals still return nonzero.

Before live testing, record exact host-side recovery steps for 105 from its
captured state, including how to restore the file and how to disable the NIC
firewall flag while retaining every other NIC property. Do not present a
truncated `pct set --netN` command that might remove the address, bridge or MAC.
Verify host console/`pct exec` access as the recovery route. Never stop the
entire Proxmox firewall as a guest recovery procedure.

## Verification and deliverables

Follow existing shell tests with temporary roots, fixture files and command
stubs. Separate rendering/profile data from host inspection and mutation.
Automated tests must cover parsing, invalid/missing VMID, wrong guest type,
profiles and ports, single-NIC selection/refusals, unmanaged files, deterministic
output, all source/port rules, IPv6/mDNS handling, unrestricted transitions,
idempotence, and dry-run with no writes. Add failure injection for candidate
validation, live-file publication, NIC update, post-apply validation, rollback,
interruption recovery and concurrent state changes. Assert unrelated host,
Datacenter, NIC and guest configurations are unchanged.

For live tests, use only 105 and first display/capture its config, expected
hostname, addresses, runtime state, guest firewall file and NIC flag. Record
installed package versions, compiler behaviour, baseline connectivity, recovery
procedure and exact dry-run output. Stop on identity or configuration mismatch.

Apply `ssh-only` and verify:

1. Fresh direct LAN SSH succeeds, including a fresh `.local` resolution and
   connection. Record which IPv4/IPv6 address the client used.
2. Fresh SSH through the gateway/Tailscale subnet route succeeds; verify its
   observed source address. Existing SSH sessions are not evidence.
3. A temporary TCP listener proved reachable before the change becomes
   unreachable from LAN and Tailscale when its port is not allowed. Confirm
   the listener is still running through host-side access. A closed-port
   failure alone does not prove filtering.
4. Guest DNS and HTTPS work; inspect relevant IPv4/IPv6 active rules.
5. An identical rerun makes no changes and the native compiler has no errors.
6. Restart only 105 and repeat the reachability/discovery checks.

On 105, also test an `application` transition using a temporary listener,
confirm its allowed port is reachable over LAN/Tailscale, then restore
`ssh-only`. No Caddy publication is necessary. Exercise an unrestricted
transition and restoration on this disposable guest if the baseline and
recovery checks permit it. Remove temporary listeners afterward.

Provide the script, automated tests, README usage/recovery instructions, exact
105 dry-run output, live test results, version-dependent findings and honest
limitations. Mark unavailable tests as not run; do not infer their success.
README should describe installation on the host, profiles, address scope,
modern-SMB limitation, local discovery, inspection and recovery. Use the
repository's review-first download/install convention and a reviewed local
payload; never require running `setup.sh` on the Proxmox host.

## Exclusions and references

Do not change host/Datacenter policy, backend, guest OS setup, Caddy,
Tailscale configuration, LAN addressing, egress policy, or production guests.
Do not characterize/restrict Bambuddy or add application-specific exceptions
for notifications, printers, or unrelated services in this change.

References inform the design; installed-version checks remain required:

- [Proxmox firewall documentation source](https://raw.githubusercontent.com/proxmox/pve-docs/master/pve-firewall.adoc):
  watched configuration files, guest-wide options, per-NIC enablement and native
  protocol exceptions.
- [RFC 6762: Multicast DNS](https://www.rfc-editor.org/info/rfc6762/):
  local discovery transport and multicast groups.
- [Samba transport documentation](https://devel.samba.org/samba/docs/current/man-html/smb.conf.5.html):
  direct SMB and NetBIOS transport distinctions.
