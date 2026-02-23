#!/bin/bash
# Cloud Upload - Moves stable local media to cloud storage
# Runs periodically via launchd. Only moves files older than 24h (configurable).

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/media-path.sh
source "$SCRIPT_DIR/lib/media-path.sh"

BASE_DIR="$(resolve_media_dir "$PROJECT_DIR")"

# Source .env
# shellcheck disable=SC1091
source "$PROJECT_DIR/.env" 2>/dev/null || true

# Exit silently if cloud storage not enabled
if [[ "${CLOUD_STORAGE_ENABLED:-}" != "true" ]]; then
    exit 0
fi

if [[ -z "${RCLONE_REMOTE:-}" ]]; then
    echo "ERROR: RCLONE_REMOTE not set in .env"
    exit 1
fi

LOG_DIR="$BASE_DIR/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/cloud-upload.log"

timestamp() { date "+%Y-%m-%d %H:%M:%S"; }
log() { echo "$(timestamp) $1" >> "$LOG"; }

# Trim log
if [[ -f "$LOG" ]] && [[ $(wc -l < "$LOG") -gt 500 ]]; then
    tmp=$(mktemp)
    trap "rm -f '$tmp'" EXIT
    tail -n 250 "$LOG" > "$tmp" && mv "$tmp" "$LOG"
    trap - EXIT
fi

MIN_AGE="${CLOUD_UPLOAD_MIN_AGE_HOURS:-24}h"
RCLONE_CONF="$BASE_DIR/config/rclone/rclone.conf"
RCLONE_IMAGE="${RCLONE_IMAGE:-rclone/rclone@sha256:c08f5e100e1c4fa4deb1315b56a47c0cc0e765222b7c0834bc93305f2e4d85c0}"

if [[ -n "${RCLONE_REMOTE_PATH:-}" ]]; then
    REMOTE_BASE="${RCLONE_REMOTE}:${RCLONE_REMOTE_PATH%/}"
    REMOTE_MOVIES="${REMOTE_BASE}/Movies"
    REMOTE_TV="${REMOTE_BASE}/TV Shows"
else
    REMOTE_MOVIES="${RCLONE_REMOTE}:Movies"
    REMOTE_TV="${RCLONE_REMOTE}:TV Shows"
fi

if [[ ! -f "$RCLONE_CONF" ]]; then
    log "ERROR: rclone.conf not found at $RCLONE_CONF"
    exit 1
fi

log "--- Cloud upload started ---"

# Move Movies
if [[ -d "$BASE_DIR/Movies" ]]; then
    log "Uploading Movies (min-age: $MIN_AGE)..."
    docker run --rm \
        -v "$BASE_DIR/config/rclone:/config/rclone" \
        -v "$BASE_DIR/Movies:/data/Movies" \
        "$RCLONE_IMAGE" move /data/Movies "$REMOTE_MOVIES" \
        --min-age "$MIN_AGE" \
        --delete-empty-src-dirs \
        --transfers 4 \
        --checkers 8 \
        --log-level INFO \
        >> "$LOG" 2>&1
    log "Movies upload complete (exit: $?)"
fi

# Move TV Shows
if [[ -d "$BASE_DIR/TV Shows" ]]; then
    log "Uploading TV Shows (min-age: $MIN_AGE)..."
    docker run --rm \
        -v "$BASE_DIR/config/rclone:/config/rclone" \
        -v "$BASE_DIR/TV Shows:/data/TV Shows" \
        "$RCLONE_IMAGE" move "/data/TV Shows" "$REMOTE_TV" \
        --min-age "$MIN_AGE" \
        --delete-empty-src-dirs \
        --transfers 4 \
        --checkers 8 \
        --log-level INFO \
        >> "$LOG" 2>&1
    log "TV Shows upload complete (exit: $?)"
fi

log "--- Cloud upload finished ---"
