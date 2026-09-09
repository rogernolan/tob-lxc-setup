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

## 2026-09-09 baseline and dry-run

Rog supplied the exact ssh-only dry-run: 105/tob-test-lxc, net0 already
firewall=1, no existing guest policy, inbound DROP/outbound ACCEPT, dhcp=1,
LAN TCP 22 and LAN UDP 5353; NIC unchanged. No mutation occurred.

Verified scanned SSH ED25519 key against Rog's host-side fingerprint:
`SHA256:iM2zLqD1BD7/tpLp9tb7JwJ7/x9vXPIscJrWriJU2Fo`.
A task-specific known-hosts file is at `/tmp/tob-105-known-hosts` on the Mac.
Guest SSH as rog succeeds with strict checking; sudo inside the guest still
requires a password and has not been needed.

Guest addresses observed:
- IPv4: 192.168.68.85/22
- ULA IPv6: fdbc:54c7:7b7e:4bdd:be24:11ff:fe68:9f3b/64
- Link-local IPv6: fe80::be24:11ff:fe68:9f3b/64

Ordinary .local SSH selected ULA IPv6, from the Mac's address in the same
/64. This is NOT link-local service access; do not silently add a fe80 rule
or a routed IPv6 allow. IPv4-forced SSH succeeded, but its observed source
was 192.168.68.71, so this check exercised the SNATed gateway path, not a
proved direct LAN IPv4 path. Avahi is active; DNS lookup and outbound HTTPS
(HTTP 200 from deb.debian.org) work.

A temporary unprivileged IPv4 HTTP listener is running on port 18080 in 105,
serving only `firewall-test-105`, with PID/log in
`/tmp/tob-firewall-listener.nOAwsq/`. Remove it after integration testing.
The baseline probe from the Mac and gateway should be repeated after apply
while confirming the listener remains running. Ordinary .local fallback
behaviour still needs a post-apply test before considering any IPv6 exception.

## First live ssh-only apply and connection checks

Rog ran the staged apply for 105. It reported matching active IPv4/IPv6 guest
chain signatures and saved `/var/backups/tob-lxc-firewall/105/previous.json`.

Fresh post-apply checks from the Mac:
- IPv4 SSH succeeded, observed source 192.168.68.71 (gateway SNAT).
- Guest DNS lookup succeeded and HTTPS to deb.debian.org returned 200.
- Port 18080 timed out from both the Mac and gateway, while `ss -lnt` inside
  105 confirmed the IPv4 listener was still running. Baseline probes had
  succeeded before apply, so this is a meaningful filtering check.
- Ordinary `.local` SSH succeeded via IPv4 after the explicit five-second
  ConnectTimeout on the preferred ULA IPv6 address. This is not proof of
  delay-free default SSH behaviour; without that option the wait can differ.

No IPv6 service exception was added. Idempotent live rerun, restart persistence,
application-profile transition and cleanup are still outstanding. Direct LAN
IPv4 separate from the SNATed path and fresh uncached mDNS require additional
verification; do not count the current SNATed probes as direct LAN evidence.

## Live idempotence and application transition

Rog reran ssh-only: active signatures verified and command reported unchanged.
He then applied application --port 18080: signatures verified and command
reported applied. Fresh HTTP probes from the Mac and gateway both returned
`firewall-test-105`; fresh IPv4 SSH also succeeded. The same listener was
blocked under ssh-only and allowed under application, as intended.
Next: restore ssh-only, prove the live listener is blocked again, then restart
105 and verify persistence and cleanup.

## Reboot persistence and cleanup (2026-09-09)

After restoring ssh-only, Rog supplied active-signature confirmation and a
port-18080 timeout. He clarified that the first apparent restart had not been
performed; it was not counted as persistence evidence. After the explicit
`pct reboot 105`, the guest boot ID changed from
`febbd380-69f2-44d1-b7ba-178f69f5dc3a` to
`ea290737-a288-4609-8c91-3ae936190d28` and start time was 07:16:13 guest time.

Fresh post-reboot IPv4 SSH succeeded (source 192.168.68.71), DHCP retained
192.168.68.85/22, DNS worked, outbound HTTPS returned 200 and Avahi was active.
A NEW unprivileged listener on 18080 returned `firewall-test-105` to a guest
loopback probe, but timed out from both Mac and gateway. This verifies the
inbound restriction after reboot rather than mistaking a stopped listener
for successful firewalling.

Ordinary .local SSH with ConnectTimeout=5 again succeeded through IPv4 after
about five seconds. IPv6 address preference remains a usability limitation;
no ULA or link-local service allowance was added. Tests without an explicit
connect timeout and fresh uncached mDNS were not performed.

Both test directories and the restarted listener were removed. 105 is left
on ssh-only. No production LXC or host/Datacenter firewall policy was changed.
Unrestricted and SMB protocol/file-operation tests were not run live; they
have native compiler coverage only. A separately proved direct-LAN IPv4 test
is not claimed: the Mac's observed IPv4 path was SNATed by the gateway.

## Approved dual-stack follow-up

Rog approved identical service access for the IPv4 LAN subnet and the observed
ULA IPv6 /64. Renderer and tests now include both source rules for every
selected service port (SSH, application and SMB); no blanket external IPv6 or
link-local trust was added. This supersedes the earlier IPv4-only limitation
and intermediate SSH-only exception. Local preview tests and 19 native
compiler assertions pass. Live verification is pending apply of the new bundle:
`/tmp/tob-firewall-dualstack.dVNMlT/scripts/` on Proxmox.

## Dual-stack SSH live verification

Rog applied the dual-stack ssh-only bundle to 105; it reported matching active
IPv4/IPv6 guest chain signatures. Fresh SSH checks on 2026-09-09:

- Ordinary `.local`: success in 0.53 seconds, using ULA IPv6 directly.
- IPv6-forced: success in 0.18 seconds.
- IPv4-forced: success in 0.18 seconds, through gateway SNAT.

Observed IPv6 client source was
`fdbc:54c7:7b7e:4bdd:187f:ea46:e3bc:5850`; destination was
`fdbc:54c7:7b7e:4bdd:be24:11ff:fe68:9f3b`. The earlier five-second fallback
was absent. Timings are individual connection measurements, not benchmarks.
The IPv6 change was applied after the recorded reboot, so dual-stack reboot
persistence has not separately been tested. Application/SMB IPv6 rule generation
has native test coverage, but live service tests were IPv4-only.

## Release verification: 2026-09-09

The apply adapter now accepts any eligible local LXC and its selected single
NIC; no production guest was changed. New gateway-only service profiles retain
LAN IPv4/IPv6 SSH and constrain other TCP service access to 192.168.68.71.

- All local setup, Caddy, firewall preview and installer suites passed.
- Transaction tests passed 28 assertions; generic target tests passed six.
- Proxmox native compiler tests passed 29 assertions, including gateway-only
  SMB/development, generic VMID with net3, and a disabled NIC baseline.
- The complete apply helper passed Perl syntax checking on Proxmox.
- Independent code review reported no material findings.
- Installer fixture tests cover complete install, explicit invocation, pinned
  downloads, incomplete bundles, failed downloads, syntax failure and preserving
  the previously installed command. A root installation on Proxmox has not yet
  been run; native tests and staging were unprivileged and read-only to policy.

Remaining live coverage: IPv6 application traffic, Samba file operations,
unrestricted transition, activation of a previously disabled NIC, and the new
gateway-only profiles. The previously recorded 105 SSH, discovery, application
allow/block, idempotence and reboot results remain the available runtime evidence.
