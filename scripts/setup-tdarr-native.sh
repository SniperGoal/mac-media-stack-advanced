#!/bin/bash
# Native Tdarr installer/manager for macOS.
# Downloads Tdarr Server + Node, installs launchd services, and applies quality flow preset.
# Usage: bash scripts/setup-tdarr-native.sh [--media-dir DIR] [--version X.Y.ZZ] [--install-only] [--skip-flow]

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/media-path.sh
source "$SCRIPT_DIR/scripts/lib/media-path.sh"

MEDIA_DIR=""
TDARR_VERSION=""
INSTALL_ONLY=false
SKIP_FLOW=false

LABEL_SERVER="com.media-stack.tdarr.server"
LABEL_NODE="com.media-stack.tdarr.node"

usage() {
    cat <<EOF
Usage: bash scripts/setup-tdarr-native.sh [OPTIONS]

Options:
  --media-dir DIR       Media root path (default: from .env or ~/Media)
  --version VERSION     Tdarr version to install (default: TDARR_VERSION or latest)
  --install-only        Do not download/update (reuse existing release)
  --skip-flow           Skip applying quality flow preset
  --help                Show this help message
EOF
}

require_arg() {
    local flag="$1"
    local value="${2:-}"
    if [[ -z "$value" || "$value" == --* ]]; then
        echo "Missing value for $flag"
        exit 1
    fi
    printf '%s\n' "$value"
}

log() { echo -e "${GREEN}OK${NC}  $1"; }
warn() { echo -e "${YELLOW}WARN${NC}  $1"; }
info() { echo -e "${CYAN}..${NC}  $1"; }
fail() { echo -e "${RED}FAIL${NC}  $1"; exit 1; }

while [[ $# -gt 0 ]]; do
    case "$1" in
        --media-dir)
            MEDIA_DIR="$(require_arg --media-dir "${2:-}")"
            shift 2
            ;;
        --version)
            TDARR_VERSION="$(require_arg --version "${2:-}")"
            shift 2
            ;;
        --install-only)
            INSTALL_ONLY=true
            shift
            ;;
        --skip-flow)
            SKIP_FLOW=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            usage
            exit 1
            ;;
    esac
done

if [[ -z "$MEDIA_DIR" ]]; then
    MEDIA_DIR="$(resolve_media_dir "$SCRIPT_DIR")"
fi
MEDIA_DIR="${MEDIA_DIR/#\~/$HOME}"

if [[ -z "$TDARR_VERSION" && -f "$SCRIPT_DIR/.env" ]]; then
    TDARR_VERSION="$(sed -n 's/^TDARR_VERSION=//p' "$SCRIPT_DIR/.env" | head -1)"
fi

TDARR_STATE_DIR="$MEDIA_DIR/config/tdarr"
TDARR_NATIVE_DIR="$MEDIA_DIR/config/tdarr-native"
TDARR_RELEASES_DIR="$TDARR_NATIVE_DIR/releases"
CACHE_DIR="$MEDIA_DIR/tdarr-transcode-cache"
LAUNCH_DIR="$HOME/Library/LaunchAgents"
LAUNCH_LOG_DIR="$MEDIA_DIR/logs/launchd"

server_bin=""
node_bin=""

detect_platform() {
    local arch
    arch="$(uname -m)"
    case "$arch" in
        arm64|aarch64)
            echo "darwin_arm64"
            ;;
        x86_64)
            echo "darwin_x64"
            ;;
        *)
            fail "Unsupported macOS architecture: $arch"
            ;;
    esac
}

find_binary() {
    local root="$1"
    local target="$2"
    find "$root" -type f -name "$target" | head -1
}

resolve_release_urls() {
    local versions_file="$1"
    local platform="$2"
    local selected_version="$3"

    if [[ -z "$selected_version" ]]; then
        selected_version="$(jq -r 'keys[]' "$versions_file" | sort -V | tail -1)"
    fi

    local server_url node_url
    server_url="$(jq -r --arg v "$selected_version" --arg p "$platform" '.[$v][$p].Tdarr_Server // empty' "$versions_file")"
    node_url="$(jq -r --arg v "$selected_version" --arg p "$platform" '.[$v][$p].Tdarr_Node // empty' "$versions_file")"

    if [[ -z "$server_url" || -z "$node_url" ]]; then
        fail "Could not resolve Tdarr assets for version=$selected_version platform=$platform"
    fi

    printf '%s|%s|%s\n' "$selected_version" "$server_url" "$node_url"
}

write_tdarr_plist() {
    local label="$1"
    local binary_path="$2"
    local mode="$3"
    local plist="$LAUNCH_DIR/$label.plist"

    cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key>
  <string>$label</string>
  <key>ProgramArguments</key>
  <array>
    <string>$binary_path</string>
  </array>
  <key>WorkingDirectory</key>
  <string>$TDARR_STATE_DIR</string>
  <key>EnvironmentVariables</key>
  <dict>
    <key>PATH</key>
    <string>/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin</string>
    <key>rootDataPath</key>
    <string>$TDARR_STATE_DIR</string>
EOF

    if [[ "$mode" == "node" ]]; then
        cat >> "$plist" <<EOF
    <key>nodeName</key>
    <string>$(hostname -s)-tdarr-node</string>
    <key>serverURL</key>
    <string>http://127.0.0.1:8266</string>
    <key>serverIP</key>
    <string>127.0.0.1</string>
    <key>serverPort</key>
    <string>8266</string>
EOF
    else
        cat >> "$plist" <<EOF
    <key>serverIP</key>
    <string>0.0.0.0</string>
    <key>serverPort</key>
    <string>8266</string>
    <key>webUIPort</key>
    <string>8265</string>
EOF
    fi

    cat >> "$plist" <<EOF
  </dict>
  <key>RunAtLoad</key>
  <true/>
  <key>KeepAlive</key>
  <true/>
  <key>StandardOutPath</key>
  <string>$LAUNCH_LOG_DIR/$label.out.log</string>
  <key>StandardErrorPath</key>
  <string>$LAUNCH_LOG_DIR/$label.err.log</string>
</dict>
</plist>
EOF
}

reload_label() {
    local label="$1"
    local plist="$LAUNCH_DIR/$label.plist"
    launchctl unload "$plist" >/dev/null 2>&1 || true
    launchctl load "$plist"
    launchctl kickstart -k "gui/$UID/$label" >/dev/null 2>&1 || true
}

wait_tdarr_ui() {
    local attempts=30
    local status="000"
    for _ in $(seq 1 "$attempts"); do
        status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://127.0.0.1:8265" 2>/dev/null || true)
        if [[ "$status" =~ ^(200|301|302|307|401|403)$ ]]; then
            return 0
        fi
        sleep 3
    done
    return 1
}

require_tools() {
    local required=(curl jq unzip launchctl)
    for bin in "${required[@]}"; do
        command -v "$bin" >/dev/null 2>&1 || fail "Missing required command: $bin"
    done
}

install_release() {
    local version="$1"
    local server_url="$2"
    local node_url="$3"

    local release_dir="$TDARR_RELEASES_DIR/$version"
    local server_zip="$release_dir/Tdarr_Server.zip"
    local node_zip="$release_dir/Tdarr_Node.zip"
    local server_extract_dir="$release_dir/server"
    local node_extract_dir="$release_dir/node"

    mkdir -p "$release_dir" "$server_extract_dir" "$node_extract_dir"

    if [[ ! -f "$server_zip" ]]; then
        info "Downloading Tdarr Server $version"
        curl -fsSL "$server_url" -o "$server_zip"
    fi
    if [[ ! -f "$node_zip" ]]; then
        info "Downloading Tdarr Node $version"
        curl -fsSL "$node_url" -o "$node_zip"
    fi

    unzip -oq "$server_zip" -d "$server_extract_dir"
    unzip -oq "$node_zip" -d "$node_extract_dir"
    xattr -dr com.apple.quarantine "$release_dir" >/dev/null 2>&1 || true

    server_bin="$(find_binary "$server_extract_dir" "Tdarr_Server")"
    node_bin="$(find_binary "$node_extract_dir" "Tdarr_Node")"

    [[ -n "$server_bin" ]] || fail "Tdarr_Server binary not found in $server_extract_dir"
    [[ -n "$node_bin" ]] || fail "Tdarr_Node binary not found in $node_extract_dir"

    chmod +x "$server_bin" "$node_bin"
    ln -sfn "$release_dir" "$TDARR_NATIVE_DIR/current"
}

reuse_current_release() {
    local current_dir="$TDARR_NATIVE_DIR/current"
    [[ -L "$current_dir" || -d "$current_dir" ]] || fail "--install-only requested but no Tdarr release is installed"
    server_bin="$(find_binary "$current_dir/server" "Tdarr_Server")"
    node_bin="$(find_binary "$current_dir/node" "Tdarr_Node")"
    [[ -n "$server_bin" ]] || fail "Tdarr_Server binary not found under $current_dir/server"
    [[ -n "$node_bin" ]] || fail "Tdarr_Node binary not found under $current_dir/node"
    chmod +x "$server_bin" "$node_bin"
}

echo ""
echo "======================================="
echo "  Tdarr Native Setup"
echo "======================================="
echo ""
echo "Media dir: $MEDIA_DIR"
echo ""

require_tools
mkdir -p "$TDARR_RELEASES_DIR" "$TDARR_STATE_DIR"/{configs,logs,server} "$CACHE_DIR" "$LAUNCH_DIR" "$LAUNCH_LOG_DIR"

if [[ "$INSTALL_ONLY" == true ]]; then
    info "Using existing Tdarr release (install-only mode)"
    reuse_current_release
else
    platform="$(detect_platform)"
    versions_file="$(mktemp)"
    trap 'rm -f "${versions_file:-}"' EXIT
    info "Fetching Tdarr version catalog"
    curl -fsSL "https://storage.tdarr.io/versions.json" -o "$versions_file"
    resolved="$(resolve_release_urls "$versions_file" "$platform" "$TDARR_VERSION")"
    selected_version="${resolved%%|*}"
    resolved="${resolved#*|}"
    server_url="${resolved%%|*}"
    node_url="${resolved#*|}"
    info "Resolved version $selected_version ($platform)"
    install_release "$selected_version" "$server_url" "$node_url"
fi

write_tdarr_plist "$LABEL_SERVER" "$server_bin" "server"
write_tdarr_plist "$LABEL_NODE" "$node_bin" "node"

reload_label "$LABEL_SERVER"
sleep 5
reload_label "$LABEL_NODE"

if wait_tdarr_ui; then
    log "Tdarr is reachable at http://localhost:8265"
else
    fail "Tdarr launchd services installed but UI check failed. See logs in $LAUNCH_LOG_DIR"
fi

if [[ "$SKIP_FLOW" != true ]]; then
    if bash "$SCRIPT_DIR/scripts/tdarr-apply-quality-flow.sh" --media-dir "$MEDIA_DIR" --wait-seconds 120; then
        log "Quality-first Tdarr flow preset is ready"
    else
        warn "Could not apply Tdarr quality flow automatically (you can run scripts/tdarr-apply-quality-flow.sh later)"
    fi
fi

echo ""
log "Native Tdarr setup complete"
