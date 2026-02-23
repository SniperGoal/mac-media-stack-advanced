#!/bin/bash
# Media Stack Setup Helper (Advanced)
# Creates folders, prepares .env, and seeds config templates.
# Usage: bash scripts/setup.sh [--media-dir DIR] [--help]

set -e

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

usage() {
    cat <<EOF
Usage: bash scripts/setup.sh [OPTIONS]

Creates Media folder structure, generates .env, and copies config templates.

Options:
  --media-dir DIR   Media root path (default: ~/Media)
  --help            Show this help message
EOF
}

MEDIA_DIR_OVERRIDE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --media-dir)
            if [[ $# -lt 2 || "$2" == --* ]]; then
                echo "Missing value for --media-dir"
                usage
                exit 1
            fi
            MEDIA_DIR_OVERRIDE="$2"
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

echo ""
echo "=============================="
echo "  Media Stack Setup (Advanced)"
echo "=============================="
echo ""

CURRENT_USER=$(whoami)
HOME_DIR=$(eval echo ~$CURRENT_USER)
MEDIA_DIR="${MEDIA_DIR_OVERRIDE:-$HOME_DIR/Media}"
MEDIA_DIR="${MEDIA_DIR/#\~/$HOME}"
USER_PUID=$(id -u)
USER_PGID=$(id -g)

echo "Detected user: $CURRENT_USER"
echo "Media folder will be: $MEDIA_DIR"
echo ""

# Create folder structure
echo "Creating folders..."
mkdir -p "$MEDIA_DIR"/{config,Downloads,Movies,"TV Shows",logs,state,backups,tdarr-transcode-cache}
mkdir -p "$MEDIA_DIR"/config/{qbittorrent,prowlarr,sonarr,radarr,bazarr,seerr,kometa,recyclarr}
mkdir -p "$MEDIA_DIR"/config/tdarr/{server,configs,logs}
mkdir -p "$MEDIA_DIR"/config/tdarr-native/{releases}
mkdir -p "$MEDIA_DIR"/config/jellystat/{db,backup}
echo -e "  ${GREEN}Done${NC}"
echo ""

# Create .env from example
# Generate Jellystat secrets if not already set
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    source "$SCRIPT_DIR/.env"
fi
if [[ -z "${JELLYSTAT_JWT_SECRET:-}" ]]; then
    JELLYSTAT_JWT_SECRET=$(openssl rand -hex 32)
    echo "  Generated JELLYSTAT_JWT_SECRET"
fi
if [[ -z "${JELLYSTAT_DB_PASSWORD:-}" ]]; then
    JELLYSTAT_DB_PASSWORD=$(openssl rand -hex 16)
    echo "  Generated JELLYSTAT_DB_PASSWORD"
fi

if [[ -f "$SCRIPT_DIR/.env" ]]; then
    echo -e "${YELLOW}Note:${NC} .env already exists. Skipping creation."
    # Write Jellystat secrets if missing from existing .env
    if ! grep -q "^JELLYSTAT_JWT_SECRET=" "$SCRIPT_DIR/.env" 2>/dev/null; then
        printf '\nJELLYSTAT_JWT_SECRET=%s\n' "$JELLYSTAT_JWT_SECRET" >> "$SCRIPT_DIR/.env"
    elif grep -q "^JELLYSTAT_JWT_SECRET=$" "$SCRIPT_DIR/.env" 2>/dev/null; then
        sed -i '' "s|^JELLYSTAT_JWT_SECRET=$|JELLYSTAT_JWT_SECRET=$JELLYSTAT_JWT_SECRET|" "$SCRIPT_DIR/.env"
    fi
    if ! grep -q "^JELLYSTAT_DB_PASSWORD=" "$SCRIPT_DIR/.env" 2>/dev/null; then
        printf 'JELLYSTAT_DB_PASSWORD=%s\n' "$JELLYSTAT_DB_PASSWORD" >> "$SCRIPT_DIR/.env"
    elif grep -q "^JELLYSTAT_DB_PASSWORD=$" "$SCRIPT_DIR/.env" 2>/dev/null; then
        sed -i '' "s|^JELLYSTAT_DB_PASSWORD=$|JELLYSTAT_DB_PASSWORD=$JELLYSTAT_DB_PASSWORD|" "$SCRIPT_DIR/.env"
    fi
    if ! grep -q "^TDARR_MODE=" "$SCRIPT_DIR/.env" 2>/dev/null; then
        printf 'TDARR_MODE=native\n' >> "$SCRIPT_DIR/.env"
    fi
    if ! grep -q "^TDARR_VERSION=" "$SCRIPT_DIR/.env" 2>/dev/null; then
        printf 'TDARR_VERSION=\n' >> "$SCRIPT_DIR/.env"
    fi
else
    echo "Creating .env file..."
    sed "s|/Users/YOURUSERNAME/Media|$MEDIA_DIR|g" "$SCRIPT_DIR/.env.example" \
        | sed "s|PUID=501|PUID=$USER_PUID|g" \
        | sed "s|PGID=20|PGID=$USER_PGID|g" \
        | sed "s|^JELLYSTAT_JWT_SECRET=$|JELLYSTAT_JWT_SECRET=$JELLYSTAT_JWT_SECRET|g" \
        | sed "s|^JELLYSTAT_DB_PASSWORD=$|JELLYSTAT_DB_PASSWORD=$JELLYSTAT_DB_PASSWORD|g" \
        > "$SCRIPT_DIR/.env"
    chmod 600 "$SCRIPT_DIR/.env"
    echo -e "  ${GREEN}Done${NC}"
fi

# Copy config templates if not already present
if [[ ! -f "$MEDIA_DIR/config/recyclarr/recyclarr.yml" ]]; then
    cp "$SCRIPT_DIR/configs/recyclarr.yml" "$MEDIA_DIR/config/recyclarr/recyclarr.yml"
    echo "  Copied recyclarr.yml template (edit API keys after first boot)"
fi

if [[ ! -f "$MEDIA_DIR/config/kometa/config.yml" ]]; then
    cp "$SCRIPT_DIR/configs/kometa.yml" "$MEDIA_DIR/config/kometa/config.yml"
    echo "  Copied kometa.yml template (edit Plex token + TMDB key after first boot)"
fi

if [[ ! -f "$MEDIA_DIR/config/archive-exceptions.txt" ]]; then
    cp "$SCRIPT_DIR/configs/archive-exceptions.txt.example" "$MEDIA_DIR/config/archive-exceptions.txt"
    echo "  Copied archive-exceptions template (optional: list titles to never archive)"
fi

echo ""
echo "=============================="
echo "  Setup complete!"
echo "=============================="
echo ""
echo "Next steps:"
echo "  1. Edit .env and add your VPN keys"
echo "  2. Run: docker compose up -d"
echo "     (add --profile jellyfin if MEDIA_SERVER=jellyfin)"
echo "     (add --profile tdarr-docker if TDARR_MODE=docker)"
echo "  3. Run: bash scripts/configure.sh"
echo "  4. Edit config templates with your API keys (see SETUP.md)"
echo ""
echo "Optional - Music (Lidarr + Tidarr):"
echo "  Run: bash scripts/setup-music.sh"
echo "  Then: docker compose --profile music up -d"
echo ""
