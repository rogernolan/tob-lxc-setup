# LXC Firewall Implementation Plan

**Goal:** Implement the approved `lxc-firewall-design.md`, keeping live tests on
105 and existing host/Datacenter rules unchanged.

**Architecture:** A standalone Bash command separates argument parsing, native
host inspection, deterministic profile rendering and transactional application.
Existing shell fixture tests exercise command behaviour without a Proxmox host.
The native validation/apply mechanism requires installed-version evidence before
its implementation; the first increment is explicitly preview-only.

## 1. CLI and preview

- [x] Add `tests/test_lxc_firewall.sh`, with temporary fixture roots and `pct`
  command stubs, following `tests/test_caddy_remote.sh`.
- [x] Demonstrate failure before adding `scripts/configure-lxc-firewall`.
- [x] Implement `parse_args`, `inspect_guest`, `render_policy` and `main`.
  `parse_args` produces VMID, profile, normalized ports and dry-run state;
  `inspect_guest` supplies hostname, NIC/full property and file ownership;
  `render_policy` prints the deterministic service policy.
- [x] Check invalid VMIDs/profiles/options/ports, missing ports, deduplication,
  NIC ambiguity, missing/remote guests, unmanaged/versioned files, source
  restrictions, all four profiles and read-only preview. Keep apply disabled
  with an explicit nonzero diagnostic until tasks 2–3 are complete.
- [x] Run `bash -n scripts/configure-lxc-firewall tests/test_lxc_firewall.sh`
  and `bash tests/test_lxc_firewall.sh`; expect success.

## 2. Installed host investigation (requires elevated read access)

- [ ] Capture `pct config 105`, status, package versions, backend/service state
  and existing guest policy; confirm identity before any mutation.
- [ ] Inspect installed firewall parsing/compilation code and diagnostics.
  Prove an isolated candidate-validation method or safe activation barrier.
  Record the exact supported mechanism, error contract and relevant context.
- [ ] Observe fresh `.local` lookup and SSH traffic for 105. Finalize the
  minimal discovery rules; keep IPv4-only service sources unless evidence
  justifies a documented, narrow IPv6 exception.

## 3. Application and recovery

- [ ] Extend fixture tests with the verified native interface and failing
  cases for validation, file publication, NIC update and convergence.
- [ ] Implement lock, bounded recovery snapshot, candidate validation,
  state recheck, publication, NIC mutation and rollback in the approved order.
  Preserve the full NIC property; detect unresolved recovery and external edits.
- [ ] Add stopped-guest reporting, no-write idempotence and profile transition
  tests, including removal of stale allowed ports. Test invalid candidates
  without exposing production watched configuration to malformed rules.
- [ ] Verify failed operations preserve or recover the original state and
  never activate an unvalidated restrictive candidate.

## 4. Documentation and live verification

- [ ] Update README with host installation, usage, sources, direct SMB,
  preview, recovery and limitations. Remove preview-only status only once
  native validation/application are implemented and verified.
- [ ] Run all repository shell tests and syntax checks; review final diff.
- [ ] Record exact 105 dry-run and recovery steps, then perform the approved
  fresh-connection, listener, outbound, idempotence and restart tests on 105.
- [ ] Test application transitions and optional Samba fixture; distinguish
  transport checks from SMB file operations and explicitly report unrun tests.
- [ ] Leave 105 on `ssh-only`, clean up fixtures and record final state.

Do not claim the full feature complete from the preview increment. Host
inspection results determine the exact native calls in task 3; do not invent
an arbitrary-candidate validation option or deploy a guessed apply sequence.
