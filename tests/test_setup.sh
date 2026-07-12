#!/usr/bin/env bash
set -Eeuo pipefail

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
SETUP_SCRIPT="$SCRIPT_DIR/setup.sh"

fail() {
    printf 'FAIL: %s\n' "$1" >&2
    exit 1
}

assert_file_exists() {
    [[ -e "$1" ]] || fail "expected file: $1"
}

assert_file_not_exists() {
    [[ ! -e "$1" ]] || fail "did not expect file: $1"
}

assert_contains() {
    grep -Fq -- "$1" "$2" || fail "expected '$1' in $2"
}

assert_count() {
    local expected=$1 pattern=$2 file=$3 actual
    actual=$(grep -Fc -- "$pattern" "$file" || true)
    [[ "$actual" -eq "$expected" ]] || fail "expected $expected occurrences of '$pattern' in $file, got $actual"
}

make_fixture() {
    FIXTURE=$(mktemp -d)
    ROOT="$FIXTURE/root"
    BIN="$FIXTURE/bin"
    mkdir -p "$ROOT/etc" "$ROOT/home" "$ROOT/tmp" "$ROOT/var/lib" "$BIN"
    cat > "$ROOT/etc/os-release" <<'EOF'
ID=debian
NAME="Debian GNU/Linux"
EOF
    : > "$ROOT/etc/passwd"
    printf 'sudo:x:27:\n' > "$ROOT/etc/group"
    : > "$FIXTURE/calls"

    cat > "$BIN/apt-get" <<'EOF'
#!/usr/bin/env bash
printf 'apt-get %s\n' "$*" >> "$TEST_CALLS"
EOF
    cat > "$BIN/npm" <<'EOF'
#!/usr/bin/env bash
printf 'npm %s\n' "$*" >> "$TEST_CALLS"
cat > "$TEST_BIN/codex" <<'CODEX'
#!/usr/bin/env bash
printf 'codex-cli test-version\n'
CODEX
chmod +x "$TEST_BIN/codex"
EOF
    cat > "$BIN/useradd" <<'EOF'
#!/usr/bin/env bash
printf 'useradd %s\n' "$*" >> "$TEST_CALLS"
printf 'rog:x:1000:1000::/home/rog:/bin/bash\n' >> "$TEST_ROOT/etc/passwd"
mkdir -p "$TEST_ROOT/home/rog"
EOF
cat > "$BIN/usermod" <<'EOF'
#!/usr/bin/env bash
printf 'usermod %s\n' "$*" >> "$TEST_CALLS"
awk -F: 'BEGIN { OFS = ":" } $1 == "sudo" { $4 = "rog" } { print }' "$TEST_ROOT/etc/group" > "$TEST_ROOT/etc/group.tmp"
mv "$TEST_ROOT/etc/group.tmp" "$TEST_ROOT/etc/group"
EOF
    cat > "$BIN/visudo" <<'EOF'
#!/usr/bin/env bash
printf 'visudo %s\n' "$*" >> "$TEST_CALLS"
exit 0
EOF
    cat > "$BIN/systemctl" <<'EOF'
#!/usr/bin/env bash
printf 'systemctl %s\n' "$*" >> "$TEST_CALLS"
EOF
    cat > "$BIN/chown" <<'EOF'
#!/usr/bin/env bash
printf 'chown %s\n' "$*" >> "$TEST_CALLS"
EOF
    cat > "$BIN/chmod" <<'EOF'
#!/usr/bin/env bash
printf 'chmod %s\n' "$*" >> "$TEST_CALLS"
/bin/chmod "$@"
EOF
    cat > "$BIN/curl" <<'EOF'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >> "$TEST_CALLS"
if [[ "$*" == *'.keys'* ]]; then
    printf '%s\n' "$TEST_KEYS"
else
    cat "$TEST_GUIDANCE"
fi
EOF
    cat > "$BIN/id" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == "-u" ]]; then
    printf '0\n'
else
    exit 0
fi
EOF
    chmod +x "$BIN"/*
}

run_setup() {
    TEST_ROOT="$ROOT" TEST_BIN="$BIN" TEST_CALLS="$FIXTURE/calls" TEST_KEYS="$KEYS" TEST_GUIDANCE="$SCRIPT_DIR/files/rog/AGENTS.md" \
        PATH="$BIN:$PATH" SETUP_PATH_UNUSED=1 SETUP_ROOT="$ROOT" SETUP_TEST_MODE=1 SETUP_TEST_PATH="$BIN" \
        SETUP_PAYLOAD_DIR="${TEST_PAYLOAD_DIR:-$SCRIPT_DIR/files}" "$SETUP_SCRIPT" "$@"
}

test_help() {
    "$SETUP_SCRIPT" --help >/dev/null
}

test_rejects_unsupported_os() {
    make_fixture
    printf 'ID=alpine\n' > "$ROOT/etc/os-release"
    if TEST_ROOT="$ROOT" TEST_BIN="$BIN" TEST_CALLS="$FIXTURE/calls" PATH="$BIN:$PATH" SETUP_ROOT="$ROOT" SETUP_TEST_MODE=1 SETUP_TEST_PATH="$BIN" "$SETUP_SCRIPT" --dry-run; then
        fail 'unsupported OS was accepted'
    fi
    assert_file_not_exists "$ROOT/etc/sudoers.d/rog"
    [[ ! -s "$FIXTURE/calls" ]] || fail 'commands ran before OS rejection'
    rm -rf "$FIXTURE"
}

test_dry_run_is_non_mutating() {
    make_fixture
    TEST_ROOT="$ROOT" TEST_BIN="$BIN" TEST_CALLS="$FIXTURE/calls" PATH="$BIN:$PATH" SETUP_ROOT="$ROOT" SETUP_TEST_MODE=1 SETUP_TEST_PATH="$BIN" "$SETUP_SCRIPT" --dry-run --no-ssh-key
    assert_file_not_exists "$ROOT/etc/sudoers.d/rog"
    assert_file_not_exists "$ROOT/home/rog/AGENTS.md"
    [[ ! -s "$FIXTURE/calls" ]] || fail 'dry-run executed mutating commands'
    rm -rf "$FIXTURE"
}

test_setup_is_idempotent() {
    make_fixture
    KEYS='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA rog@test'
    key_file="$FIXTURE/rog.pub"
    printf '%s\n%s\n' "$KEYS" "$KEYS" > "$key_file"

    run_setup --ssh-public-key-file "$key_file"
    run_setup --ssh-public-key-file "$key_file"

    assert_file_exists "$ROOT/etc/sudoers.d/rog"
    assert_contains 'rog ALL=(ALL:ALL) ALL' "$ROOT/etc/sudoers.d/rog"
    assert_file_exists "$ROOT/home/rog/.ssh/authorized_keys"
    assert_count 1 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA rog@test' "$ROOT/home/rog/.ssh/authorized_keys"
    assert_file_exists "$ROOT/home/rog/AGENTS.md"
    assert_contains 'practical homelab sysadmin assistant' "$ROOT/home/rog/AGENTS.md"
    assert_contains 'apt-get update' "$FIXTURE/calls"
    assert_contains 'npm install --global @openai/codex' "$FIXTURE/calls"
    assert_count 1 'usermod --append --groups sudo rog' "$FIXTURE/calls"
    rm -rf "$FIXTURE"
}

test_bootstrap_fetches_missing_payload() {
    make_fixture
    KEYS='ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA rog@test'
    TEST_PAYLOAD_DIR="$FIXTURE/missing" run_setup
    assert_file_exists "$ROOT/home/rog/AGENTS.md"
    assert_file_exists "$ROOT/home/rog/.ssh/authorized_keys"
    assert_count 1 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA rog@test' "$ROOT/home/rog/.ssh/authorized_keys"
    assert_contains 'raw.githubusercontent.com/rogernolan/tob-lxc-setup/main/files/rog/AGENTS.md' "$FIXTURE/calls"
    rm -rf "$FIXTURE"
}

test_help
test_rejects_unsupported_os
test_dry_run_is_non_mutating
test_setup_is_idempotent
test_bootstrap_fetches_missing_payload
printf 'PASS: setup tests\n'
