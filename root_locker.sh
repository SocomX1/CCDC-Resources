#!/usr/bin/env bash
set -euo pipefail

log() {
    printf '[+] %s\n' "$*"
}

warn() {
    printf '[!] %s\n' "$*" >&2
}

fail() {
    printf '[x] %s\n' "$*" >&2
    exit 1
}

need_root() {
    if [ "${EUID:-$(id -u)}" -ne 0 ]; then
        fail "Run this script as root."
    fi
}

command_exists() {
    command -v "$1" >/dev/null 2>&1
}

backup_file() {
    local file="$1"
    local ts
    ts="$(date +%Y%m%d-%H%M%S 2>/dev/null || echo backup)"
    cp -p -- "$file" "$file.bak.$ts"
}

lock_root_password() {
    if command_exists passwd; then
        if passwd -l root >/dev/null 2>&1; then
            log "Locked root password with passwd -l."
            return
        fi
    fi

    if command_exists usermod; then
        if usermod -L root >/dev/null 2>&1; then
            log "Locked root password with usermod -L."
            return
        fi
    fi

    warn "Could not lock root password automatically."
}

# expire_root_password() {
#     if command_exists chage; then
#         if chage -E 0 root >/dev/null 2>&1; then
#             log "Expired root account with chage -E 0."
#         else
#             warn "Could not expire root account with chage."
#         fi
#     else
#         warn "chage not found; skipping account expiration."
#     fi
# }

# set_root_nologin_shell() {
#     local nologin_shell=""

#     for shell in /usr/sbin/nologin /sbin/nologin /bin/false; do
#         if [ -x "$shell" ]; then
#             nologin_shell="$shell"
#             break
#         fi
#     done

#     if [ -z "$nologin_shell" ]; then
#         warn "No nologin shell found; skipping shell change."
#         return
#     fi

#     if command_exists chsh; then
#         if chsh -s "$nologin_shell" root >/dev/null 2>&1; then
#             log "Set root shell to $nologin_shell with chsh."
#             return
#         fi
#     fi

#     if command_exists usermod; then
#         if usermod -s "$nologin_shell" root >/dev/null 2>&1; then
#             log "Set root shell to $nologin_shell with usermod."
#             return
#         fi
#     fi

#     warn "Could not change root shell."
# }

remove_root_ssh_keys() {
    local ssh_dir="/root/.ssh"
    local auth_keys="$ssh_dir/authorized_keys"

    if [ -f "$auth_keys" ]; then
        backup_file "$auth_keys"
        : > "$auth_keys"
        chmod 600 "$auth_keys" || true
        log "Cleared root authorized_keys."
    else
        log "No root authorized_keys file found."
    fi
}

harden_sshd_config() {
    local sshd_config=""
    local ddir=""
    local dropin=""

    for f in /etc/ssh/sshd_config /etc/openssh/sshd_config; do
        if [ -f "$f" ]; then
            sshd_config="$f"
            break
        fi
    done

    if [ -z "$sshd_config" ]; then
        warn "sshd_config not found; skipping SSH hardening."
        return
    fi

    ddir="$(dirname "$sshd_config")/sshd_config.d"
    dropin="$ddir/99-disable-root-login.conf"

    mkdir -p "$ddir"

    cat > "$dropin" <<'EOF'
# Managed by root lockdown script
PermitRootLogin no
EOF

    chmod 644 "$dropin"
    log "Wrote SSH drop-in: $dropin"

    if command_exists sshd; then
        if sshd -t >/dev/null 2>&1; then
            log "sshd configuration test passed."
        else
            fail "sshd configuration test failed; review SSH config before restarting sshd."
        fi
    else
        warn "sshd binary not found; could not validate SSH configuration."
    fi

    if command_exists systemctl; then
        if systemctl reload sshd >/dev/null 2>&1; then
            log "Reloaded sshd via systemctl reload sshd."
            return
        elif systemctl reload ssh >/dev/null 2>&1; then
            log "Reloaded ssh via systemctl reload ssh."
            return
        fi
    fi

    if command_exists service; then
        if service sshd reload >/dev/null 2>&1; then
            log "Reloaded sshd via service sshd reload."
            return
        elif service ssh reload >/dev/null 2>&1; then
            log "Reloaded ssh via service ssh reload."
            return
        fi
    fi

    warn "Could not reload sshd automatically. Reload it manually."
}

# Doesn't currently make use of expire_root_password or set_root_nologin_shell
# in order to make the script more easily reversible.
main() {
    need_root

    log "Starting root account lockdown..."

    lock_root_password
    remove_root_ssh_keys
    harden_sshd_config
    
    log "Root lockdown complete."
}

main "$@"