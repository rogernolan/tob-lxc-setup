#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
INSTALLER="$SCRIPT_DIR/scripts/install-caddy-host"
FIXTURE=$(mktemp -d)
trap 'rm -rf "$FIXTURE"' EXIT

ROOT="$FIXTURE/root"
BIN="$FIXTURE/bin"
PAYLOAD="$FIXTURE/payload"
DESTINATION="$ROOT/usr/local/sbin/add-caddy-host"
mkdir -p "$ROOT/usr/local/sbin" "$BIN"

fail() {
	printf 'FAIL: %s\n' "$1" >&2
	exit 1
}

assert_file_contains() {
	grep -Fq -- "$1" "$2" || fail "expected '$1' in $2"
}

assert_file_equals() {
	[[ "$(cat "$1")" == "$2" ]] || fail "unexpected content in $1"
}

assert_file_not_exists() {
	[[ ! -e "$1" ]] || fail "did not expect file: $1"
}

cat > "$BIN/id" <<'EOF'
#!/usr/bin/env bash
[[ "$1" == "-u" ]] && printf '0\n' || exit 1
EOF

cat > "$BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >> "$TEST_CURL_LOG"
if [[ ${TEST_CURL_FAIL:-0} == 1 ]]; then
	exit 22
fi
cat "$TEST_PAYLOAD"
EOF

cat > "$BIN/install" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail
src=
dest=
directory_mode=0
while (($#)); do
	case "$1" in
		-o|-g|-m) shift 2 ;;
		-d) directory_mode=1; shift ;;
		*)
			if [[ -z "$src" ]]; then src=$1; else dest=$1; fi
			shift
			;;
	esac
done
if ((directory_mode)); then
	mkdir -p "$src"
	exit 0
fi
cp "$src" "$dest"
chmod 0755 "$dest"
EOF

chmod +x "$BIN/id" "$BIN/curl" "$BIN/install"

make_test_installer() {
	local output=$1
	awk -v destination="$DESTINATION" '
		$0 == "destination=/usr/local/sbin/add-caddy-host" {
			print "destination=" destination
			next
		}
		{ print }
	' "$INSTALLER" > "$output"
	chmod +x "$output"
}

run_installer() {
	local installer=$1
	shift
	TEST_CURL_LOG="$FIXTURE/curl.log" TEST_PAYLOAD="$PAYLOAD" TMPDIR="$FIXTURE" \
		PATH="$BIN:$PATH" "$installer" "$@"
}

test_successful_install_forwards_arguments() {
	local installer="$FIXTURE/install-success.sh"
	cat > "$PAYLOAD" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$@" > "$TEST_ARGS"
EOF
	make_test_installer "$installer"
	TEST_ARGS="$FIXTURE/args" run_installer "$installer" --force \
		app.hatbat.net http://192.168.68.20:8080
	[[ -x "$DESTINATION" ]] || fail "installed command is not executable"
	assert_file_contains \
		'https://raw.githubusercontent.com/rogernolan/tob-lxc-setup/main/scripts/add-caddy-host' \
		"$FIXTURE/curl.log"
	assert_file_equals "$FIXTURE/args" '--force
app.hatbat.net
http://192.168.68.20:8080'
}

test_reviewed_local_payload_is_installed_without_redownload() {
	local installer="$FIXTURE/install-local.sh"
	cat > "$PAYLOAD" <<'EOF'
#!/bin/sh
set -eu
printf '%s\n' "$@" > "$TEST_ARGS"
EOF
	rm -f "$FIXTURE/curl.log"
	make_test_installer "$installer"
	TEST_ARGS="$FIXTURE/args" run_installer "$installer" --payload-file "$PAYLOAD" \
		app.hatbat.net http://192.168.68.20:8080
	assert_file_not_exists "$FIXTURE/curl.log"
	assert_file_equals "$FIXTURE/args" 'app.hatbat.net
http://192.168.68.20:8080'
}

test_invalid_payload_preserves_existing_command() {
	local installer="$FIXTURE/install-invalid.sh"
	printf 'OLD-CONTENT\n' > "$DESTINATION"
	printf 'not a shell script\n' > "$PAYLOAD"
	make_test_installer "$installer"
	if run_installer "$installer" app.hatbat.net http://192.168.68.20:8080; then
		fail "invalid payload was accepted"
	fi
	assert_file_equals "$DESTINATION" 'OLD-CONTENT'
}

test_download_failure_preserves_existing_command() {
	local installer="$FIXTURE/install-download-failure.sh"
	printf 'OLD-CONTENT\n' > "$DESTINATION"
	printf '#!/bin/sh\nset -eu\n' > "$PAYLOAD"
	make_test_installer "$installer"
	if TEST_CURL_FAIL=1 run_installer "$installer" app.hatbat.net http://192.168.68.20:8080; then
		fail "download failure was accepted"
	fi
	assert_file_equals "$DESTINATION" 'OLD-CONTENT'
}

test_successful_install_forwards_arguments
test_reviewed_local_payload_is_installed_without_redownload
test_invalid_payload_preserves_existing_command
test_download_failure_preserves_existing_command
printf 'PASS: caddy remote installer tests\n'
