# SSH Authentication Hardening Design

## Goal

Make SSH access key-only when this setup has successfully installed at least one accepted public key for `rog`, while avoiding a lockout when no key is available.

## Behavior

- Remove the `--no-ssh-key` option and always obtain SSH public keys from GitHub or the explicitly supplied local key file.
- Install and deduplicate accepted public keys in `/home/rog/.ssh/authorized_keys`.
- Require at least one accepted key after installation. If none exists, fail before changing SSH authentication policy.
- Before applying the policy, print a warning that password and unused authentication methods are being disabled.
- Write an SSH daemon drop-in that enables public-key authentication and disables password, keyboard-interactive/challenge-response, GSSAPI/Kerberos, and empty-password authentication.
- Validate the effective drop-in with `sshd -t` before installing it; preserve unrelated SSH configuration.
- Update documentation and fixture tests to cover the mandatory key flow, hardening settings, validation, idempotence, and no-key failure safety.

## Safety

The setup must never disable password authentication unless at least one accepted public key is present. A missing, empty, or invalid key source causes failure without installing the hardening drop-in.

## Verification

Run `bash -n setup.sh tests/test_setup.sh` and `bash tests/test_setup.sh`.
