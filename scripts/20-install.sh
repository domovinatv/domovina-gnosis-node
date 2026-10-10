#!/usr/bin/env bash
# Download, verify (SHA-256 from config/versions.env) and install components
# into versioned directories under $GNOSIS_ROOT, then point `current` at them.
#
#   sudo scripts/20-install.sh                 # everything the config needs
#   sudo scripts/20-install.sh nethermind      # one component (e.g. upgrade)
#
# Components: nethermind teku jre node listener cloudflared
# Installing a new version does not restart anything; use gnosisctl restart.
# Rollback: sudo ln -sfn <old-version> /opt/gnosis/<component>/current

source "$(dirname "$0")/lib.sh"
load_config
require_root "$@"
require_intel

install_nethermind() {
  local v="$NETHERMIND_VERSION" dir file
  file="nethermind-$v-$NETHERMIND_COMMIT-macos-x64.zip"
  dir="$(version_dir nethermind "$v")"
  log "Nethermind $v"
  fetch "https://github.com/NethermindEth/nethermind/releases/download/$v/$file" "$file" "$NETHERMIND_SHA256"
  if command -v gpg >/dev/null 2>&1; then
    # Optional second check; the pinned checksum above is the gate.
    # Run gpg as the admin: sudo on macOS keeps HOME, so gpg as root would
    # write root-owned files into ~/.gnupg and leave a root dirmngr behind.
    local gpg_cmd=(gpg)
    [[ -n "${SUDO_USER:-}" && "$SUDO_USER" != "root" ]] && gpg_cmd=(sudo -u "$SUDO_USER" -H gpg)
    curl -fsSL -o "$CACHE_DIR/$file.asc" "https://github.com/NethermindEth/nethermind/releases/download/$v/$file.asc" &&
      "${gpg_cmd[@]}" --verify "$CACHE_DIR/$file.asc" "$CACHE_DIR/$file" 2>&1 | sed 's/^/      gpg: /' || warn "gpg check failed or key not imported (see docs/04)"
  fi
  rm -rf "$dir"; mkdir -p "$dir"
  unzip -q "$CACHE_DIR/$file" -d "$dir"
  [[ -x "$dir/nethermind" ]] || die "no nethermind executable in $file"
  unquarantine "$dir"
  activate_version nethermind "$v"
}

install_jre() {
  local dir file
  file="$TEMURIN_FILE"
  dir="$(version_dir jre "$TEMURIN_RELEASE")"
  log "Java runtime $TEMURIN_RELEASE (Temurin)"
  fetch "https://github.com/adoptium/temurin25-binaries/releases/download/${TEMURIN_RELEASE/+/%2B}/$file" "$file" "$TEMURIN_SHA256"
  rm -rf "$dir"; mkdir -p "$dir"
  tar --no-same-owner -xzf "$CACHE_DIR/$file" -C "$dir" --strip-components 1
  [[ -x "$dir/Contents/Home/bin/java" ]] || die "no java in $file"
  unquarantine "$dir"
  activate_version jre "$TEMURIN_RELEASE"
}

install_teku() {
  local v="$TEKU_VERSION" dir file
  file="teku-$v.tar.gz"
  dir="$(version_dir teku "$v")"
  log "Teku $v"
  fetch "https://github.com/Consensys/teku/releases/download/$v/$file" "$file" "$TEKU_SHA256"
  rm -rf "$dir"; mkdir -p "$dir"
  tar --no-same-owner -xzf "$CACHE_DIR/$file" -C "$dir" --strip-components 1
  [[ -f "$dir/lib/teku-$v.jar" ]] || die "teku jar missing in $file"
  unquarantine "$dir"
  activate_version teku "$v"
}

install_node() {
  local v="$NODE_VERSION" dir file
  file="node-$v-darwin-x64.tar.gz"
  dir="$(version_dir node "$v")"
  log "Node.js $v"
  fetch "https://nodejs.org/dist/$v/$file" "$file" "$NODE_SHA256"
  rm -rf "$dir"; mkdir -p "$dir"
  tar --no-same-owner -xzf "$CACHE_DIR/$file" -C "$dir" --strip-components 1
  unquarantine "$dir"
  activate_version node "$v"
}

install_listener() {
  # The daemon runs a copy, not the git checkout, so a `git pull` never
  # changes a running service by surprise. Re-run this to deploy changes.
  local dir="$GNOSIS_ROOT/listener"
  log "Payment listener -> $dir"
  mkdir -p "$dir"
  install -m 644 "$REPO_DIR/listener/listener.mjs" "$dir/listener.mjs"
  if [[ ! -f "$ETC_DIR/listener.env" ]]; then
    install -m 640 "$REPO_DIR/listener/listener.env.example" "$ETC_DIR/listener.env"
    is_test || chown root:"$SERVICE_USER" "$ETC_DIR/listener.env"
    info "created $ETC_DIR/listener.env from example: set WEBHOOK_URL and WEBHOOK_SECRET"
  fi
  if [[ ! -f "$ETC_DIR/watchlist.json" ]]; then
    echo '[]' > "$ETC_DIR/watchlist.json"
    chmod 644 "$ETC_DIR/watchlist.json"
    info "created empty $ETC_DIR/watchlist.json"
  fi
}

install_cloudflared() {
  local v="$CLOUDFLARED_VERSION" dir file
  file="cloudflared-$v-darwin-amd64.tgz"
  dir="$(version_dir cloudflared "$v")"
  log "cloudflared $v"
  fetch "https://github.com/cloudflare/cloudflared/releases/download/$v/cloudflared-darwin-amd64.tgz" "$file" "$CLOUDFLARED_SHA256"
  rm -rf "$dir"; mkdir -p "$dir"
  tar --no-same-owner -xzf "$CACHE_DIR/$file" -C "$dir"
  chmod 755 "$dir/cloudflared"
  unquarantine "$dir"
  activate_version cloudflared "$v"
  info "service setup is manual, see docs/06-rpc-exposure.md"
}

components=("$@")
if [[ ${#components[@]} -eq 0 ]]; then
  components=(nethermind)
  [[ "$CL_CLIENT" == "teku" ]] && components+=(jre teku)
  [[ "$LISTENER_ENABLED" == "true" ]] && components+=(node listener)
fi

for c in "${components[@]}"; do
  case "$c" in
    nethermind|teku|jre|node|listener|cloudflared) "install_$c" ;;
    lighthouse) die "lighthouse is built from source: scripts/25-build-lighthouse.sh" ;;
    *) die "unknown component: $c" ;;
  esac
done

echo
log "installed: ${components[*]}"
info "next: sudo scripts/30-services.sh install   (or gnosisctl restart <service> after an upgrade)"
