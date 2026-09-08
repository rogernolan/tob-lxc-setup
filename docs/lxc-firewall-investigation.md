# LXC firewall investigation — 2026-09-08

## Current implementation status

The CLI/service-policy preview increment is implemented. Live apply deliberately
returns nonzero without changes. Discovery rules, native validation and mutation
are not implemented yet; preview output says so explicitly.

Verified locally: new firewall fixture suite, existing setup and Caddy installer
suites, shell syntax and diff whitespace checks passed.

## Read-only host evidence

SSH as rog to 192.168.68.81 succeeds. Installed packages:

- pve-manager 9.2.2
- pve-container 6.1.10
- pve-firewall 6.0.4

The installed `/usr/share/perl5/PVE/Firewall.pm` is readable without root.
`generic_fw_config_parser` (line 3435) accepts paths outside `/etc/pve` and reads
those using `PVE::Tools::file_get_contents`. `compile` (line 4205) contains a
`vmdata` test-directory path that reads cluster, host and VM firewall fixtures.
These are promising native isolation interfaces, not yet a verified complete
validation method. Their context inputs and diagnostic behaviour still need
inspection and tests; do not infer that the CLI exposes the same capability.

`sudo -n /usr/sbin/pct config 105` still requires a password. Root SSH rejected
the current key in the preceding access check. The guest's `.local` name also
failed resolution in that check. Guest identity, addresses, current firewall,
backend runtime state and recovery commands remain unverified.

## Next access needed

Elevated read access on tob-proxmox to inspect 105's config/status, existing
firewall configuration and active rules, and to exercise isolated native
validation. No live firewall change is needed for this investigation. Actual
mutation and connection testing follow only after the safe mechanism and
recovery steps are verified.

## Privileged inspection supplied by Rog

105 is stopped, hostname tob-test-lxc, unprivileged Debian, with one NIC:

```text
net0: name=eth0,bridge=vmbr0,firewall=1,hwaddr=BC:24:11:68:9F:3B,ip=dhcp,type=veth
```

There is no `/etc/pve/firewall/105.fw`. The NIC flag is already enabled, so
publishing an enabled candidate is itself an activation point once the guest
is running; enabling the NIC later cannot be treated as the sole barrier.
DHCP must continue to work. The stopped state explains why a fresh guest
`.local` lookup may fail; discovery is not yet diagnosed as broken.

The existing DROP/ACCEPT defaults and SSH/WebUI/mDNS rules are in
`/etc/pve/firewall/cluster.fw`. There is no local `host.fw`. Both files/scopes
remain outside mutation scope.

Both pve-firewall and proxmox-firewall report active/running, also confirmed
through read-only systemctl show. Service state alone did not identify the enforcing backend; the subsequent
active-rule evidence below resolves this. Do not stop either service.

The installed `PVE::Firewall::compile` accepts a vmdata argument containing
`testdir`, loads cluster.fw/host.fw/guest files from there, then generates IPv4,
IPv6, ebtables and ipset rule structures. This confirms a native test-mode
entry point exists; it still requires an actual fixture exercise with the
correct VM data and error detection before use in the command.

## Active-rule evidence supplied by Rog

The follow-up inspection shows no nftables tables and active IPv4 iptables
INPUT/FORWARD/OUTPUT jumps to PVEFW chains. PVEFW-HOST-IN contains the expected
LAN SSH, WebUI and mDNS rules followed by DROP. This confirms the legacy
iptables backend for this investigation despite both services running.
No further backend clarification is required.

Only the first 80 lines of iptables-save were supplied; this is backend
confirmation, not a complete guest ruleset audit. The generic PVEFW-Drop
chain includes SMB/NetBIOS drops, but that does not invalidate an explicit
TCP 445 allow earlier in a guest's processing path. Verify generated rule
ordering during native compiler tests, without changing host rules.

## Native validator implementation and fixture verification

Implemented `scripts/lxc-firewall-validate`, which calls the installed native
compiler in test-directory mode, checks for expected enabled guest chains in
both IP families and rejects all parser/generator warnings. It only returns
compiled rule JSON and never invokes firewall update or kernel rule commands.

Ran `tests/test_lxc_firewall_native.pl` over SSH as rog on Proxmox: all 12
assertions passed. Covered valid scoped SSH/SMB rules, ordering before the
standard drop chain, DHCP replies, no IPv6 TCP service allows, malformed
ports/sources/trailing syntax, disabled guest policy and disabled Datacenter.
This used disposable fixtures, not copies of the protected live configuration.

Prepared `scripts/check-lxc-firewall` to copy real local configuration into an
auto-cleaned temporary snapshot and validate all four candidate service
profiles for 105. It requires root only to read the live context. It performs
no live config mutation, guest start or service action. Both Perl scripts pass
syntax checking on the installed Proxmox host.

Reviewed files are staged on the host at:
`/tmp/tob-firewall-review.8nheDc/scripts/`.
Next user-run command on Proxmox:

```sh
sudo perl /tmp/tob-firewall-review.8nheDc/scripts/check-lxc-firewall 105
```

Live-context validation, discovery, actual application/recovery and connection
tests remain outstanding. This preflight still validates service candidates;
it does not claim mDNS rules have been finalized.

## Real-context preflight supplied by Rog

Existing policy compiled with 0 IPv4/IPv6 guest inbound rules. ssh-only
compiled with 5 IPv4 and 8 IPv6 inbound rules, application and lan-smb each
with 6 IPv4 and 8 IPv6 inbound rules, unrestricted with zero in both families.
All passed. These counts include native protocol rules; the IPv6 rules do
not represent IPv6 service-port allowances.

105 was started by Rog for baseline connectivity. Its name now resolves and
SSH advertises an ED25519 key, but first-connection host-key verification is
pending Rog's host-side fingerprint. No guest firewall has been applied yet.

Implemented the apply adapter and transaction module. Local transaction tests
cover failure and recovery paths; native verification now includes mDNS rule
compilation and returned signatures (14 assertions). Exact live apply and
connectivity checks remain pending.

## Apply-path checkpoint

Implemented `scripts/lxc-firewall-apply` and a pure transaction module, wired
through the existing entry point. Current deployment remains restricted to
105 / tob-test-lxc and pve-firewall 6.0.4. Validation uses actual context
snapshots; publication uses Proxmox's native atomic file writer; NIC changes
use pct. Running-guest convergence compares native PVE chain signatures in
IPv4/IPv6 kernel rules and checks their bridge hooks. No update/reload service
call or direct kernel rule mutation is used.

28 local transaction assertions pass, plus preview and existing repository
suites. Both Perl and shell syntax checks pass on Proxmox for the staged
bundle. Native compiler tests pass 14 assertions including LAN mDNS and native
signatures. Live apply, rollback on Proxmox and fresh-connection checks are
still NOT RUN.

The reviewed apply bundle is staged at:
`/tmp/tob-firewall-apply.pI7HDH/scripts/` on tob-proxmox.
Next steps: obtain 105's SSH fingerprint, capture exact live dry-run, verify
baseline discovery/SSH/outbound connectivity, then apply and test with the
recorded host-side recovery command available.
