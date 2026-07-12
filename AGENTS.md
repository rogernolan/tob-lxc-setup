# AGENTS.md

## Mission

Maintain a small, dependable setup tool for Rog's Debian and Ubuntu Proxmox LXC hosts. Prefer straightforward shell and standard distribution tools. Optimize for safe, repeatable operations and quick recovery from partial runs.

## Operating principles

- Be expedient on routine, reversible work; do not trade away security for convenience.
- Keep changes narrowly scoped. Avoid introducing Ansible, third-party installers, or extra services unless the task explicitly requires them.
- Make every setup action idempotent: rerunning the script must converge without duplicate users, groups, keys, packages, sudo rules, or service actions.
- Fail early on unsupported operating systems, missing privileges, invalid input, unavailable dependencies, and unsafe assumptions.
- Preserve existing host configuration unless the task explicitly authorizes changing it. In particular, do not overwrite SSH configuration, firewall policy, hostnames, locale, timezone, or user data.
- Explain operationally significant assumptions in `README.md` and in the script's help output.

## Security requirements

- Never commit passwords, private keys, access tokens, API credentials, or machine-specific secrets.
- Treat public SSH keys as safe-to-publish, but validate key type and format before installing them.
- Never execute shell code fetched from the network. Network downloads must be limited to reviewed scripts or data, use HTTPS, fail closed, and be validated before use.
- Use least privilege. Run package and system changes as root only when required; keep generated sudo policy explicit, minimal, correctly owned, and validated with `visudo`.
- Quote shell variables, use `set -Eeuo pipefail`, use a predictable `PATH`, and clean up temporary files with traps.
- Do not log credentials, complete environment variables, private key material, or unnecessary personal data.
- Do not weaken SSH authentication or disable host protections as a convenience.

## Implementation conventions

- Target Debian and Ubuntu only unless the task expands the supported matrix.
- Prefer `apt-get` for scripts and make noninteractive behavior explicit.
- Detect commands, users, groups, services, and systemd availability rather than assuming them.
- Use dedicated files under `/etc/sudoers.d/` and `/etc/ssh/` when configuration is needed; preserve unrelated lines and permissions.
- Keep the main script readable through small functions with clear names and one responsibility.
- Use comments to explain why an operational or security decision exists, not what an obvious command does.

## Verification

Before reporting a change as complete:

1. Run `bash -n` on shell files.
2. Run the repository test suite and repeat idempotency-sensitive tests.
3. Run ShellCheck when available; fix real findings or document why a finding is safe.
4. Inspect `git diff --check` and `git status`.
5. For changes affecting live host behavior, state what was verified locally and what still requires a disposable LXC or manual host check.

Never claim a build, test, or setup run passed without fresh command output.

## Git workflow

- Use focused commits with imperative messages, for example `fix: avoid duplicate authorized keys`.
- Do not rewrite history, reset user changes, or delete unrelated files without explicit approval.
- Review the final diff before committing.
- Do not push or open a pull request unless Rog asks for publication.

## User-facing communication

- Lead with the operational outcome and call out anything Rog must do manually.
- Keep instructions copy/pasteable and include the exact target host, path, or command.
- Surface risk plainly when a shortcut involves remote code, privilege escalation, SSH access, or package changes.
