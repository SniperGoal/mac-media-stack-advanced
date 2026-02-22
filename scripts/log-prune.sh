#!/bin/bash
# Prunes old log files from the media stack.
# Default: removes .log, .txt, and .gz files older than 30 days.
# Runs as a daily launchd job or manually.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/media-path.sh
source "$SCRIPT_DIR/scripts/lib/media-path.sh"
MEDIA_DIR="$(resolve_media_dir "$SCRIPT_DIR")"
RETENTION_DAYS="${LOG_PRUNE_RETENTION_DAYS:-30}"

usage() {
    echo "Usage: $(basename "$0") [--path /path/to/Media] [--days N]"
    echo ""
    echo "Options:"
    echo "  --path    Media directory (default: ~/Media)"
    echo "  --days    Retention in days (default: 30)"
    exit 0
}

require_arg() {
    local flag="$1"
    local value="${2:-}"
    if [[ -z "$value" || "$value" == --* ]]; then
        echo "Missing value for $flag" >&2
        exit 1
    fi
    echo "$value"
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --path) MEDIA_DIR="$(require_arg --path "${2:-}")"; shift 2 ;;
        --days) RETENTION_DAYS="$(require_arg --days "${2:-}")"; shift 2 ;;
        -h|--help) usage ;;
        *) echo "Unknown option: $1"; exit 1 ;;
    esac
done

LOG_DIR="${MEDIA_DIR}/logs"
CONFIG_DIR="${MEDIA_DIR}/config"
LOG_FILE="${LOG_DIR}/log-prune.log"

stamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

log() {
    mkdir -p "$LOG_DIR"
    echo "$(stamp) $*" >> "$LOG_FILE"
}

if ! [[ "$RETENTION_DAYS" =~ ^[0-9]+$ ]]; then
    log "[ERROR] invalid retention days: $RETENTION_DAYS"
    exit 1
fi

prune_tree() {
    local root="$1"
    local label="$2"
    local deleted=0

    if [[ ! -d "$root" ]]; then
        log "[INFO] skip $label (missing: $root)"
        return
    fi

    while IFS= read -r -d '' file; do
        rm -f "$file"
        deleted=$((deleted + 1))
    done < <(find "$root" -type f \( -name '*.log' -o -name '*.txt' -o -name '*.gz' \) -mtime +"$RETENTION_DAYS" -print0 2>/dev/null)

    # Remove empty nested directories
    find "$root" -type d -empty -delete 2>/dev/null || true
    log "[OK] pruned $deleted files from $label older than $RETENTION_DAYS days"
}

log "[INFO] starting log prune retention_days=$RETENTION_DAYS"
prune_tree "$LOG_DIR" "media-logs"
prune_tree "$CONFIG_DIR" "config-logs"
log "[INFO] log prune complete"

echo "Log prune complete. Removed files older than $RETENTION_DAYS days."
echo "Details: $LOG_FILE"
