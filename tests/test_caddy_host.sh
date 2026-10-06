#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT
ROOT="$FIXTURE/root"
BIN="$FIXTURE/bin"
COMMAND="$FIXTURE/add-caddy-host"
mkdir -p "$BIN"

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	exit 1
}

assert_file_equals() {
	[[ "$(cat "$1")" == "$2" ]] || fail "unexpected content in $1"
}

# Redirect only the command's fixed system paths into the fake root.
awk -v root="$ROOT" '
	/^(caddyfile|sites_dir|ddns_env|ddns_command|lock_file|backup_dir)=\// {
		sub(/=\//, "=" root "/")
	}
	{ print }
' "$SCRIPT_DIR/scripts/add-caddy-host" > "$COMMAND"
chmod +x "$COMMAND"

cat > "$BIN/id" <<'EOF'
#!/bin/sh
[ "$1" = -u ] && printf '0\n'
EOF
cat > "$BIN/install" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
while (($#)); do
	case "$1" in
		-o|-g|-m) shift 2 ;;
		-d) shift ;;
		*) mkdir -p "$1"; shift ;;
	esac
done
EOF
cat > "$BIN/chown" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$BIN/flock" <<'EOF'
#!/bin/sh
exit 0
EOF
cat > "$BIN/curl" <<'EOF'
#!/bin/sh
printf 'curl %s\n' "$*" >> "$TEST_CALLS"
printf '200'
EOF
cat > "$BIN/caddy" <<'EOF'
#!/bin/sh
printf 'caddy %s\n' "$*" >> "$TEST_CALLS"
EOF
cat > "$BIN/systemctl" <<'EOF'
#!/bin/sh
printf 'systemctl %s\n' "$*" >> "$TEST_CALLS"
EOF
chmod +x "$BIN/"*

make_fixture() {
	rm -rf "$ROOT"
	mkdir -p "$ROOT/etc/caddy" "$ROOT/etc/cloudflare-ddns" \
		"$ROOT/usr/local/sbin" "$ROOT/run/lock"
	printf 'import %s/etc/caddy/sites-enabled/*.caddy\n' "$ROOT" > "$ROOT/etc/caddy/Caddyfile"
	cp "$ROOT/etc/caddy/Caddyfile" "$FIXTURE/original-caddyfile"
	printf "CF_ALIASES='existing.hatbat.net'\n" > "$ROOT/etc/cloudflare-ddns/cloudflare-ddns.env"
	cat > "$ROOT/usr/local/sbin/cloudflare-ddns" <<'EOF'
#!/bin/sh
. "$TEST_ROOT/etc/cloudflare-ddns/cloudflare-ddns.env"
printf '%s\n' "$CF_ALIASES" > "$TEST_DNS_ALIASES"
[ "${TEST_DNS_FAIL:-0}" != 1 ]
EOF
	chmod +x "$ROOT/usr/local/sbin/cloudflare-ddns"
	: > "$FIXTURE/calls"
	rm -f "$FIXTURE/dns-aliases"
}

run_command() {
	TEST_ROOT="$ROOT" TEST_CALLS="$FIXTURE/calls" TEST_DNS_ALIASES="$FIXTURE/dns-aliases" \
		PATH="$BIN:$PATH" "$COMMAND" "$@"
}

test_dns_accepts_arbitrary_domains() {
	local hostname expected
	for hostname in app.diffeng.co.uk diffeng.co.uk app.example.org example.org app.hatbat.net; do
		make_fixture
		run_command --update-dns "$hostname" http://192.168.68.20:8080 ||
			fail "DNS mode rejected $hostname"
		expected="$hostname {
	reverse_proxy http://192.168.68.20:8080
}"
		assert_file_equals "$ROOT/etc/caddy/sites-enabled/$hostname.caddy" "$expected"
		assert_file_equals "$FIXTURE/dns-aliases" "existing.hatbat.net $hostname"
		assert_file_equals "$ROOT/etc/cloudflare-ddns/cloudflare-ddns.env" \
			"CF_ALIASES='existing.hatbat.net $hostname'"
		run_command --update-dns "$hostname" http://192.168.68.20:8080
		assert_file_equals "$FIXTURE/dns-aliases" "existing.hatbat.net $hostname"
	done
}

test_arbitrary_domain_without_dns_configuration() {
	make_fixture
	rm -rf "$ROOT/etc/cloudflare-ddns" "$ROOT/usr/local/sbin/cloudflare-ddns"
	run_command app.diffeng.co.uk http://192.168.68.20:8080
	[[ -f "$ROOT/etc/caddy/sites-enabled/app.diffeng.co.uk.caddy" ]] || fail 'site was not written'
	[[ ! -e "$FIXTURE/dns-aliases" ]] || fail 'DNS was updated without --update-dns'
}

test_invalid_hostnames_are_rejected_before_changes() {
	local hostname
	for hostname in 'App.diffeng.co.uk' '-app.diffeng.co.uk' 'app..diffeng.co.uk' \
		'app.diffeng.co.uk/path' 'app.diffeng.co.uk;echo' '*.diffeng.co.uk' 'app diffeng.co.uk'; do
		make_fixture
		if run_command --update-dns -- "$hostname" http://192.168.68.20:8080 > "$FIXTURE/output" 2>&1; then
			fail "invalid hostname was accepted: $hostname"
		fi
		grep -Fq 'HOSTNAME must be a lowercase DNS name' "$FIXTURE/output" || fail 'wrong validation error'
		[[ ! -s "$FIXTURE/calls" ]] || fail 'invalid hostname reached external commands'
		cmp -s "$FIXTURE/original-caddyfile" "$ROOT/etc/caddy/Caddyfile" || fail 'Caddyfile changed'
		assert_file_equals "$ROOT/etc/cloudflare-ddns/cloudflare-ddns.env" "CF_ALIASES='existing.hatbat.net'"
	done
}

test_dns_failure_rolls_back_arbitrary_domain() {
	make_fixture
	if TEST_DNS_FAIL=1 run_command --update-dns app.diffeng.co.uk http://192.168.68.20:8080 \
		> "$FIXTURE/output" 2>&1; then
		fail 'DNS failure was accepted'
	fi
	grep -Fq 'Cloudflare DNS update failed' "$FIXTURE/output" || fail 'wrong DNS failure error'
	[[ ! -e "$ROOT/etc/caddy/sites-enabled/app.diffeng.co.uk.caddy" ]] || fail 'site was not rolled back'
	cmp -s "$FIXTURE/original-caddyfile" "$ROOT/etc/caddy/Caddyfile" || fail 'Caddyfile was not restored'
	assert_file_equals "$ROOT/etc/cloudflare-ddns/cloudflare-ddns.env" "CF_ALIASES='existing.hatbat.net'"
}

test_dns_accepts_arbitrary_domains
test_arbitrary_domain_without_dns_configuration
test_invalid_hostnames_are_rejected_before_changes
test_dns_failure_rolls_back_arbitrary_domain
printf 'PASS: caddy host domain tests\n'
