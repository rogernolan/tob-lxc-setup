#!/usr/bin/env bash
set -Eeuo pipefail
REPO=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT
mkdir -p "$FIXTURE/pve/lxc" "$FIXTURE/pve/firewall" "$FIXTURE/bin"
fail() { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
[[ -f "$REPO/scripts/configure-lxc-firewall" ]] || fail 'firewall command is missing'
sed "s|^pve_root=/etc/pve$|pve_root=$FIXTURE/pve|" \
  "$REPO/scripts/configure-lxc-firewall" > "$FIXTURE/command"
cat > "$FIXTURE/bin/id" <<'EOF'
#!/bin/sh
printf '0\n'
EOF
cat > "$FIXTURE/bin/pct" <<'EOF'
#!/bin/sh
[ "$1" = config ] && [ "$2" = 105 ] || exit 1
cat "$GUEST_FIXTURE"
EOF
chmod +x "$FIXTURE/bin/"*
export PATH="$FIXTURE/bin:$PATH" GUEST_FIXTURE="$FIXTURE/pve/lxc/105.conf"
reset_guest() {
  printf '%s\n' 'hostname: tob-test-lxc' \
    'net1: name=eth0,bridge=vmbr0,hwaddr=AA:BB:CC:DD:EE:FF,ip=192.168.68.90/22,firewall=0' > "$GUEST_FIXTURE"
  rm -f "$FIXTURE/pve/firewall/105.fw"
}
run() { bash "$FIXTURE/command" "$@" > "$FIXTURE/out" 2>&1; }
contains() { grep -Fq -- "$1" "$FIXTURE/out" || fail "missing output: $1"; }
reject() {
  local message=$1; shift
  if run "$@"; then fail "accepted invalid invocation: $*"; fi
  contains "$message"
}
reset_guest
run --help || fail 'help failed'
contains 'Usage:'
reject 'VMID' abc ssh-only --dry-run
reject 'VMID' 0 ssh-only --dry-run
reject 'unknown profile' 105 made-up --dry-run
reject 'requires --port' 105 application --dry-run
for port in 0 65536 -1 abc 80-90 999999999999999999999999; do
  reject 'port' 105 application --port "$port" --dry-run
done
reject 'requires a value' 105 application --port
reject 'only valid for application' 105 ssh-only --port 80 --dry-run
reject 'unknown option' 105 ssh-only --force --dry-run
reject 'local LXC' 106 ssh-only --dry-run
run 105 ssh-only --dry-run || fail 'SSH preview failed'
contains 'NIC: net1'
contains 'Current NIC firewall: 0'
contains 'IN ACCEPT -source 192.168.68.0/22 -p tcp -dport 22'
contains 'IN ACCEPT -source fdbc:54c7:7b7e:4bdd::/64 -p tcp -dport 22'
contains 'not natively validated'
contains 'dhcp: 1'
contains 'IN ACCEPT -source 192.168.68.0/22 -p udp -dport 5353'
cp "$FIXTURE/out" "$FIXTURE/first"
run 105 ssh-only --dry-run
cmp -s "$FIXTURE/first" "$FIXTURE/out" || fail 'preview not deterministic'
run 105 application --port 9090 --port 08080 --port 8080 --dry-run
[[ $(grep -c -- '-dport 8080$' "$FIXTURE/out") = 2 ]] || fail 'expected one rule per address family'
[[ $(grep -- '-source 192.168.68.0/22 -p tcp -dport' "$FIXTURE/out" | sed 's/.*-dport //') = $'22\n8080\n9090' ]] || fail 'port ordering'
[[ $(grep -- '-source fdbc:54c7:7b7e:4bdd::/64 -p tcp -dport' "$FIXTURE/out" | sed 's/.*-dport //') = $'22\n8080\n9090' ]] || fail 'IPv6 application parity'
run 105 lan-smb --dry-run
contains '-dport 445'
contains 'IN ACCEPT -source fdbc:54c7:7b7e:4bdd::/64 -p tcp -dport 445'
if grep -Eq -- '-dport (137|138|139)|fe80::|SMB\(' "$FIXTURE/out"; then fail 'overbroad SMB policy'; fi
run 105 unrestricted --dry-run
contains 'enable: 0'
contains 'no inbound isolation'
contains 'NIC action: unchanged'
printf 'net2: name=eth1,bridge=vmbr0\n' >> "$GUEST_FIXTURE"
reject 'exactly one' 105 ssh-only --dry-run
reset_guest
printf 'hostname: tob-test-lxc\n' > "$GUEST_FIXTURE"
reject 'exactly one' 105 ssh-only --dry-run
reset_guest
sed 's/,bridge=vmbr0//' "$GUEST_FIXTURE" > "$FIXTURE/config"
cp "$FIXTURE/config" "$GUEST_FIXTURE"
reject 'bridge' 105 ssh-only --dry-run
reset_guest
printf 'lock: migrate\n' >> "$GUEST_FIXTURE"
reject 'locked' 105 ssh-only --dry-run
reset_guest
printf '[OPTIONS]\nenable: 1\n' > "$FIXTURE/pve/firewall/105.fw"
reject 'unmanaged' 105 ssh-only --dry-run
printf '# Managed by tob-lxc-setup configure-lxc-firewall\n# Format: 99\n' > "$FIXTURE/pve/firewall/105.fw"
reject 'format' 105 ssh-only --dry-run
printf '# Managed by tob-lxc-setup configure-lxc-firewall\n# Format: 1\n' > "$FIXTURE/pve/firewall/105.fw"
cp -R "$FIXTURE/pve" "$FIXTURE/before"
run 105 ssh-only --dry-run
contains 'Existing policy: managed'
diff -r "$FIXTURE/before" "$FIXTURE/pve" || fail 'dry-run changed state'
reject 'apply helper is unavailable' 105 ssh-only
diff -r "$FIXTURE/before" "$FIXTURE/pve" || fail 'unimplemented apply changed state'
printf 'PASS: firewall preview tests\n'
