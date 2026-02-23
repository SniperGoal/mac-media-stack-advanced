#!/bin/bash
# One-shot upgrader: mac-media-stack -> mac-media-stack-advanced

set -euo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ADVANCED_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
BASIC_DIR="$HOME/mac-media-stack"
MEDIA_DIR=""
ASSUME_YES=false
NON_INTERACTIVE=false
SKIP_BACKUP=false
ENABLE_WATCHTOWER=false

usage() {
    cat <<EOF
Usage: bash scripts/upgrade-from-basic.sh [OPTIONS]

Upgrade an existing basic stack install to advanced using the same MEDIA_DIR.

Options:
  --basic-dir DIR         Basic repo path (default: ~/mac-media-stack)
  --media-dir DIR         Override media path (default: read from basic .env)
  --yes                   Run without confirmation prompt
  --non-interactive       Skip Seerr sign-in prompt during configure
  --skip-backup           Skip pre-upgrade backup snapshot
  --enable-watchtower     Start watchtower profile after upgrade
  --help                  Show this help message
EOF
}

require_arg() {
    local flag="$1"
    local value="${2:-}"
    if [[ -z "$value" || "$value" == --* ]]; then
        echo -e "${RED}FAIL${NC} Missing value for $flag"
        exit 1
    fi
    printf '%s\n' "$value"
}

expand_path() {
    local p="$1"
    p="${p/#\~/$HOME}"
    printf '%s\n' "$p"
}

log() { echo -e "  ${GREEN}OK${NC}  $1"; }
warn() { echo -e "  ${YELLOW}WARN${NC}  $1"; }
info() { echo -e "  ${CYAN}..${NC}  $1"; }
fail() { echo -e "  ${RED}FAIL${NC}  $1"; exit 1; }

env_get() {
    local file="$1"
    local key="$2"
    if [[ ! -f "$file" ]]; then
        return 0
    fi
    awk -F= -v key="$key" '$1 == key { sub(/^[^=]*=/, "", $0); print; exit }' "$file"
}

env_set() {
    local file="$1"
    local key="$2"
    local value="$3"
    local tmp

    tmp="$(mktemp)"
    awk -v key="$key" -v value="$value" '
        BEGIN { done = 0 }
        $0 ~ "^" key "=" {
            print key "=" value
            done = 1
            next
        }
        { print }
        END {
            if (!done) {
                print key "=" value
            }
        }
    ' "$file" > "$tmp"
    mv "$tmp" "$file"
}

copy_env_key_if_set() {
    local src="$1"
    local dst="$2"
    local key="$3"
    local value

    value="$(env_get "$src" "$key")"
    if [[ -n "${value:-}" ]]; then
        env_set "$dst" "$key" "$value"
    fi
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --basic-dir)
            BASIC_DIR="$(require_arg --basic-dir "${2:-}")"
            shift 2
            ;;
        --media-dir)
            MEDIA_DIR="$(require_arg --media-dir "${2:-}")"
            shift 2
            ;;
        --yes)
            ASSUME_YES=true
            shift
            ;;
        --non-interactive)
            NON_INTERACTIVE=true
            shift
            ;;
        --skip-backup)
            SKIP_BACKUP=true
            shift
            ;;
        --enable-watchtower)
            ENABLE_WATCHTOWER=true
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

BASIC_DIR="$(expand_path "$BASIC_DIR")"
ADVANCED_DIR="$(expand_path "$ADVANCED_DIR")"
if [[ -n "$MEDIA_DIR" ]]; then
    MEDIA_DIR="$(expand_path "$MEDIA_DIR")"
fi

BASIC_ENV="$BASIC_DIR/.env"
ADVANCED_ENV="$ADVANCED_DIR/.env"
ADVANCED_ENV_EXAMPLE="$ADVANCED_DIR/.env.example"

echo ""
echo "=============================================="
echo "  Upgrade: mac-media-stack -> advanced"
echo "=============================================="
echo ""

command -v docker >/dev/null 2>&1 || fail "docker not found"
command -v git >/dev/null 2>&1 || fail "git not found"

if ! docker info &>/dev/null; then
    fail "Docker/OrbStack is not running. Start it and rerun."
fi
log "Container runtime is running"

[[ -d "$BASIC_DIR" ]] || fail "Basic repo not found at $BASIC_DIR"
[[ -f "$BASIC_DIR/docker-compose.yml" ]] || fail "Basic docker-compose.yml not found at $BASIC_DIR"
[[ -f "$BASIC_ENV" ]] || fail "Basic .env not found at $BASIC_ENV"
[[ -f "$ADVANCED_DIR/docker-compose.yml" ]] || fail "Advanced docker-compose.yml not found at $ADVANCED_DIR"
[[ -f "$ADVANCED_ENV_EXAMPLE" ]] || fail "Missing .env.example in advanced repo"
[[ "$BASIC_DIR" != "$ADVANCED_DIR" ]] || fail "Basic and advanced paths must be different"

if [[ -z "$MEDIA_DIR" ]]; then
    MEDIA_DIR="$(env_get "$BASIC_ENV" "MEDIA_DIR")"
fi
MEDIA_DIR="$(expand_path "${MEDIA_DIR:-$HOME/Media}")"

echo "Basic repo:    $BASIC_DIR"
echo "Advanced repo: $ADVANCED_DIR"
echo "Media dir:     $MEDIA_DIR"
echo ""

if [[ "$ASSUME_YES" != true ]]; then
    read -r -p "Proceed with upgrade? [y/N] " confirm
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Cancelled."
        exit 0
    fi
fi

BACKUP_DIR="(skipped)"
if [[ "$SKIP_BACKUP" != true ]]; then
    BACKUP_DIR="$HOME/media-stack-upgrade-backup/$(date +%Y%m%d-%H%M%S)"
    info "Creating backup snapshot at $BACKUP_DIR"
    mkdir -p "$BACKUP_DIR"
    cp -a "$BASIC_ENV" "$BACKUP_DIR/basic.env"
    [[ -f "$ADVANCED_ENV" ]] && cp -a "$ADVANCED_ENV" "$BACKUP_DIR/advanced.env.pre-upgrade"
    [[ -d "$MEDIA_DIR/config" ]] && cp -a "$MEDIA_DIR/config" "$BACKUP_DIR/media-config" || warn "No config dir at $MEDIA_DIR/config"
    [[ -d "$MEDIA_DIR/state" ]] && cp -a "$MEDIA_DIR/state" "$BACKUP_DIR/media-state" || true
    [[ -d "$MEDIA_DIR/logs" ]] && cp -a "$MEDIA_DIR/logs" "$BACKUP_DIR/media-logs" || true
    log "Backup snapshot created"
else
    warn "Skipping backup (--skip-backup)"
fi

info "Preparing advanced folders/config templates"
(cd "$ADVANCED_DIR" && bash scripts/setup.sh --media-dir "$MEDIA_DIR")

[[ -f "$ADVANCED_ENV" ]] || fail "Advanced .env missing after setup"

env_set "$ADVANCED_ENV" "MEDIA_DIR" "$MEDIA_DIR"
copy_env_key_if_set "$BASIC_ENV" "$ADVANCED_ENV" "PUID"
copy_env_key_if_set "$BASIC_ENV" "$ADVANCED_ENV" "PGID"
copy_env_key_if_set "$BASIC_ENV" "$ADVANCED_ENV" "TIMEZONE"
copy_env_key_if_set "$BASIC_ENV" "$ADVANCED_ENV" "SEERR_BIND_IP"
copy_env_key_if_set "$BASIC_ENV" "$ADVANCED_ENV" "MEDIA_SERVER"
copy_env_key_if_set "$BASIC_ENV" "$ADVANCED_ENV" "TDARR_MODE"
copy_env_key_if_set "$BASIC_ENV" "$ADVANCED_ENV" "TDARR_VERSION"

wg_priv="$(env_get "$BASIC_ENV" "WIREGUARD_PRIVATE_KEY")"
wg_addr="$(env_get "$BASIC_ENV" "WIREGUARD_ADDRESSES")"
if [[ -n "$wg_priv" && "$wg_priv" != "your_wireguard_private_key_here" ]]; then
    env_set "$ADVANCED_ENV" "WIREGUARD_PRIVATE_KEY" "$wg_priv"
fi
if [[ -n "$wg_addr" && "$wg_addr" != "your_wireguard_address_here" ]]; then
    env_set "$ADVANCED_ENV" "WIREGUARD_ADDRESSES" "$wg_addr"
fi
chmod 600 "$ADVANCED_ENV"
log "Advanced .env updated from basic settings"

MEDIA_SERVER="$(env_get "$ADVANCED_ENV" "MEDIA_SERVER")"
MEDIA_SERVER="${MEDIA_SERVER:-plex}"
TDARR_MODE="$(env_get "$ADVANCED_ENV" "TDARR_MODE")"
TDARR_MODE="${TDARR_MODE:-native}"
if [[ "$TDARR_MODE" != "native" && "$TDARR_MODE" != "docker" ]]; then
    warn "Invalid TDARR_MODE '$TDARR_MODE' in advanced .env; defaulting to native"
    TDARR_MODE="native"
fi
env_set "$ADVANCED_ENV" "TDARR_MODE" "$TDARR_MODE"

BASIC_MEDIA_SERVER="$(env_get "$BASIC_ENV" "MEDIA_SERVER")"
BASIC_MEDIA_SERVER="${BASIC_MEDIA_SERVER:-plex}"

info "Running advanced preflight checks"
(cd "$ADVANCED_DIR" && bash scripts/doctor.sh --media-dir "$MEDIA_DIR")

info "Stopping basic stack"
(cd "$BASIC_DIR" && docker compose down)
log "Basic stack stopped"

info "Starting advanced stack"
COMPOSE_ARGS=()
if [[ "$MEDIA_SERVER" == "jellyfin" ]]; then
    COMPOSE_ARGS+=(--profile jellyfin)
fi
if [[ "$TDARR_MODE" == "docker" ]]; then
    COMPOSE_ARGS+=(--profile tdarr-docker)
fi
(cd "$ADVANCED_DIR" && docker compose "${COMPOSE_ARGS[@]}" up -d)
log "Advanced stack started"

if [[ "$TDARR_MODE" == "native" ]]; then
    info "Setting up native Tdarr"
    (cd "$ADVANCED_DIR" && bash scripts/setup-tdarr-native.sh --media-dir "$MEDIA_DIR")
fi

info "Running auto-configuration"
if [[ "$NON_INTERACTIVE" == true ]]; then
    (cd "$ADVANCED_DIR" && bash scripts/configure.sh --non-interactive)
else
    (cd "$ADVANCED_DIR" && bash scripts/configure.sh)
fi

info "Installing automation jobs"
(cd "$ADVANCED_DIR" && bash scripts/install-launchd-jobs.sh)

if [[ "$ENABLE_WATCHTOWER" == true ]]; then
    info "Enabling watchtower profile"
    (cd "$ADVANCED_DIR" && docker compose --profile autoupdate up -d watchtower)
fi

info "Running health check"
set +e
(cd "$ADVANCED_DIR" && bash scripts/health-check.sh)
health_status=$?
set -e

echo ""
echo "=============================================="
if [[ $health_status -eq 0 ]]; then
    echo -e "  ${GREEN}Upgrade complete${NC}"
else
    echo -e "  ${YELLOW}Upgrade finished with warnings${NC}"
fi
echo "=============================================="
echo ""
echo "Backup path: $BACKUP_DIR"
echo ""
echo "Remaining manual steps:"
if [[ "$MEDIA_SERVER" == "plex" ]]; then
    echo "  1. Set Kometa keys in $MEDIA_DIR/config/kometa/config.yml"
    echo "     - PLEX_TOKEN"
    echo "     - TMDB API key"
    echo "  2. In Tdarr, add libraries and assign 'Quality-First HEVC (Resolution Preserving)'"
else
    echo "  1. In Tdarr, add libraries and assign 'Quality-First HEVC (Resolution Preserving)'"
    echo "  2. Open Jellystat at http://localhost:3000 and connect to http://jellyfin:8096"
    echo "  3. If prompted, restart Jellyfin to finish Intro Skipper/TMDb Box Sets plugin activation"
fi
echo ""
echo "Rollback (if needed):"
echo "  cd $ADVANCED_DIR && docker compose down"
if [[ "$BASIC_MEDIA_SERVER" == "jellyfin" ]]; then
    echo "  cd $BASIC_DIR && docker compose --profile jellyfin up -d"
else
    echo "  cd $BASIC_DIR && docker compose up -d"
fi
echo ""
