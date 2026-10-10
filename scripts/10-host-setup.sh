#!/usr/bin/env bash
# One-time (idempotent) preparation of the MacBook as an always-on node host.
#
#   sudo scripts/10-host-setup.sh
#
# 1. hidden service user  2. /opt/gnosis tree  3. Engine API JWT secret
# 4. power settings (never sleep)  5. no automatic macOS update installs
# 6. application firewall  7. log rotation for the listener
#
# Every step is explained in docs/03-macbook-host.md. Re-running is safe.

source "$(dirname "$0")/lib.sh"
load_config
require_root "$@"
require_intel

ADMIN_USER="${SUDO_USER:-$(id -un)}"

# --- 1. service user -----------------------------------------------------------
setup_user() {
  log "Service user $SERVICE_USER (uid/gid $SERVICE_UID)"
  if is_test; then info "skipped (test mode)"; return; fi

  if ! dscl . -read "/Groups/$SERVICE_USER" >/dev/null 2>&1; then
    dscl . -list /Groups PrimaryGroupID | awk -v g="$SERVICE_UID" '$2==g {found=1} END {exit !found}' &&
      die "gid $SERVICE_UID already taken; set SERVICE_UID in config/node.env"
    dscl . -create "/Groups/$SERVICE_USER"
    dscl . -create "/Groups/$SERVICE_USER" PrimaryGroupID "$SERVICE_UID"
    dscl . -create "/Groups/$SERVICE_USER" RealName "Gnosis node"
    dscl . -create "/Groups/$SERVICE_USER" Password '*'
    info "group created"
  fi
  if ! dscl . -read "/Users/$SERVICE_USER" >/dev/null 2>&1; then
    dscl . -list /Users UniqueID | awk -v u="$SERVICE_UID" '$2==u {found=1} END {exit !found}' &&
      die "uid $SERVICE_UID already taken; set SERVICE_UID in config/node.env"
    dscl . -create "/Users/$SERVICE_USER"
    dscl . -create "/Users/$SERVICE_USER" UniqueID "$SERVICE_UID"
    dscl . -create "/Users/$SERVICE_USER" PrimaryGroupID "$SERVICE_UID"
    dscl . -create "/Users/$SERVICE_USER" UserShell /usr/bin/false
    dscl . -create "/Users/$SERVICE_USER" NFSHomeDirectory /var/empty
    dscl . -create "/Users/$SERVICE_USER" RealName "Gnosis node"
    dscl . -create "/Users/$SERVICE_USER" IsHidden 1
    dscl . -create "/Users/$SERVICE_USER" Password '*'
    info "user created (no login shell, no password, hidden)"
  fi
  # Lets the admin read logs and data without sudo.
  if [[ "$ADMIN_USER" != "root" ]]; then
    dseditgroup -o edit -a "$ADMIN_USER" -t user "$SERVICE_USER"
    info "$ADMIN_USER added to group $SERVICE_USER"
  fi
}

# --- 2. directory tree ------------------------------------------------------------
setup_dirs() {
  log "Directory tree in $GNOSIS_ROOT"
  mkdir -p "$GNOSIS_ROOT" "$CACHE_DIR" "$ETC_DIR" "$SECRETS_DIR" \
           "$DATA_DIR" "$LOG_DIR" "$GNOSIS_ROOT/state"
  is_test && { info "ownership skipped (test mode)"; return; }

  # Binaries and config: root-owned, the service can read but not change them.
  chown root:wheel "$GNOSIS_ROOT" "$CACHE_DIR"
  chmod 755 "$GNOSIS_ROOT"
  chown root:"$SERVICE_USER" "$ETC_DIR"; chmod 750 "$ETC_DIR"
  # Runtime state: owned by the service, group-readable for the admin.
  chown "$SERVICE_USER:$SERVICE_USER" "$DATA_DIR" "$LOG_DIR" "$GNOSIS_ROOT/state"
  chmod 750 "$DATA_DIR" "$LOG_DIR" "$GNOSIS_ROOT/state"
  chown "$SERVICE_USER:$SERVICE_USER" "$SECRETS_DIR"; chmod 700 "$SECRETS_DIR"
  info "owners set (binaries root, data/logs/state/secrets $SERVICE_USER)"
}

# --- 3. JWT --------------------------------------------------------------------
setup_jwt() {
  log "Engine API JWT secret"
  if [[ -s "$JWT_FILE" ]]; then
    info "exists, kept: $JWT_FILE"
    return
  fi
  (umask 077; openssl rand -hex 32 | tr -d '\n' > "$JWT_FILE")
  svc_own "$JWT_FILE"
  chmod 600 "$JWT_FILE"
  info "created $JWT_FILE (600)"
}

# --- 4. power --------------------------------------------------------------------
setup_power() {
  log "Power management (pmset)"
  if is_test; then info "skipped (test mode)"; return; fi
  # Never sleep, no hibernation image, keep network alive. Display may sleep.
  pmset -a sleep 0 disksleep 0 displaysleep 10 powernap 0 standby 0 \
           autopoweroff 0 hibernatemode 0 tcpkeepalive 1 womp 1 ttyskeepawake 1
  # Low Power Mode caps CPU clocks, also on AC; a syncing node needs full speed.
  if pmset -g cap | grep -qw lowpowermode; then pmset -a lowpowermode 0; fi
  # Boot when power returns after a fully drained battery, where supported.
  if pmset -g cap | grep -qw autorestartatconnect; then pmset -a autorestartatconnect 1; fi
  if pmset -g cap | grep -qw autorestart; then pmset -a autorestart 1; fi
  pmset -g | sed 's/^/      /'
}

# --- 5. software updates ----------------------------------------------------------
setup_updates() {
  log "Automatic macOS updates: download/notify only, never auto-install"
  if is_test; then info "skipped (test mode)"; return; fi
  softwareupdate --schedule off >/dev/null 2>&1 || true
  defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticDownload -bool false
  defaults write /Library/Preferences/com.apple.SoftwareUpdate AutomaticallyInstallMacOSUpdates -bool false
  defaults write /Library/Preferences/com.apple.commerce AutoUpdate -bool false
  info "also check System Settings > General > Software Update > Automatic Updates (docs/03)"
}

# --- 6. firewall -----------------------------------------------------------------
setup_firewall() {
  log "Application firewall"
  if is_test; then info "skipped (test mode)"; return; fi
  local fw=/usr/libexec/ApplicationFirewall/socketfilterfw
  $fw --setglobalstate on >/dev/null
  $fw --setstealthmode on >/dev/null
  $fw --getglobalstate | sed 's/^/      /'
}

# --- 7. log rotation -----------------------------------------------------------------
setup_newsyslog() {
  log "Log rotation (newsyslog) for the listener"
  # Nethermind (NLog) and Teku (log4j) rotate their own log files. The
  # listener writes its own file and reopens it on SIGHUP, so newsyslog can
  # rotate it by size and signal it through the pid file.
  local conf="/etc/newsyslog.d/gnosis.conf"
  is_test && conf="$ETC_DIR/newsyslog-gnosis.conf"
  cat > "$conf" <<EOF
# Managed by domovina-gnosis-node scripts/10-host-setup.sh
# logfilename                      [owner:group]                 mode count size(KB) when flags pid_file                          sig
$LOG_DIR/listener.log  $SERVICE_USER:$SERVICE_USER  640  10    20000    *    J     $GNOSIS_ROOT/state/listener.pid  1
EOF
  info "wrote $conf"
}

setup_user
setup_dirs
setup_jwt
setup_power
setup_updates
setup_firewall
setup_newsyslog

echo
log "host setup done. Next: sudo scripts/20-install.sh"
