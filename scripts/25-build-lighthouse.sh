#!/usr/bin/env bash
# OPTIONAL: build Lighthouse from source, for CL_CLIENT=lighthouse.
# The default consensus client is Teku (docs/02-decisions.md#adr-003); you
# only need this to switch clients or keep a fallback ready.
#
#   scripts/25-build-lighthouse.sh        # as your admin user, NOT with sudo
#
# Lighthouse stopped publishing Intel macOS binaries in v8.0.0, and the
# Homebrew formula is built without Gnosis support. The `gnosis` cargo
# feature is mandatory: without it the binary refuses `--network gnosis`.
#
# Needs: Xcode Command Line Tools, rustup, cmake, protoc. Takes ~20-40 min on
# the i9 and several GB in ~/src and ~/.cargo.

source "$(dirname "$0")/lib.sh"
load_config
require_intel
[[ $EUID -ne 0 ]] || die "run as your normal user; the script asks for sudo only to install the binary"

SRC="${LIGHTHOUSE_SRC:-$HOME/src/lighthouse}"
FEATURES="gnosis,slasher-lmdb,beacon-node-leveldb"   # gnosis + Lighthouse's default features

log "Toolchain"
xcode-select -p >/dev/null 2>&1 || die "install Command Line Tools: xcode-select --install"
if ! command -v rustup >/dev/null 2>&1 && [[ ! -x "$HOME/.cargo/bin/rustup" ]]; then
  info "installing rustup (https://rustup.rs)"
  curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --profile minimal
fi
export PATH="$HOME/.cargo/bin:$PATH"
rustup update stable >/dev/null
info "$(rustc --version) (Lighthouse needs >= $LIGHTHOUSE_MIN_RUST)"

for tool in cmake protoc; do
  if ! command -v "$tool" >/dev/null 2>&1; then
    command -v brew >/dev/null 2>&1 || die "$tool missing and no Homebrew. Install $tool (cmake.org / github.com/protocolbuffers/protobuf releases)"
    warn "$tool missing: brew install (Intel is Homebrew tier 3 since 7.0, this may compile from source)"
    case "$tool" in cmake) brew install cmake ;; protoc) brew install protobuf ;; esac
  fi
  info "$tool: $(command -v "$tool")"
done

log "Source $LIGHTHOUSE_VERSION in $SRC"
if [[ ! -d "$SRC/.git" ]]; then
  mkdir -p "$(dirname "$SRC")"
  git clone https://github.com/sigp/lighthouse.git "$SRC"
fi
git -C "$SRC" fetch --tags --quiet
git -C "$SRC" checkout --quiet "$LIGHTHOUSE_VERSION"
info "at $(git -C "$SRC" describe --tags)"

log "cargo build --release --features $FEATURES"
(cd "$SRC" && cargo build --release --locked -p lighthouse --features "$FEATURES")
BIN="$SRC/target/release/lighthouse"
"$BIN" --version | head -1 | sed 's/^/    /'

log "Install to $GNOSIS_ROOT/lighthouse/$LIGHTHOUSE_VERSION (sudo)"
sudo mkdir -p "$GNOSIS_ROOT/lighthouse/$LIGHTHOUSE_VERSION"
sudo install -m 755 "$BIN" "$GNOSIS_ROOT/lighthouse/$LIGHTHOUSE_VERSION/lighthouse"
sudo ln -sfn "$LIGHTHOUSE_VERSION" "$GNOSIS_ROOT/lighthouse/current"
info "set CL_CLIENT=lighthouse in config/node.env, then: sudo scripts/30-services.sh uninstall teku && sudo scripts/30-services.sh install lighthouse"
info "a different CL needs its own fresh checkpoint sync; the EL database is kept."
