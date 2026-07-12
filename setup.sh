#!/usr/bin/env bash
set -Eeuo pipefail
IFS=$'\n\t'
PATH='/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin'
if [[ ${SETUP_TEST_MODE:-0} == 1 && -n ${SETUP_TEST_PATH:-} ]]; then
    PATH="$SETUP_TEST_PATH:$PATH"
fi
export PATH

SCRIPT_DIR=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
ROOT=${SETUP_ROOT:-/}
PAYLOAD_DIR=${SETUP_PAYLOAD_DIR:-"$SCRIPT_DIR/files"}
GITHUB_USER=rogernolan
SSH_PUBLIC_KEY_FILE=
NO_SSH_KEY=0
DRY_RUN=0
SUDOERS_TMP=
GUIDANCE_TMP=
PAYLOAD_URL=${SETUP_PAYLOAD_URL:-https://raw.githubusercontent.com/rogernolan/tob-lxc-setup/main/files/rog/AGENTS.md}

usage() {
    cat <<'EOF'
Usage: setup.sh [options]

Configure a Debian or Ubuntu LXC for Rog's homelab.

Options:
  --github-user USER          Fetch SSH keys from github.com/USER.keys
  --ssh-public-key-file FILE Install keys from a local public-key file
  --no-ssh-key                Do not configure an SSH key for rog
  --dry-run                   Show planned changes without mutating the host
  --help                      Show this help
EOF
}

die() {
    printf 'ERROR: %s\n' "$*" >&2
    exit 1
}

log() {
    printf 'INFO: %s\n' "$*"
}

root_path() {
    printf '%s%s' "$ROOT" "$1"
}

run() {
    if ((DRY_RUN)); then
        printf '+ %q' "$1"
        shift
        printf ' %q' "$@"
        printf '\n'
        return 0
    fi
    "$@"
}

run_env() {
    if ((DRY_RUN)); then
        printf '+ env'
        printf ' %q' "$@"
        printf '\n'
        return 0
    fi
    env "$@"
}

cleanup() {
    if [[ -n "$SUDOERS_TMP" && -e "$SUDOERS_TMP" ]]; then
        rm -f -- "$SUDOERS_TMP"
    fi
    if [[ -n "$GUIDANCE_TMP" && -e "$GUIDANCE_TMP" ]]; then
        rm -f -- "$GUIDANCE_TMP"
    fi
}
trap cleanup EXIT

parse_args() {
    while (($#)); do
        case "$1" in
            --github-user)
                (($# >= 2)) || die "--github-user requires a value"
                GITHUB_USER=$2
                shift 2
                ;;
            --ssh-public-key-file)
                (($# >= 2)) || die "--ssh-public-key-file requires a path"
                SSH_PUBLIC_KEY_FILE=$2
                shift 2
                ;;
            --no-ssh-key)
                NO_SSH_KEY=1
                shift
                ;;
            --dry-run)
                DRY_RUN=1
                shift
                ;;
            --help|-h)
                usage
                exit 0
                ;;
            *)
                die "unknown option: $1"
                ;;
        esac
    done
}

validate_environment() {
    if ((EUID != 0)) && [[ ${SETUP_TEST_MODE:-0} != 1 ]]; then
        die 'run this setup from a root shell'
    fi

    local os_release id
    os_release=$(root_path /etc/os-release)
    [[ -r "$os_release" ]] || die "missing $os_release"
    id=
    while IFS='=' read -r key value; do
        if [[ "$key" == ID ]]; then
            id=${value//\"/}
            break
        fi
    done < "$os_release"
    case "$id" in
        debian|ubuntu) ;;
        *) die "unsupported operating system: ${id:-unknown}; only Debian and Ubuntu are supported" ;;
    esac

    [[ "$GITHUB_USER" =~ ^[A-Za-z0-9-]+$ ]] || die 'GitHub username contains unsupported characters'
    if (( ! NO_SSH_KEY )) && [[ -n "$SSH_PUBLIC_KEY_FILE" && ! -r "$SSH_PUBLIC_KEY_FILE" ]]; then
        die "SSH public-key file is not readable: $SSH_PUBLIC_KEY_FILE"
    fi
}

install_packages() {
    local packages=(
        ca-certificates
        curl
        git
        jq
        locales
        nodejs
        npm
        openssh-client
        openssh-server
        ripgrep
        sudo
        tmux
        avahi-daemon
    )
    log 'updating package metadata'
    run_env DEBIAN_FRONTEND=noninteractive apt-get update
    log 'upgrading installed packages'
    run_env DEBIAN_FRONTEND=noninteractive apt-get -y upgrade
    log 'installing required packages'
    run_env DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends "${packages[@]}"
}

configure_locale() {
    local locale_file temp_file
    locale_file=$(root_path /etc/locale.gen)
    [[ -f "$locale_file" ]] || {
        log 'locale.gen is unavailable; skipping locale generation'
        return
    }
    if ((DRY_RUN)); then
        log 'would enable and generate en_GB.UTF-8'
        return
    fi
    if grep -qE '^en_GB\.UTF-8[[:space:]]+UTF-8$' "$locale_file"; then
        :
    elif grep -qE '^#[[:space:]]*en_GB\.UTF-8[[:space:]]+UTF-8$' "$locale_file"; then
        temp_file=$(mktemp "${locale_file}.XXXXXX")
        awk '{ if ($0 ~ /^#[[:space:]]*en_GB\.UTF-8[[:space:]]+UTF-8$/) sub(/^#[[:space:]]*/, ""); print }' "$locale_file" > "$temp_file"
        mv -- "$temp_file" "$locale_file"
    else
        printf 'en_GB.UTF-8 UTF-8\n' >> "$locale_file"
    fi
    locale-gen en_GB.UTF-8
}

install_codex() {
    if command -v codex >/dev/null 2>&1; then
        log 'Codex CLI already installed'
        return
    fi
    log 'installing Codex CLI from npm'
    run npm install --global @openai/codex
    ((DRY_RUN)) && return
    command -v codex >/dev/null 2>&1 || die 'Codex installation completed without a usable codex command'
    codex --version >/dev/null || die 'Codex command failed its version check'
}

user_exists() {
    grep -q '^rog:' "$(root_path /etc/passwd)"
}

group_exists() {
    grep -q "^$1:" "$(root_path /etc/group)"
}

user_in_group() {
    awk -F: -v group="$1" -v user=rog '$1 == group { n=split($4, members, ","); for (i = 1; i <= n; i++) if (members[i] == user) exit 0; exit 1 } END { if (NR == 0) exit 1 }' "$(root_path /etc/group)"
}

set_user_password() {
    local password confirmation
    read -r -s -p 'Password for rog: ' password
    printf '\n' >&2
    read -r -s -p 'Confirm password for rog: ' confirmation
    printf '\n' >&2
    [[ -n "$password" ]] || die 'password for rog must not be empty'
    [[ "$password" == "$confirmation" ]] || die 'password confirmations do not match'
    printf 'rog:%s\n' "$password" | chpasswd
}

configure_user() {
    local created=0
    if user_exists; then
        log 'user rog already exists'
    else
        log 'creating user rog'
        run useradd --create-home --shell /bin/bash rog
        created=1
    fi

    if ((created)) && (( ! DRY_RUN )); then
        set_user_password
    fi

    if ! group_exists sudo; then
        log 'creating sudo group'
        run groupadd sudo
    fi
    if user_exists && ! user_in_group sudo; then
        log 'adding rog to sudo group'
        run usermod --append --groups sudo rog
    fi
}

configure_sudo() {
    local sudoers_dir sudoers_file
    sudoers_dir=$(root_path /etc/sudoers.d)
    sudoers_file="$sudoers_dir/rog"
    run mkdir -p "$sudoers_dir"
    if ((DRY_RUN)); then
        log "would install $sudoers_file"
        return
    fi
    SUDOERS_TMP=$(mktemp "$(root_path /tmp)/tob-lxc-setup.sudoers.XXXXXX")
    printf 'rog ALL=(ALL:ALL) ALL\n' > "$SUDOERS_TMP"
    visudo -cf "$SUDOERS_TMP" >/dev/null || die 'generated sudoers policy failed visudo validation'
    install -m 0440 "$SUDOERS_TMP" "$sudoers_file"
    chown root:root "$sudoers_file"
}

valid_key_line() {
    local key_type key_data rest
    IFS=' ' read -r key_type key_data rest <<< "$1"
    [[ "$key_type" == ssh-ed25519 || "$key_type" == ssh-rsa || "$key_type" == ecdsa-sha2-* ]] || return 1
    [[ -n "$key_data" ]] || return 1
    printf '%s' "$key_data" | base64 --decode >/dev/null 2>&1
}

install_ssh_keys() {
    local key_source key_tmp ssh_dir authorized_keys line key_type key_data
    key_tmp=$(mktemp "$(root_path /tmp)/tob-lxc-setup.keys.XXXXXX")
    trap 'rm -f -- "$key_tmp"; cleanup' RETURN

    if [[ -n "$SSH_PUBLIC_KEY_FILE" ]]; then
        key_source=$SSH_PUBLIC_KEY_FILE
        cp -- "$key_source" "$key_tmp"
    else
        key_source="https://github.com/${GITHUB_USER}.keys"
        log "fetching SSH public keys from $key_source"
        curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 "$key_source" > "$key_tmp"
    fi

    ssh_dir=$(root_path /home/rog/.ssh)
    authorized_keys="$ssh_dir/authorized_keys"
    run mkdir -p "$ssh_dir"
    run chmod 0700 "$ssh_dir"
    run touch "$authorized_keys"
    run chmod 0600 "$authorized_keys"
    run chown -R rog:rog "$ssh_dir"

    while IFS= read -r line || [[ -n "$line" ]]; do
        [[ -z "$line" ]] && continue
        valid_key_line "$line" || die 'SSH key source contains an invalid or unsupported public-key line'
        IFS=' ' read -r key_type key_data _ <<< "$line"
        if ! awk -F'[[:space:]]+' -v type="$key_type" -v data="$key_data" '$1 == type && $2 == data { found = 1 } END { exit !found }' "$authorized_keys" 2>/dev/null; then
            printf '%s\n' "$line" >> "$authorized_keys"
        fi
    done < "$key_tmp"
    rm -f -- "$key_tmp"
    trap - RETURN
}

install_user_guidance() {
    local source destination
    source="$PAYLOAD_DIR/rog/AGENTS.md"
    destination=$(root_path /home/rog/AGENTS.md)
    if [[ ! -r "$source" ]]; then
        ((DRY_RUN)) && {
            log "would fetch user guidance payload from $PAYLOAD_URL"
            return
        }
        log "fetching user guidance payload from $PAYLOAD_URL"
        GUIDANCE_TMP=$(mktemp "$(root_path /tmp)/tob-lxc-setup.guidance.XXXXXX")
        curl --fail --silent --show-error --location --proto '=https' --tlsv1.2 "$PAYLOAD_URL" > "$GUIDANCE_TMP"
        grep -q '^# AGENTS.md$' "$GUIDANCE_TMP" || die 'downloaded user guidance payload failed validation'
        source=$GUIDANCE_TMP
    fi
    if [[ -e "$destination" ]]; then
        log "preserving existing $destination"
        return
    fi
    run cp -- "$source" "$destination"
    run chmod 0644 "$destination"
    run chown rog:rog "$destination"
}

manage_services() {
    local service
    if ((DRY_RUN)); then
        log 'would enable and start ssh and avahi-daemon when systemd services are available'
        return
    fi
    [[ -d "$(root_path /run/systemd/system)" ]] || {
        log 'systemd is not active; skipping service activation'
        return
    }
    command -v systemctl >/dev/null 2>&1 || {
        log 'systemctl is unavailable; skipping service activation'
        return
    }
    if systemctl list-unit-files ssh.service >/dev/null 2>&1; then
        run systemctl enable --now ssh
    elif systemctl list-unit-files sshd.service >/dev/null 2>&1; then
        run systemctl enable --now sshd
    fi
    service=avahi-daemon
    if systemctl list-unit-files "${service}.service" >/dev/null 2>&1; then
        run systemctl enable --now "$service"
    fi
}

main() {
    parse_args "$@"
    validate_environment
    install_packages
    configure_locale
    install_codex
    configure_user
    configure_sudo
    if ((NO_SSH_KEY)); then
        log 'SSH key installation disabled by --no-ssh-key'
    elif ((DRY_RUN)); then
        log 'would install SSH keys for rog'
    else
        install_ssh_keys
    fi
    install_user_guidance
    manage_services
    log 'LXC setup complete'
}

main "$@"
