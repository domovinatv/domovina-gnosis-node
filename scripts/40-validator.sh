#!/usr/bin/env bash
# Validator key handling for the Teku validator client. Read docs/08-validator.md first.
#
#   sudo scripts/40-validator.sh import DIR          copy keystore-*.json from DIR, ask for the password
#   sudo scripts/40-validator.sh slashing-export FILE   EIP-3076 export (validator must be stopped)
#   sudo scripts/40-validator.sh slashing-import FILE   EIP-3076 import (validator must be stopped)
#   sudo scripts/40-validator.sh exit                  voluntary exit (irreversible, asks twice)
#
# Keys live in $GNOSIS_ROOT/validator/{keys,passwords}, readable only by the service user.
# NEVER run the same keys anywhere else at the same time: that is how validators get slashed.

source "$(dirname "$0")/lib.sh"
load_config
require_root "$@"

VAL_DIR="$GNOSIS_ROOT/validator"
KEYS_DIR="$VAL_DIR/keys"
PASS_DIR="$VAL_DIR/passwords"
VC_DATA="$DATA_DIR/validator"

teku() {
  local home="$GNOSIS_ROOT/teku/current"
  sudo -u "$SERVICE_USER" "$GNOSIS_ROOT/jre/current/Contents/Home/bin/java" \
    "-Dteku.home=$home" -cp "$home/lib/*" tech.pegasys.teku.Teku "$@"
}

vc_running() { launchctl print "system/$(label validator)" 2>/dev/null | grep -q 'state = running'; }

cmd_import() {
  local src="${1:?usage: $0 import DIR}" f n=0 pw pw2
  compgen -G "$src/keystore-*.json" >/dev/null || die "no keystore-*.json in $src"
  vc_running && die "stop the validator first: scripts/gnosisctl stop validator"

  mkdir -p "$KEYS_DIR" "$PASS_DIR"
  read -r -s -p "Keystore password (from key generation): " pw; echo
  read -r -s -p "Repeat: " pw2; echo
  [[ "$pw" == "$pw2" ]] || die "passwords differ"

  for f in "$src"/keystore-*.json; do
    local name; name="$(basename "$f" .json)"
    if [[ -f "$KEYS_DIR/$name.json" ]]; then info "already imported: $name"; continue; fi
    install -m 600 "$f" "$KEYS_DIR/$name.json"
    # Teku pairs keys/<name>.json with passwords/<name>.txt
    (umask 077; printf '%s' "$pw" > "$PASS_DIR/$name.txt")
    n=$((n + 1))
    info "imported $name (pubkey 0x$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["pubkey"])' "$f"))"
  done
  pw=''; pw2=''
  chmod 700 "$VAL_DIR" "$KEYS_DIR" "$PASS_DIR"
  svc_own "$VAL_DIR"
  log "$n key(s) imported into $KEYS_DIR"
  info "next: VALIDATOR_ENABLED=true and FEE_RECIPIENT in config/node.env, then"
  info "      sudo scripts/30-services.sh install validator"
  info "Doppelganger detection keeps it silent for the first ~2-3 epochs (~4 min). That is expected."
}

cmd_slashing_export() {
  local out="${1:?usage: $0 slashing-export FILE}"
  vc_running && die "stop the validator first: scripts/gnosisctl stop validator"
  teku slashing-protection export --data-path="$VC_DATA" --to="/tmp/slashing-export.$$.json"
  mv "/tmp/slashing-export.$$.json" "$out"
  log "exported to $out"
}

cmd_slashing_import() {
  local in="${1:?usage: $0 slashing-import FILE}"
  vc_running && die "stop the validator first: scripts/gnosisctl stop validator"
  local tmp="/tmp/slashing-import.$$.json"
  install -m 644 "$in" "$tmp"
  teku slashing-protection import --data-path="$VC_DATA" --from="$tmp"
  rm -f "$tmp"
  log "imported $in"
}

cmd_exit() {
  warn "A voluntary exit is PERMANENT. The validator stops earning and cannot be restarted."
  warn "After ~256 epochs (~6 h) the 1 GNO becomes withdrawable to the withdrawal address."
  local a
  read -r -p "Type EXIT to continue: " a; [[ "$a" == "EXIT" ]] || die "aborted"
  teku voluntary-exit --network=gnosis \
    --beacon-node-api-endpoint="http://127.0.0.1:$CL_HTTP_PORT" \
    --data-path="$VC_DATA" \
    --validator-keys="$KEYS_DIR:$PASS_DIR"
}

case "${1:-}" in
  import)          cmd_import "${2:-}" ;;
  slashing-export) cmd_slashing_export "${2:-}" ;;
  slashing-import) cmd_slashing_import "${2:-}" ;;
  exit)            cmd_exit ;;
  *) sed -n '2,11p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
