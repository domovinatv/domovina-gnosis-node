#!/usr/bin/env bash
# Validator key handling for the Teku validator client. Read docs/08-validator.md first.
#
#   scripts/40-validator.sh verify DIR                 verify deposit_data & keystores before import/deposit
#   sudo scripts/40-validator.sh import DIR            copy keystore-*.json from DIR, ask for the password
#   sudo scripts/40-validator.sh status                on-chain status and GNO balance from local beacon node
#   sudo scripts/40-validator.sh slashing-export FILE  EIP-3076 export (validator must be stopped)
#   sudo scripts/40-validator.sh slashing-import FILE  EIP-3076 import (validator must be stopped)
#   sudo scripts/40-validator.sh exit                  voluntary exit (irreversible, asks twice)
#
# Keys live in $GNOSIS_ROOT/validator/{keys,passwords}, readable only by the service user.
# NEVER run the same keys anywhere else at the same time: that is how validators get slashed.

source "$(dirname "$0")/lib.sh"
load_config

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

cmd_verify() {
  local src="${1:?usage: $0 verify DIR}"
  compgen -G "$src/keystore-*.json" >/dev/null || die "no keystore-*.json in $src"
  compgen -G "$src/deposit_data-*.json" >/dev/null || die "no deposit_data-*.json in $src"
  /usr/bin/python3 - "$src" <<'PY'
import glob, json, os, sys

src = sys.argv[1]
ks_files = sorted(glob.glob(os.path.join(src, "keystore-*.json")))
dd_files = sorted(glob.glob(os.path.join(src, "deposit_data-*.json")))

ks_pubs = {}
for f in ks_files:
    d = json.load(open(f))
    pk = d.get("pubkey", "").lower().removeprefix("0x")
    ks_pubs[pk] = os.path.basename(f)

dd_entries = []
for f in dd_files:
    dd_entries.extend(json.load(open(f)))

bad = 0
print(f"Found {len(ks_files)} keystore(s) and {len(dd_entries)} deposit_data entry/entries in {src}:\n")
for i, e in enumerate(dd_entries, 1):
    pk = e.get("pubkey", "").lower().removeprefix("0x")
    wc = e.get("withdrawal_credentials", "").lower().removeprefix("0x")
    amt = int(e.get("amount", 0))
    net = e.get("network_name", "?")
    fork = e.get("fork_version", "").lower().removeprefix("0x")
    w_type = wc[:2]
    w_addr = "0x" + wc[24:] if len(wc) == 64 else "INVALID"
    gno = amt / 32_000_000_000
    ks_name = ks_pubs.get(pk, "MISSING KEYSTORE!")

    print(f"  [{i}] Keystore:            {ks_name}")
    print(f"      Pubkey:              0x{pk}")
    print(f"      Network / Fork:      {net} (fork_version 0x{fork})")
    print(f"      Credentials type:    0x{w_type} ({'compounding (recommended)' if w_type == '02' else 'regular 0x01' if w_type == '01' else 'BLS 0x00 - DO NOT USE'})")
    print(f"      Withdrawal address:  {w_addr}")
    print(f"      Deposit amount:      {gno:g} GNO ({amt} mGNO Gwei)")

    if pk not in ks_pubs:
        print("      ERROR: pubkey not found in any keystore-*.json!")
        bad = 1
    if net != "gnosis" or fork != "00000064":
        print("      ERROR: not a Gnosis Chain deposit (expected network=gnosis, fork_version=00000064)!")
        bad = 1
    if w_type not in ("01", "02") or wc[2:24] != "0" * 22:
        print("      ERROR: invalid withdrawal_credentials format!")
        bad = 1
    if gno < 1 or gno > 64:
        print("      ERROR: deposit amount out of range (expected 1..64 GNO)!")
        bad = 1
    print()

sys.exit(bad)
PY
}

cmd_import() {
  require_root import "$@"
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
  info "      sudo scripts/30-services.sh install teku validator"
  info "Doppelganger detection keeps it silent for the first ~2-3 epochs (~4 min). That is expected."
}

cmd_status() {
  require_root status "$@"
  compgen -G "$KEYS_DIR/keystore-*.json" >/dev/null || die "no keystores in $KEYS_DIR"
  local f pk res
  for f in "$KEYS_DIR"/keystore-*.json; do
    pk="0x$(/usr/bin/python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["pubkey"].removeprefix("0x"))' "$f")"
    res="$(curl -fsS -m 5 "http://127.0.0.1:$CL_HTTP_PORT/eth/v1/beacon/states/head/validators/$pk" 2>/dev/null || true)"
    if [[ -z "$res" ]]; then
      printf '  %s  status: not_on_chain_yet (awaiting deposit or ~1.5h activation)\n' "$pk"
    else
      /usr/bin/python3 -c '
import json, sys
d = json.loads(sys.argv[1])["data"]
v = d["validator"]
bal = int(d["balance"]) / 32_000_000_000
eb = int(v["effective_balance"]) / 32_000_000_000
wc = v["withdrawal_credentials"]
w_addr = "0x" + wc[-40:]
print(f"  {v[\"pubkey\"]}  index={d[\"index\"]}  status={d[\"status\"]}  balance={bal:.6f} GNO (effective {eb:.5f} GNO)  withdrawal={w_addr}  slashed={v[\"slashed\"]}")
' "$res"
    fi
  done
}

cmd_slashing_export() {
  require_root slashing-export "$@"
  local out="${1:?usage: $0 slashing-export FILE}"
  vc_running && die "stop the validator first: scripts/gnosisctl stop validator"
  teku slashing-protection export --data-path="$VC_DATA" --to="/tmp/slashing-export.$$.json"
  mv "/tmp/slashing-export.$$.json" "$out"
  [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]] && chown "$SUDO_USER" "$out" || true
  log "exported to $out"
}

cmd_slashing_import() {
  require_root slashing-import "$@"
  local in="${1:?usage: $0 slashing-import FILE}"
  vc_running && die "stop the validator first: scripts/gnosisctl stop validator"
  local tmp="/tmp/slashing-import.$$.json"
  install -m 644 "$in" "$tmp"
  teku slashing-protection import --data-path="$VC_DATA" --from="$tmp"
  rm -f "$tmp"
  log "imported $in"
}

cmd_exit() {
  require_root exit "$@"
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
  verify)          cmd_verify "${2:-}" ;;
  import)          cmd_import "${2:-}" ;;
  status)          cmd_status ;;
  slashing-export) cmd_slashing_export "${2:-}" ;;
  slashing-import) cmd_slashing_import "${2:-}" ;;
  exit)            cmd_exit ;;
  *) sed -n '2,13p' "$0" | sed 's/^# \{0,1\}//'; exit 1 ;;
esac
