#!/usr/bin/env bash
set -Eeuo pipefail
repo=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/bin" "$tmp/payload/lib/TOB"
# Relocate installation only in this fixture; production has no prefix override.
sed "s|prefix=/usr/local|prefix=$tmp/installed|" "$repo/scripts/install-lxc-firewall" > "$tmp/installer"
printf '#!/bin/sh\necho 0\n' > "$tmp/bin/id"
printf '#!/bin/sh\nexit 0\n' > "$tmp/bin/perl"
chmod +x "$tmp/bin/"*
export PATH="$tmp/bin:$PATH"
for name in configure-lxc-firewall lxc-firewall-apply lxc-firewall-validate; do
  printf '#!/bin/sh\nprintf "invoked:%%s\\n" "$*"\n' > "$tmp/payload/$name"
done
for name in LXCFirewallTransaction LXCFirewallTarget; do
  printf '1;\n' > "$tmp/payload/lib/TOB/$name.pm"
done
bash "$tmp/installer" --payload-dir "$tmp/payload" > "$tmp/output"
! grep -q invoked "$tmp/output"
"$tmp/installed/sbin/configure-lxc-firewall" 107 development > "$tmp/output"
grep -q 'invoked:107 development' "$tmp/output"
cp "$tmp/installed/sbin/configure-lxc-firewall" "$tmp/original"
rm "$tmp/payload/lib/TOB/LXCFirewallTarget.pm"
if bash "$tmp/installer" --payload-dir "$tmp/payload" > "$tmp/output" 2>&1; then
  echo 'FAIL: incomplete bundle accepted'; exit 1
fi
cmp "$tmp/original" "$tmp/installed/sbin/configure-lxc-firewall"
printf '1;\n' > "$tmp/payload/lib/TOB/LXCFirewallTarget.pm"
bash "$tmp/installer" --payload-dir "$tmp/payload" -- 105 ssh-only --dry-run > "$tmp/output"
grep -q 'invoked:105 ssh-only --dry-run' "$tmp/output"
if bash "$tmp/installer" --ref main > "$tmp/output" 2>&1; then
  echo 'FAIL: mutable ref accepted'; exit 1
fi
# Failed downloads and syntax errors must preserve the installed command.
cp "$tmp/installed/sbin/configure-lxc-firewall" "$tmp/original"
cat > "$tmp/bin/curl" <<'STUB'
#!/bin/bash
url=${!#}
case "$url" in
  */0123456789012345678901234567890123456789/scripts/*) ;;
  *) exit 9 ;;
esac
file=${url#*/scripts/}
[[ $file != "${FAIL_FILE:-}" ]] || exit 22
cat "$FIXTURE_PAYLOAD/$file"
STUB
chmod +x "$tmp/bin/curl"
export FIXTURE_PAYLOAD="$tmp/payload" FAIL_FILE=lib/TOB/LXCFirewallTarget.pm
if bash "$tmp/installer" --ref 0123456789012345678901234567890123456789 > "$tmp/output" 2>&1; then
  echo 'FAIL: failed download accepted'; exit 1
fi
cmp "$tmp/original" "$tmp/installed/sbin/configure-lxc-firewall"
unset FAIL_FILE
bash "$tmp/installer" --ref 0123456789012345678901234567890123456789 > "$tmp/output"
"$tmp/installed/sbin/configure-lxc-firewall" 104 lan-smb --service-source gateway > "$tmp/output"
grep -q 'invoked:104 lan-smb --service-source gateway' "$tmp/output"
cp "$tmp/installed/sbin/configure-lxc-firewall" "$tmp/original"
printf 'if\n' > "$tmp/payload/configure-lxc-firewall"
if bash "$tmp/installer" --payload-dir "$tmp/payload" > "$tmp/output" 2>&1; then
  echo 'FAIL: invalid shell accepted'; exit 1
fi
cmp "$tmp/original" "$tmp/installed/sbin/configure-lxc-firewall"
# Earlier launchers remain bound to their complete release after an upgrade.
bash "$tmp/original" 105 ssh-only > "$tmp/output"
grep -q 'invoked:105 ssh-only' "$tmp/output"
printf 'PASS: firewall installer tests\n' 
