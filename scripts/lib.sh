# Shared helpers for the scripts in this directory. Source it, don't run it.
#
# Written for the bash 3.2 that ships with macOS: no associative arrays,
# no ${var,,}, no mapfile, and no "${empty_array[@]}" under set -u.
#
# Test mode: GNOSIS_TEST=1 lets the scripts run as a normal user on any Mac
# (no root, no chown, arm64 allowed). Point GNOSIS_ROOT at a scratch dir.

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GNOSIS_TEST="${GNOSIS_TEST:-0}"

if [[ -t 1 ]]; then
  C_RED=$'\033[31m'; C_YEL=$'\033[33m'; C_GRN=$'\033[32m'; C_DIM=$'\033[2m'; C_OFF=$'\033[0m'
else
  C_RED=''; C_YEL=''; C_GRN=''; C_DIM=''; C_OFF=''
fi

log()  { printf '%s==>%s %s\n' "$C_GRN" "$C_OFF" "$*"; }
info() { printf '%s    %s%s\n' "$C_DIM" "$*" "$C_OFF"; }
warn() { printf '%sWARN%s %s\n' "$C_YEL" "$C_OFF" "$*" >&2; }
die()  { printf '%sERROR%s %s\n' "$C_RED" "$C_OFF" "$*" >&2; exit 1; }

load_config() {
  # Keep a GNOSIS_ROOT given on the command line (test mode) over the file.
  local root_override="${GNOSIS_ROOT:-}"
  # shellcheck source=../config/versions.env
  source "$REPO_DIR/config/versions.env"
  local conf="${GNOSIS_CONFIG:-$REPO_DIR/config/node.env}"
  if [[ -f "$conf" ]]; then
    source "$conf"
  else
    warn "config/node.env missing, using config/node.env.example (cp it and edit)"
    source "$REPO_DIR/config/node.env.example"
  fi
  [[ -n "$root_override" ]] && GNOSIS_ROOT="$root_override"

  DATA_DIR="$GNOSIS_ROOT/data"
  LOG_DIR="$GNOSIS_ROOT/logs"
  ETC_DIR="$GNOSIS_ROOT/etc"
  SECRETS_DIR="$GNOSIS_ROOT/secrets"
  CACHE_DIR="$GNOSIS_ROOT/cache"
  JWT_FILE="$SECRETS_DIR/jwt.hex"
  LAUNCHD_DIR="${LAUNCHD_DIR:-/Library/LaunchDaemons}"
  LABEL_PREFIX="tv.domovina.gnosis"
}

is_test() { [[ "$GNOSIS_TEST" == "1" ]]; }

require_root() {
  is_test && return 0
  [[ $EUID -eq 0 ]] || die "run with sudo: sudo $0 $*"
}

require_intel() {
  local arch
  arch="$(uname -m)"
  if [[ "$arch" != "x86_64" ]]; then
    is_test && { warn "arch $arch; continuing because GNOSIS_TEST=1"; return 0; }
    die "this repo installs Intel (x86_64) builds; this Mac is $arch"
  fi
}

# chown to the service user (skipped in test mode).
svc_own() {
  is_test && return 0
  chown -R "$SERVICE_USER:$SERVICE_USER" "$@"
}

# fetch URL FILE SHA256: download into the cache once and verify the checksum.
fetch() {
  local url="$1" file="$CACHE_DIR/$2" sum="$3"
  mkdir -p "$CACHE_DIR"
  if [[ ! -f "$file" ]]; then
    info "download $url"
    curl -fSL --retry 3 --progress-bar -o "$file.part" "$url"
    mv "$file.part" "$file"
  fi
  local got
  got="$(shasum -a 256 "$file" | awk '{print $1}')"
  if [[ "$got" != "$sum" ]]; then
    rm -f "$file"
    die "checksum mismatch for $2: expected $sum, got $got (file removed)"
  fi
  info "sha256 ok: $2"
}

# Versioned installs: $GNOSIS_ROOT/<name>/<version>, with a `current` symlink.
# Rolling back is pointing `current` at the previous directory.
version_dir() { echo "$GNOSIS_ROOT/$1/$2"; }

activate_version() {
  local name="$1" version="$2"
  # Binaries belong to root: the service user can run but not modify them.
  # (tar/unzip as root would otherwise keep the archive's numeric owners.)
  is_test || chown -R root:wheel "$GNOSIS_ROOT/$name/$version"
  chmod -R go-w "$GNOSIS_ROOT/$name/$version"
  ln -sfn "$version" "$GNOSIS_ROOT/$name/current"
  info "$name/current -> $version"
}

# Remove the quarantine flag macOS puts on downloaded files, so Gatekeeper
# doesn't block binaries started by launchd (there is nobody to click "Open").
unquarantine() { xattr -dr com.apple.quarantine "$@" 2>/dev/null || true; }

label() { echo "$LABEL_PREFIX.$1"; }
