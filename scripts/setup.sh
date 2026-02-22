#!/bin/bash
# Media Stack Setup Helper (Advanced)
# Creates all required folders and prepares config files.
# Usage: bash scripts/setup.sh [--help]

set -e

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"

usage() {
    cat <<EOF
Usage: bash scripts/setup.sh

Creates Media folder structure, generates .env, and copies config templates.

Options:
  --help    Show this help message
EOF
}

case "${1:-}" in
    "" ) ;;
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

echo ""
echo "=============================="
echo "  Media Stack Setup (Advanced)"
echo "=============================="
echo ""

CURRENT_USER=$(whoami)
HOME_DIR=$(eval echo ~$CURRENT_USER)
MEDIA_DIR="$HOME_DIR/Media"
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
echo -e "  ${GREEN}Done${NC}"
echo ""

# Create .env from example
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    echo -e "${YELLOW}Note:${NC} .env already exists. Skipping creation."
else
    echo "Creating .env file..."
    sed "s|/Users/YOURUSERNAME/Media|$MEDIA_DIR|g" "$SCRIPT_DIR/.env.example" \
        | sed "s|PUID=501|PUID=$USER_PUID|g" \
        | sed "s|PGID=20|PGID=$USER_PGID|g" \
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
echo "  3. Run: bash scripts/configure.sh"
echo "  4. Edit config templates with your API keys (see SETUP.md)"
echo ""
echo "Optional - Music (Lidarr + Tidarr):"
echo "  Run: bash scripts/setup-music.sh"
echo "  Then: docker compose --profile music up -d"
echo ""
