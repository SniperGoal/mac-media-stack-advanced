#!/bin/bash
# Media Stack (Advanced) preflight checks (non-destructive)
# Usage: bash scripts/doctor.sh [--media-dir DIR] [--help]

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
ENV_FILE="$SCRIPT_DIR/.env"
MEDIA_DIR="$HOME/Media"

PASS=0
WARN=0
FAIL=0

usage() {
    cat <<EOF
Usage: bash scripts/doctor.sh [OPTIONS]

Run preflight checks before first startup.

Options:
  --media-dir DIR   Media root path (default: from .env, otherwise ~/Media)
  --help            Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --media-dir)
            if [[ $# -lt 2 || "$2" == --* ]]; then
                echo "Missing value for --media-dir"
                exit 1
            fi
            MEDIA_DIR="$2"
            shift 2
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

if [[ -f "$ENV_FILE" ]]; then
    env_media=$(sed -n 's/^MEDIA_DIR=//p' "$ENV_FILE" | head -1)
    if [[ -n "$env_media" ]]; then
        MEDIA_DIR="$env_media"
    fi
fi
MEDIA_DIR="${MEDIA_DIR/#\~/$HOME}"

# Read media server/tdarr choices
MEDIA_SERVER="plex"
TDARR_MODE="native"
if [[ -f "$ENV_FILE" ]]; then
    env_server=$(sed -n 's/^MEDIA_SERVER=//p' "$ENV_FILE" | head -1)
    if [[ -n "$env_server" ]]; then
        MEDIA_SERVER="$env_server"
    fi
    env_tdarr_mode=$(sed -n 's/^TDARR_MODE=//p' "$ENV_FILE" | head -1)
    if [[ -n "$env_tdarr_mode" ]]; then
        TDARR_MODE="$env_tdarr_mode"
    fi
fi

ok() { echo -e "  ${GREEN}OK${NC}   $1"; PASS=$((PASS + 1)); }
warn() { echo -e "  ${YELLOW}WARN${NC} $1"; WARN=$((WARN + 1)); }
fail() { echo -e "  ${RED}FAIL${NC} $1"; FAIL=$((FAIL + 1)); }

echo ""
echo "=============================="
echo "  Media Stack Doctor (Advanced)"
echo "=============================="
echo ""
echo -e "  ${CYAN}Info${NC}  Project: $SCRIPT_DIR"
echo -e "  ${CYAN}Info${NC}  Media dir: $MEDIA_DIR"
echo ""

for cmd in docker curl grep sed awk python3 jq unzip sqlite3; do
    if command -v "$cmd" >/dev/null 2>&1; then
        ok "Command found: $cmd"
    else
        fail "Missing command: $cmd"
    fi
done

if docker info >/dev/null 2>&1; then
    runtime=$(docker info --format '{{.OperatingSystem}}' 2>/dev/null || echo "Docker")
    ok "Container runtime running ($runtime)"
else
    fail "Container runtime is not running"
fi

if [[ -f "$ENV_FILE" ]]; then
    ok ".env exists"
    if grep -q '^WIREGUARD_PRIVATE_KEY=your_wireguard_private_key_here' "$ENV_FILE"; then
        fail "WIREGUARD_PRIVATE_KEY is still a placeholder in .env"
    else
        ok "WIREGUARD_PRIVATE_KEY appears set"
    fi

    if grep -q '^WIREGUARD_ADDRESSES=your_wireguard_address_here' "$ENV_FILE"; then
        fail "WIREGUARD_ADDRESSES is still a placeholder in .env"
    else
        ok "WIREGUARD_ADDRESSES appears set"
    fi
else
    fail ".env is missing (run: bash scripts/setup.sh)"
fi

if [[ -f "$SCRIPT_DIR/.env.nord" ]]; then
    ok ".env.nord exists (Nord fallback can be enabled)"
else
    warn ".env.nord missing (VPN failover will stay disabled until you add it)"
fi

for dir in \
    "$MEDIA_DIR" \
    "$MEDIA_DIR/Downloads" \
    "$MEDIA_DIR/Movies" \
    "$MEDIA_DIR/TV Shows" \
    "$MEDIA_DIR/config" \
    "$MEDIA_DIR/config/recyclarr" \
    "$MEDIA_DIR/config/kometa" \
    "$MEDIA_DIR/config/tdarr" \
    "$MEDIA_DIR/config/tdarr-native" \
    "$MEDIA_DIR/tdarr-transcode-cache" \
    "$MEDIA_DIR/backups"; do
    if [[ -d "$dir" ]]; then
        ok "Directory exists: $dir"
    else
        warn "Directory missing: $dir"
    fi
done

if [[ -f "$SCRIPT_DIR/docker-compose.yml" ]] && [[ -f "$ENV_FILE" ]]; then
    if docker compose -f "$SCRIPT_DIR/docker-compose.yml" config >/dev/null 2>&1; then
        ok "docker-compose.yml renders with current .env"
    else
        fail "docker-compose.yml failed to render (check .env values)"
    fi

    if [[ -f "$SCRIPT_DIR/docker-compose.nord-fallback.yml" && -f "$SCRIPT_DIR/.env.nord" ]]; then
        if docker compose -f "$SCRIPT_DIR/docker-compose.yml" -f "$SCRIPT_DIR/docker-compose.nord-fallback.yml" config >/dev/null 2>&1; then
            ok "Nord fallback compose override renders"
        else
            fail "Nord fallback compose override failed to render"
        fi
    fi

    if docker compose -f "$SCRIPT_DIR/docker-compose.yml" --profile tdarr-docker config >/dev/null 2>&1; then
        ok "docker-compose.yml renders with tdarr-docker profile"
    else
        fail "docker-compose.yml failed to render tdarr-docker profile"
    fi
fi

# Cloud storage checks
CLOUD_STORAGE_ENABLED=""
if [[ -f "$ENV_FILE" ]]; then
    CLOUD_STORAGE_ENABLED=$(sed -n 's/^CLOUD_STORAGE_ENABLED=//p' "$ENV_FILE" | head -1)
fi

if [[ "$CLOUD_STORAGE_ENABLED" == "true" ]]; then
    if [[ "$MEDIA_SERVER" != "jellyfin" ]]; then
        fail "CLOUD_STORAGE_ENABLED=true requires MEDIA_SERVER=jellyfin (native Plex cannot read Docker FUSE mounts on macOS)"
    else
        ok "Cloud storage compatibility check passed for Jellyfin"
    fi

    if [[ "$TDARR_MODE" == "native" ]]; then
        fail "CLOUD_STORAGE_ENABLED=true requires TDARR_MODE=docker (native Tdarr cannot read Docker FUSE mounts on macOS)"
    else
        ok "Cloud storage compatibility check passed for Tdarr mode ($TDARR_MODE)"
    fi

    rclone_conf="$MEDIA_DIR/config/rclone/rclone.conf"
    if [[ -f "$rclone_conf" ]]; then
        ok "rclone.conf exists"
    else
        fail "rclone.conf missing at $rclone_conf"
    fi

    env_remote=$(sed -n 's/^RCLONE_REMOTE=//p' "$ENV_FILE" | head -1)
    if [[ -n "$env_remote" ]]; then
        if [[ -f "$rclone_conf" ]] && grep -q "^\[$env_remote\]" "$rclone_conf" 2>/dev/null; then
            ok "RCLONE_REMOTE '$env_remote' found in rclone.conf"
        elif [[ -f "$rclone_conf" ]]; then
            fail "RCLONE_REMOTE '$env_remote' not found in rclone.conf"
        fi
    else
        fail "RCLONE_REMOTE not set in .env"
    fi

    for cdir in "$MEDIA_DIR/cloud" "$MEDIA_DIR/merged" "$MEDIA_DIR/config/rclone"; do
        if [[ -d "$cdir" ]]; then
            ok "Directory exists: $cdir"
        else
            warn "Directory missing: $cdir"
        fi
    done

    if [[ -f "$SCRIPT_DIR/docker-compose.cloud-storage.yml" ]]; then
        ok "docker-compose.cloud-storage.yml exists"
    else
        fail "docker-compose.cloud-storage.yml missing"
    fi

    if docker compose -f "$SCRIPT_DIR/docker-compose.yml" -f "$SCRIPT_DIR/docker-compose.cloud-storage.yml" --profile cloud-storage config >/dev/null 2>&1; then
        ok "Cloud storage compose renders with current .env"
    else
        fail "Cloud storage compose failed to render (check .env values)"
    fi

    if docker compose -f "$SCRIPT_DIR/docker-compose.yml" -f "$SCRIPT_DIR/docker-compose.cloud-storage.yml" --profile cloud-storage --profile jellyfin config >/dev/null 2>&1; then
        ok "Cloud storage compose renders with jellyfin profile"
    else
        fail "Cloud storage compose failed to render jellyfin profile"
    fi

    if docker compose -f "$SCRIPT_DIR/docker-compose.yml" -f "$SCRIPT_DIR/docker-compose.cloud-storage.yml" --profile cloud-storage --profile tdarr-docker config >/dev/null 2>&1; then
        ok "Cloud storage compose renders with tdarr-docker profile"
    else
        fail "Cloud storage compose failed to render tdarr-docker profile"
    fi
fi

PORTS="5055 9696 8989 7878 8080 6767 8191 8265 8266"
if [[ "$MEDIA_SERVER" == "jellyfin" ]]; then
    PORTS="$PORTS 8096"
else
    PORTS="$PORTS 32400"
fi
for port in $PORTS; do
    owner=$(lsof -nP -iTCP:"$port" -sTCP:LISTEN 2>/dev/null | awk 'NR==2{print $1}')
    if [[ -z "$owner" ]]; then
        ok "Port $port is free"
    else
        warn "Port $port already in use by $owner"
    fi
done

if [[ "$TDARR_MODE" == "native" || "$TDARR_MODE" == "docker" ]]; then
    ok "Tdarr mode: $TDARR_MODE"
else
    fail "Invalid TDARR_MODE '$TDARR_MODE' (expected native or docker)"
fi

if [[ "$TDARR_MODE" == "native" ]]; then
    if command -v launchctl >/dev/null 2>&1; then
        ok "launchctl available for native Tdarr"
    else
        fail "launchctl missing (required for TDARR_MODE=native)"
    fi
fi

if [[ "$MEDIA_SERVER" == "jellyfin" ]]; then
    ok "Media server: Jellyfin (Docker)"
else
    if [[ -d "/Applications/Plex Media Server.app" ]] || pgrep -x "Plex Media Server" >/dev/null 2>&1; then
        ok "Plex Media Server detected"
    else
        warn "Plex Media Server not detected yet"
    fi
fi

echo ""
echo "=============================="
echo -e "  Results: ${GREEN}$PASS passed${NC}, ${YELLOW}$WARN warnings${NC}, ${RED}$FAIL failed${NC}"
echo "=============================="
echo ""

if [[ $FAIL -gt 0 ]]; then
    echo "Resolve FAIL items first, then run this again."
    exit 1
fi

echo "Preflight checks passed."
