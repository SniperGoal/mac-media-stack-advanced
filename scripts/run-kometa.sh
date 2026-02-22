#!/bin/bash
# Triggers a Kometa run (one-shot container).
# Called by launchd every 4 hours or manually.
# Plex-only — skipped automatically when MEDIA_SERVER is set to jellyfin.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

# shellcheck disable=SC1091
source "$PROJECT_DIR/.env" 2>/dev/null || true
if [[ "${MEDIA_SERVER:-plex}" != "plex" ]]; then
    echo "Kometa is Plex-only. Skipping."
    exit 0
fi

DOCKER_BIN="$(command -v docker || echo /opt/homebrew/bin/docker)"
COMPOSE_FILE="$PROJECT_DIR/docker-compose.yml"

if ! "$DOCKER_BIN" compose -f "$COMPOSE_FILE" ps -a --services 2>/dev/null | grep -q '^kometa$'; then
    "$DOCKER_BIN" compose -f "$COMPOSE_FILE" up -d --no-deps kometa
else
    "$DOCKER_BIN" start kometa 2>/dev/null || "$DOCKER_BIN" compose -f "$COMPOSE_FILE" up -d --no-deps kometa
fi
