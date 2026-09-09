# Firewall installer and PR plan

Goal: publish the reviewed guest firewall tooling with a pinned one-shot installer.

The installer accepts an immutable Git commit or a reviewed local scripts directory.
It stages an explicit allowlist in a private release directory, checks syntax, then
atomically replaces the launcher. Existing launches keep using their complete
release. Installation alone does not change guest policy; arguments following
`--` explicitly invoke the installed command. Keep previous releases for recovery.

- [ ] Test complete installation, invocation, failed downloads and invalid bundles.
- [ ] Implement scripts/install-lxc-firewall and its fixture tests.
- [ ] Run local suites and native compiler tests on Proxmox without live mutation.
- [ ] Document pinned curl command, rollout exclusions and remaining live checks.
- [ ] Review diff, commit, push and create PR. Do not merge or change production guests.
