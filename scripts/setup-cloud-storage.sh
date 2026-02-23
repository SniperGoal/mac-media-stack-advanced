#!/bin/bash
# Cloud Storage Setup (rclone + mergerfs)
# Creates directories, configures rclone remote, writes cloud storage env vars.
# Usage: bash scripts/setup-cloud-storage.sh [--media-dir DIR] [--non-interactive] [--help]

set -e

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/media-path.sh
source "$SCRIPT_DIR/scripts/lib/media-path.sh"

NON_INTERACTIVE=false

usage() {
    cat <<EOF
Usage: bash scripts/setup-cloud-storage.sh [OPTIONS]

Sets up rclone + mergerfs cloud storage integration.

Options:
  --media-dir DIR       Media root path (default: from .env, otherwise ~/Media)
  --non-interactive     Skip interactive prompts (requires RCLONE_REMOTE in .env)
  --help                Show this help message
EOF
}

MEDIA_DIR_OVERRIDE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --media-dir)
            if [[ $# -lt 2 || "$2" == --* ]]; then
                echo "Missing value for --media-dir"
                exit 1
            fi
            MEDIA_DIR_OVERRIDE="$2"
            shift 2
            ;;
        --non-interactive)
            NON_INTERACTIVE=true
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

if [[ -n "$MEDIA_DIR_OVERRIDE" ]]; then
    MEDIA_DIR="$MEDIA_DIR_OVERRIDE"
else
    MEDIA_DIR="$(resolve_media_dir "$SCRIPT_DIR")"
fi

echo ""
echo "=============================="
echo "  Cloud Storage Setup"
echo "=============================="
echo ""

MEDIA_SERVER="plex"
TDARR_MODE="native"
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    env_server=$(sed -n 's/^MEDIA_SERVER=//p' "$SCRIPT_DIR/.env" | head -1)
    env_tdarr_mode=$(sed -n 's/^TDARR_MODE=//p' "$SCRIPT_DIR/.env" | head -1)
    [[ -n "$env_server" ]] && MEDIA_SERVER="$env_server"
    [[ -n "$env_tdarr_mode" ]] && TDARR_MODE="$env_tdarr_mode"
fi

if [[ "$MEDIA_SERVER" != "jellyfin" ]]; then
    echo -e "${YELLOW}WARN${NC}  Cloud merged mounts are only readable by Docker containers on macOS."
    echo "      Native Plex cannot read merged cloud mount paths."
    echo "      Use Jellyfin for cloud-backed playback (set MEDIA_SERVER=jellyfin)."
    echo ""
fi

if [[ "$TDARR_MODE" == "native" ]]; then
    echo -e "${YELLOW}WARN${NC}  Native Tdarr cannot read merged cloud mount paths."
    echo "      Use TDARR_MODE=docker when cloud storage is enabled."
    echo ""
fi

# Warn if free space is low for VFS cache + active downloads
available_kb=$(df -k "$MEDIA_DIR" 2>/dev/null | awk 'NR==2 {print $4}')
if [[ -n "$available_kb" && "$available_kb" =~ ^[0-9]+$ ]]; then
    available_gb=$((available_kb / 1024 / 1024))
    if ((available_gb < 100)); then
        echo -e "${YELLOW}WARN${NC}  Only ~${available_gb}GB free at $MEDIA_DIR."
        echo "      Cloud VFS cache + active downloads can consume space quickly."
        echo "      Recommended free space: at least 100GB."
        echo ""
    fi
fi

# Create directories
echo "Creating cloud storage directories..."
mkdir -p "$MEDIA_DIR"/{config/rclone,cloud,merged}
echo -e "  ${GREEN}Done${NC}"
echo ""

# Check for existing rclone.conf
RCLONE_CONF="$MEDIA_DIR/config/rclone/rclone.conf"

if [[ -f "$RCLONE_CONF" ]]; then
    echo -e "${GREEN}Found${NC} existing rclone.conf at $RCLONE_CONF"
    echo ""
else
    if [[ "$NON_INTERACTIVE" == true ]]; then
        echo -e "${YELLOW}WARN${NC}  No rclone.conf found. Create one manually at:"
        echo "  $RCLONE_CONF"
        echo ""
        echo "  Or copy the example:"
        echo "  cp $SCRIPT_DIR/configs/rclone.conf.example $RCLONE_CONF"
    else
        echo "No rclone.conf found. How would you like to configure your cloud remote?"
        echo ""
        echo "  1) Run rclone config wizard (interactive, in Docker)"
        echo "  2) Copy an existing rclone.conf from another location"
        echo "  3) Skip (configure manually later)"
        echo ""
        read -p "  Choice [1/2/3]: " choice
        echo ""

        case "$choice" in
            1)
                echo -e "${CYAN}Starting rclone config wizard...${NC}"
                echo "  (This runs inside Docker. Follow the prompts to set up your remote.)"
                echo ""
                docker run --rm -it \
                    -v "$MEDIA_DIR/config/rclone:/config/rclone" \
                    rclone/rclone config
                echo ""
                ;;
            2)
                read -p "  Path to existing rclone.conf: " existing_conf
                existing_conf="${existing_conf/#\~/$HOME}"
                if [[ -f "$existing_conf" ]]; then
                    cp "$existing_conf" "$RCLONE_CONF"
                    echo -e "  ${GREEN}Copied${NC}"
                else
                    echo -e "  ${RED}File not found:${NC} $existing_conf"
                    echo "  You can copy it manually later to: $RCLONE_CONF"
                fi
                echo ""
                ;;
            3|*)
                echo "  Skipped. Copy your rclone.conf to: $RCLONE_CONF"
                echo "  Or copy the example: cp $SCRIPT_DIR/configs/rclone.conf.example $RCLONE_CONF"
                echo ""
                ;;
        esac
    fi
fi

# Get remote name and path
RCLONE_REMOTE=""
RCLONE_REMOTE_PATH=""

if [[ -f "$SCRIPT_DIR/.env" ]]; then
    existing_remote=$(sed -n 's/^RCLONE_REMOTE=//p' "$SCRIPT_DIR/.env" | head -1)
    existing_path=$(sed -n 's/^RCLONE_REMOTE_PATH=//p' "$SCRIPT_DIR/.env" | head -1)
    if [[ -n "$existing_remote" ]]; then
        RCLONE_REMOTE="$existing_remote"
        RCLONE_REMOTE_PATH="${existing_path:-}"
    fi
fi

if [[ -z "$RCLONE_REMOTE" && "$NON_INTERACTIVE" == false ]]; then
    if [[ -f "$RCLONE_CONF" ]]; then
        echo "Available remotes in your rclone.conf:"
        grep '^\[' "$RCLONE_CONF" | tr -d '[]' | while read -r name; do
            echo "  - $name"
        done
        echo ""
    fi

    read -p "  Remote name (from rclone.conf): " RCLONE_REMOTE
    read -p "  Remote path (leave empty for root): " RCLONE_REMOTE_PATH
    echo ""
fi

if [[ -z "$RCLONE_REMOTE" ]]; then
    echo -e "${YELLOW}WARN${NC}  No remote configured. Set RCLONE_REMOTE in .env before starting."
else
    echo -e "  Remote: ${GREEN}${RCLONE_REMOTE}:${RCLONE_REMOTE_PATH}${NC}"
fi

# Write to .env
ENV_FILE="$SCRIPT_DIR/.env"
if [[ -f "$ENV_FILE" ]]; then
    # Append or update cloud storage vars
    for var in CLOUD_STORAGE_ENABLED RCLONE_REMOTE RCLONE_REMOTE_PATH; do
        if grep -q "^${var}=" "$ENV_FILE" 2>/dev/null; then
            case "$var" in
                CLOUD_STORAGE_ENABLED) sed -i '' "s|^${var}=.*|${var}=true|" "$ENV_FILE" ;;
                RCLONE_REMOTE) [[ -n "$RCLONE_REMOTE" ]] && sed -i '' "s|^${var}=.*|${var}=$RCLONE_REMOTE|" "$ENV_FILE" ;;
                RCLONE_REMOTE_PATH) sed -i '' "s|^${var}=.*|${var}=$RCLONE_REMOTE_PATH|" "$ENV_FILE" ;;
            esac
        elif grep -q "^# ${var}=" "$ENV_FILE" 2>/dev/null; then
            case "$var" in
                CLOUD_STORAGE_ENABLED) sed -i '' "s|^# ${var}=.*|${var}=true|" "$ENV_FILE" ;;
                RCLONE_REMOTE) [[ -n "$RCLONE_REMOTE" ]] && sed -i '' "s|^# ${var}=.*|${var}=$RCLONE_REMOTE|" "$ENV_FILE" ;;
                RCLONE_REMOTE_PATH) sed -i '' "s|^# ${var}=.*|${var}=$RCLONE_REMOTE_PATH|" "$ENV_FILE" ;;
            esac
        else
            case "$var" in
                CLOUD_STORAGE_ENABLED) printf '\n%s=true\n' "$var" >> "$ENV_FILE" ;;
                RCLONE_REMOTE) [[ -n "$RCLONE_REMOTE" ]] && printf '%s=%s\n' "$var" "$RCLONE_REMOTE" >> "$ENV_FILE" ;;
                RCLONE_REMOTE_PATH) printf '%s=%s\n' "$var" "$RCLONE_REMOTE_PATH" >> "$ENV_FILE" ;;
            esac
        fi
    done

    # Add VFS cache defaults if not present
    for default_var in "RCLONE_VFS_CACHE_MODE=full" "RCLONE_VFS_CACHE_MAX_SIZE=50G" "RCLONE_VFS_CACHE_MAX_AGE=72h" "RCLONE_VFS_READ_CHUNK_SIZE=128M" "CLOUD_UPLOAD_MIN_AGE_HOURS=24"; do
        var_name="${default_var%%=*}"
        if ! grep -q "^${var_name}=" "$ENV_FILE" 2>/dev/null && ! grep -q "^# ${var_name}=" "$ENV_FILE" 2>/dev/null; then
            printf '# %s\n' "$default_var" >> "$ENV_FILE"
        fi
    done

    echo -e "  ${GREEN}Updated .env${NC}"
else
    echo -e "  ${YELLOW}WARN${NC}  No .env file found. Run scripts/setup.sh first."
fi

# Create remote directories
if [[ -n "$RCLONE_REMOTE" && -f "$RCLONE_CONF" ]]; then
    echo ""
    echo "Creating remote directories..."
    docker run --rm \
        -v "$MEDIA_DIR/config/rclone:/config/rclone" \
        rclone/rclone mkdir "${RCLONE_REMOTE}:${RCLONE_REMOTE_PATH:+${RCLONE_REMOTE_PATH}/}Movies" 2>/dev/null && \
        echo -e "  ${GREEN}OK${NC}  ${RCLONE_REMOTE}:Movies" || \
        echo -e "  ${YELLOW}WARN${NC}  Could not create Movies on remote"

    docker run --rm \
        -v "$MEDIA_DIR/config/rclone:/config/rclone" \
        rclone/rclone mkdir "${RCLONE_REMOTE}:${RCLONE_REMOTE_PATH:+${RCLONE_REMOTE_PATH}/}TV Shows" 2>/dev/null && \
        echo -e "  ${GREEN}OK${NC}  ${RCLONE_REMOTE}:TV Shows" || \
        echo -e "  ${YELLOW}WARN${NC}  Could not create TV Shows on remote"
fi

# Disk space warning
available_gb=$(df -g "$MEDIA_DIR" 2>/dev/null | awk 'NR==2{print $4}' || echo "0")
if [[ "$available_gb" -lt 100 && "$available_gb" -gt 0 ]]; then
    echo ""
    echo -e "  ${YELLOW}WARN${NC}  Only ${available_gb}GB free on $(df "$MEDIA_DIR" | awk 'NR==2{print $1}')"
    echo "  VFS cache defaults to 50GB. Adjust RCLONE_VFS_CACHE_MAX_SIZE in .env if needed."
fi

echo ""
echo "=============================="
echo "  Cloud storage setup complete!"
echo "=============================="
echo ""
echo "Next steps:"
echo "  1. Verify your rclone.conf at: $RCLONE_CONF"
echo "  2. Start with cloud storage:"
echo "     docker compose -f docker-compose.yml -f docker-compose.cloud-storage.yml --profile cloud-storage up -d"
echo ""
echo "  Or use bootstrap.sh --cloud-storage for a full install."
echo ""
echo "Optional - Periodic cloud upload:"
echo "  bash scripts/install-launchd-jobs.sh  (installs cloud-upload every 6 hours)"
echo ""
