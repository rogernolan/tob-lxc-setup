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

Trusted service sources are `192.168.68.0/22` and the local IPv6 ULA subnet
`fdbc:54c7:7b7e:4bdd::/64`. By default, profiles permit the same selected service ports
from both subnets. Other IPv4/IPv6 sources remain blocked; do not add blanket
`fe80::/10` or public IPv6 allowances.

This dual-stack policy was approved on 2026-09-09 after tests showed ordinary
`.local` SSH selecting a guest ULA address and suffering IPv4 fallback delays.
It replaces the initial IPv4-only policy and the intermediate SSH-only IPv6
proposal. The ULA prefix is specific to this LAN; review it if addressing
changes. Do not automatically trust a new prefix from discovery results.

## Command and profiles

```sh
configure-lxc-firewall VMID PROFILE [--port PORT ...] [--service-source lan|gateway] [--dry-run]
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
| `development` | All TCP from gateway 192.168.68.71; LAN SSH retained |
| `unrestricted` | Guest enforcement disabled; no inbound isolation from this tool |

All restrictive profiles set `enable: 1`, `policy_in: DROP`, and
`policy_out: ACCEPT`, and preserve required network control traffic and local
mDNS discovery. SSH is always included in restrictive profiles for v1.
For `application` and `lan-smb`, `--service-source gateway` narrows service
access to `192.168.68.71`, while SSH retains both LAN subnets. Default service
source is `lan`. `development` requires gateway service access and opens all
TCP ports from that source, without claiming to identify HTTPS. Reject a LAN
service source for development and any service-source option for ssh-only or
unrestricted. Rog approved this exception to the shared LAN/Tailnet tier for
tob-files and tob-dev on 2026-09-09. Gateway-only access includes Caddy and
other gateway-originated traffic because SNAT removes the original identity.
`application` replaces the original `caddy-backend` name; `ssh-only` replaces
`private-ssh`. There are no legacy aliases to maintain for these new commands.

`unrestricted` writes a managed configuration with `enable: 0` and ACCEPT
policies, preserving the NIC flag. It is an explicit profile transition, not
deletion of the policy file. Output must say that guest inbound isolation is
disabled; it does not promise reachability through other network controls.

VMID must be a valid numeric Proxmox identifier resolving to a local LXC.
Require at least one `--port` for `application`. Accept decimal integers
1–65535, normalize them, deduplicate and numerically sort ports. Reject unknown
profiles/options, missing option values, ranges, nonnumeric ports, and `--port`
on other profiles. `--help` requires no host privileges or Proxmox tools.

### Direct SMB requirements

`lan-smb` targets a modern Samba file server deliberately using direct SMB
over TCP 445. Clients use SMB2 or SMB3, with SMB1 disabled in the Samba service
configuration. A port-based firewall cannot enforce the negotiated SMB version:
opening 445 is not proof that SMB1 is disabled.

The profile must:

- Allow TCP 445 and management SSH TCP 22 from the trusted sources defined
  above, including SNATed Tailscale clients.
- Add no TCP or UDP allowances for ports 137–139. In particular, do not open
  UDP 137 (NetBIOS name service), UDP 138 (NetBIOS datagrams), or TCP 139
  (SMB over NetBIOS). Do not open UDP 445.
- Generate explicit service-port rules rather than use a broad Samba/SMB
  macro that might include legacy ports. Do not enable NetBIOS automatically
  when discovery or a connection fails.
- Retain the common local mDNS/control-traffic rules. mDNS is separate from
  SMB transport and must not introduce a NetBIOS dependency.

Clients connect directly to a share, for example `smb://fileserver.local/share`
on the LAN or `smb://<server-LAN-IP>/share` through the Tailscale subnet route.
A normally resolvable DNS name is also suitable. Local `.local` resolution
does not imply service advertisement or appearance in a file manager's Network
view. NetBIOS browsing, WINS, WS-Discovery and automatic share discovery are
not acceptance requirements, and no extra ports are opened to support them.

This is a file-serving profile, not an Active Directory domain-controller or
general Samba infrastructure profile. The firewall tool must not edit
`smb.conf`, manage `nmbd`, change authentication/share permissions, or configure
service advertisements. Document direct TCP 445 listening and SMB2/SMB3-only
operation as guest-service prerequisites, checked separately before rollout.
Legacy compatibility, if ever needed, requires a separately named, explicitly
requested profile; it must not broaden the default `lan-smb` profile.

## Local discovery and network control traffic

Local `.local` name resolution must continue to work after applying a
restrictive profile, including normal SSH by name from the Mac. Preserve the
guest's existing Avahi setup. No `.local` discovery over Tailscale is required.

Use fresh lookups and connections to 105 to verify this behaviour. Inspection
of actual discovery and connection traffic on 105 is authorized to establish
which rules are needed; keep captures narrowly scoped to that test. Choose
the simplest native Proxmox rules supported by the observations, rather than
prescribing a complete mDNS rule set in advance.

Keep normal guest networking working, including address configuration, DNS
and outbound HTTPS. Discovery/control allowances must not broaden service
access: the same trusted-subnet boundaries apply to both address families. The firewall command does not reconfigure Avahi or add a reflector.

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
in v1. Manual adoption remains a separate reviewed operation. Refuse an unknown
managed format version rather than assuming that its contents can be replaced.

## Validation and application safety

Proxmox watches live firewall configuration and applies it automatically.
Writing the live file and then running `pve-firewall compile` is not a safe
pre-validation mechanism for an already-enabled guest.

Prefer validating the proposed complete configuration with the installed
native compiler outside the live watched files, where a suitable mechanism
exists. Do not assume Proxmox provides a command to validate an arbitrary
candidate file in its full intended context.

An alternative strategy is acceptable if it demonstrates that no new or
changed restrictive policy can become active until the candidate has been
validated. Existing active protection must remain in place during validation;
do not stop the host-wide firewall or temporarily disable existing guest
enforcement. The safety argument must cover both first-time enablement and
updates to an already-protected guest, including automatic firewall reloads,
partial failures and interruption between steps.

Record the mechanism, installed-version evidence, activation barrier and
failure behaviour in the implementation documentation. Validate the candidate
that will actually be activated, with its intended enabled state and relevant
configuration context; successfully compiling a disabled configuration is not
enough if the compiler skips the candidate rules. Prove the ordering with
tests, including a deliberately invalid candidate that never becomes active.
Use fixtures or isolated validation for invalid candidates; do not place
malformed rules in watched production configuration to test this guarantee.
If neither the preferred nor an alternative strategy can meet these guarantees,
leave the live configuration unchanged and report the limitation.

The apply sequence is below. An alternative may adapt the staging and
publication details, but must retain these ordering guarantees and document
its exact sequence and recovery points.

1. Validate arguments, root privileges, host identity, local LXC identity,
   network support, backend/service state, Datacenter enablement, and writable
   cluster configuration. Detect pre-existing native compiler errors and abort
   without trying to repair unrelated configuration.
2. Serialize invocations with a host-local lock. Capture the guest firewall
   file, its original presence/absence, and the complete selected NIC property.
3. Generate the deterministic candidate. Before any live staging or mutation,
   recheck the captured state and save a durable, root-only recovery snapshot
   outside `/etc/pve`, under `/var/backups/tob-lxc-firewall/<VMID>/`. Keep one
   previous successful state plus any unresolved transaction snapshot; refuse
   to overwrite unresolved recovery state. Do not accumulate unlimited
   snapshots. Purely isolated validation need not create a recovery snapshot
   until it succeeds and a live change is needed.
4. Validate the candidate using the preferred isolated mechanism or a
   demonstrated safe alternative described above. Any staging in watched
   configuration must be proven unable to activate the unvalidated candidate
   or disturb existing protection. Validate in the relevant complete context,
   including the intended NIC firewall state. A successful exit alone is not
   sufficient if the native parser reports errors while returning success;
   verify its diagnostics contract with malformed fixtures.
5. Before activation, recheck that the candidate and relevant configuration
   context still match what was validated, accounting for the tool's own
   staging. Abort and recover if they changed. A tool lock does not exclude
   GUI/API edits: concurrent external editing or migration is unsupported
   during apply. Never silently activate a different candidate from the one
   validated.
6. Replace the live firewall file using a complete-file publication mechanism
   verified for pmxcfs. Preserve all other configuration. For restrictive
   profiles, only then enable the NIC flag through native Proxmox tooling,
   preserving every other NIC property. Never temporarily disable an enabled
   NIC. Unrestricted leaves the NIC property unchanged.
7. Revalidate and wait for bounded evidence that the intended active rules
   have converged for a running guest. For a stopped guest, report the policy
   as configured with runtime verification pending; do not start it implicitly.
   Distinguish saved configuration from active enforcement. Do not claim
   runtime success from compiler output alone.
8. On an apply failure or handled interruption, restore the original firewall
   file/presence and NIC property and verify recovery. Avoid overwriting a
   concurrent external edit during rollback; retain recovery data and report
   the conflict. On rollback failure, return nonzero with exact recovery paths
   and instructions. A later run detects incomplete transactions.

With isolated validation, validation failure leaves the live files and NIC
untouched. An alternative involving live staging must leave active protection
unchanged and restore the original staged configuration on validation failure,
with recovery information retained for an interrupted or failed restoration.
Apply failure triggers recovery, but the operation spans separate Proxmox
objects and is not an atomic transaction. After validation, activation or
rollback can temporarily affect connectivity; an uncatchable interruption can
leave recovery pending. This limitation does not permit activation of an
unvalidated restrictive candidate. Do not flush conntrack or reboot
automatically during apply.

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
Cover stopped-guest reporting, unknown managed format versions and a change
to the candidate or validation context before activation. Test source matching
with trusted and untrusted address fixtures, not just expected rule text.

For every restrictive profile, assert that each selected TCP service port has
exactly one IPv4 and one IPv6 allow rule, scoped to the two trusted subnets.
Discovery/control rules must not allow other application ports. Unrestricted
must generate no service rules.

For `lan-smb`, automated rule tests must verify that TCP 445 and TCP 22 are
allowed only from the configured trusted sources and that no generated rule
or expanded macro permits TCP/UDP 137–139 or UDP 445. Verify this for fresh
generation, reruns, and transitions from an `application` profile that had
explicitly allowed a legacy port, so obsolete allowances cannot survive.

For live tests, use only 105 and first display/capture its config, expected
hostname, addresses, runtime state, guest firewall file and NIC flag. Record
installed package versions, compiler behaviour, baseline connectivity, recovery
procedure and exact dry-run output. Stop on identity or configuration mismatch.

Ensure 105 is running for integration testing. Apply `ssh-only` and verify:

1. Fresh direct LAN SSH succeeds, including a fresh `.local` resolution and
   connection. Record A/AAAA answers and actual source/destination addresses.
   Verify ordinary `.local` SSH and IPv6-forced SSH connect promptly from the
   trusted IPv6 subnet, without requiring IPv4 fallback.
2. Fresh SSH through the gateway/Tailscale subnet route succeeds; verify its
   observed source address. Existing SSH sessions are not evidence.
3. A temporary TCP listener proved reachable before the change becomes
   unreachable from LAN and Tailscale when its port is not allowed. Confirm
   the listener is still running through host-side access. A closed-port
   failure alone does not prove filtering.
4. Guest DNS and HTTPS work; inspect relevant IPv4/IPv6 active rules.
5. An identical rerun makes no changes and the native compiler has no errors.
6. Restart only 105 and repeat the reachability/discovery checks.

Where 105 has usable IPv6 connectivity, verify that fresh IPv6 connections to
unlisted listening test service ports remain blocked,
while required local discovery/control traffic still works. Confirm listeners
and the IPv6 path before attributing failure to filtering. If IPv6 cannot be
exercised, record this as not tested; do not claim dual-stack runtime verification.

On 105, also test an `application` transition using a temporary listener,
confirm its allowed port is reachable over LAN/Tailscale, then restore
`ssh-only` and confirm new connections to that port are blocked again.
No Caddy publication is necessary. Exercise an unrestricted
transition and restoration on this disposable guest if the baseline and
recovery checks permit it. Remove temporary listeners afterward.

Validate `lan-smb` on 105 using a disposable Samba share if a Samba test fixture
is available. Verify a fresh authenticated SMB2/SMB3 connection and a small
file read/write over TCP 445 from LAN and Tailscale, direct access by LAN
`.local` name, continued SSH, and the absence of legacy-port allow rules in
the active firewall. Confirm the test service rejects SMB1 and does not rely
on NetBIOS. Use only disposable credentials/data and remove the fixture after
testing. If no Samba fixture is available, record SMB protocol/file-operation
tests as not run; a TCP listener proves port reachability only. Do not test
against or reconfigure the production file server to fill this gap.

At the end of successful integration testing, leave 105 on `ssh-only`, remove
temporary test services/data and verify a fresh SSH connection. On failure,
use the recovery procedure and report the actual final state.

Provide the script, automated tests, README usage/recovery instructions, exact
105 dry-run output, live test results, version-dependent findings and honest
limitations. Mark unavailable tests as not run; do not infer their success.
README should describe installation on the host, profiles, address scope,
direct-SMB prerequisites and excluded browsing protocols, local discovery,
inspection and recovery. Use the repository's review-first download/install
convention and a reviewed local
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
