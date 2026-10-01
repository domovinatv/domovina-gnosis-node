#!/usr/bin/env bash
# Read-only checks of the MacBook before anything is installed.
# Safe to run any time, no sudo. Exit code 1 if a hard requirement fails.
#
#   scripts/00-preflight.sh

source "$(dirname "$0")/lib.sh"
load_config

fails=0
ok()   { printf '  %sok%s    %s\n' "$C_GRN" "$C_OFF" "$*"; }
bad()  { printf '  %sFAIL%s  %s\n' "$C_RED" "$C_OFF" "$*"; fails=$((fails + 1)); }
meh()  { printf '  %swarn%s  %s\n' "$C_YEL" "$C_OFF" "$*"; }

log "Hardware"
arch="$(uname -m)"
[[ "$arch" == "x86_64" ]] && ok "CPU arch $arch" || bad "CPU arch $arch (this setup targets the Intel i9)"
info "$(sysctl -n machdep.cpu.brand_string), $(sysctl -n hw.physicalcpu) cores / $(sysctl -n hw.logicalcpu) threads"

ram_gb=$(( $(sysctl -n hw.memsize) / 1024 / 1024 / 1024 ))
(( ram_gb >= 32 )) && ok "RAM ${ram_gb} GB" || bad "RAM ${ram_gb} GB (want >= 32)"

# Free space on the volume that will hold GNOSIS_ROOT (/opt lives on Data).
probe="$GNOSIS_ROOT"; [[ -d "$probe" ]] || probe=/
free_gb=$(df -g "$probe" | awk 'NR==2 {print $4}')
if (( free_gb >= 700 )); then ok "free disk ${free_gb} GB"
elif (( free_gb >= 500 )); then meh "free disk ${free_gb} GB (works today, little headroom; want >= 700)"
else bad "free disk ${free_gb} GB (need >= 500, want >= 700)"; fi

log "macOS"
ok "$(sw_vers -productName) $(sw_vers -productVersion) ($(sw_vers -buildVersion))"
xcode-select -p >/dev/null 2>&1 && ok "Command Line Tools installed" || bad "Command Line Tools missing: xcode-select --install"

fv="$(fdesetup status 2>/dev/null || true)"
if [[ "$fv" == *"On"* ]]; then
  meh "FileVault ON: an unplanned reboot waits at the unlock screen and the node stays down until someone types the password (docs/03)"
  fdesetup supportsauthrestart 2>/dev/null | grep -q true && info "authrestart supported: use 'sudo fdesetup authrestart' for planned reboots"
else
  meh "FileVault OFF: unattended reboots work, disk is only protected by the T2 while it stays in this Mac (docs/03)"
fi

log "Power"
if pmset -g batt | grep -q "AC Power"; then ok "on AC power"; else meh "on battery"; fi
sleep_val="$(pmset -g | awk '$1=="sleep" {print $2}')"
[[ "$sleep_val" == "0" ]] && ok "system sleep disabled" || meh "system sleep = ${sleep_val:-?} (10-host-setup.sh sets 0)"
batt="$(system_profiler SPPowerDataType 2>/dev/null | awk -F': ' '/Condition|Cycle Count|Maximum Capacity/ {gsub(/^ +/,"",$1); printf "%s=%s ", $1, $2}')"
[[ -n "$batt" ]] && info "battery: $batt"

log "Network and time"
if curl -fsS -m 10 -o /dev/null "$CHECKPOINT_SYNC_URL/eth/v1/beacon/states/finalized/finality_checkpoints"; then
  ok "checkpoint sync reachable: $CHECKPOINT_SYNC_URL"
else
  bad "checkpoint sync unreachable: $CHECKPOINT_SYNC_URL"
fi
offset="$(sntp -t 3 time.cloudflare.com 2>/dev/null | awk '/[+-][0-9.]+ \+\/-/ {print $1; exit}')"
if [[ -n "$offset" ]]; then
  abs="${offset#[-+]}"
  awk -v a="$abs" 'BEGIN { exit !(a < 0.1) }' && ok "clock offset ${offset}s" || meh "clock offset ${offset}s (validators want < 0.1s)"
else
  meh "could not measure clock offset (sntp)"
fi

log "Ports free on 127.0.0.1"
for p in "$EL_HTTP_PORT" "$EL_WS_PORT" "$EL_ENGINE_PORT" "$CL_HTTP_PORT" "$EL_P2P_PORT" "$CL_P2P_PORT"; do
  if lsof -nP -iTCP:"$p" -sTCP:LISTEN >/dev/null 2>&1; then
    meh "port $p in use: $(lsof -nP -iTCP:"$p" -sTCP:LISTEN | awk 'NR==2 {print $1}')"
  else
    ok "port $p free"
  fi
done

log "Existing install"
if [[ -d "$GNOSIS_ROOT" ]]; then info "$GNOSIS_ROOT exists:"; ls "$GNOSIS_ROOT" | sed 's/^/      /'; else info "$GNOSIS_ROOT not created yet"; fi
dscl . -read "/Users/$SERVICE_USER" UniqueID >/dev/null 2>&1 && info "service user $SERVICE_USER exists" || info "service user $SERVICE_USER not created yet"

echo
if (( fails > 0 )); then
  die "$fails hard requirement(s) failed"
fi
log "preflight passed"
