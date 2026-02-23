#!/bin/bash
# Apply the quality-first Tdarr flow preset directly into Tdarr's flow database.
# Usage: bash scripts/tdarr-apply-quality-flow.sh [--media-dir DIR] [--flow-file FILE] [--wait-seconds N]

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/media-path.sh
source "$SCRIPT_DIR/scripts/lib/media-path.sh"

MEDIA_DIR=""
FLOW_FILE="$SCRIPT_DIR/configs/tdarr-flow-quality-first-hevc.json"
WAIT_SECONDS=90

usage() {
    cat <<EOF
Usage: bash scripts/tdarr-apply-quality-flow.sh [OPTIONS]

Options:
  --media-dir DIR       Media root path (default: from .env or ~/Media)
  --flow-file FILE      Flow preset JSON (default: configs/tdarr-flow-quality-first-hevc.json)
  --wait-seconds N      Wait up to N seconds for Tdarr DB (default: 90)
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

while [[ $# -gt 0 ]]; do
    case "$1" in
        --media-dir)
            MEDIA_DIR="$(require_arg --media-dir "${2:-}")"
            shift 2
            ;;
        --flow-file)
            FLOW_FILE="$(require_arg --flow-file "${2:-}")"
            shift 2
            ;;
        --wait-seconds)
            WAIT_SECONDS="$(require_arg --wait-seconds "${2:-}")"
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

if [[ -z "$MEDIA_DIR" ]]; then
    MEDIA_DIR="$(resolve_media_dir "$SCRIPT_DIR")"
fi
MEDIA_DIR="${MEDIA_DIR/#\~/$HOME}"
FLOW_FILE="${FLOW_FILE/#\~/$HOME}"

DB_PATH="$MEDIA_DIR/config/tdarr/server/Tdarr/DB2/SQL/database.db"

if [[ ! -f "$FLOW_FILE" ]]; then
    echo -e "${RED}FAIL${NC} Tdarr flow file not found: $FLOW_FILE"
    exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
    echo -e "${RED}FAIL${NC} jq is required"
    exit 1
fi
if ! command -v python3 >/dev/null 2>&1; then
    echo -e "${RED}FAIL${NC} python3 is required"
    exit 1
fi

flow_id="$(jq -r '._id // empty' "$FLOW_FILE")"
if [[ -z "$flow_id" ]]; then
    echo -e "${RED}FAIL${NC} Flow preset is missing _id: $FLOW_FILE"
    exit 1
fi

attempts=$((WAIT_SECONDS / 3))
if [[ "$attempts" -lt 1 ]]; then
    attempts=1
fi

for _ in $(seq 1 "$attempts"); do
    if [[ -f "$DB_PATH" ]]; then
        break
    fi
    sleep 3
done

if [[ ! -f "$DB_PATH" ]]; then
    echo -e "${YELLOW}WARN${NC} Tdarr DB not ready yet at $DB_PATH (flow preset skipped)"
    exit 0
fi

flow_json="$(jq -c '.' "$FLOW_FILE")"

python3 - "$DB_PATH" "$flow_id" "$flow_json" <<'PY'
import sqlite3
import sys
import time

db_path, flow_id, flow_json = sys.argv[1:4]
timestamp_ms = int(time.time() * 1000)

conn = sqlite3.connect(db_path)
conn.execute(
    """
    INSERT INTO flowsjsondb (id, timestamp, json_data)
    VALUES (?, ?, ?)
    ON CONFLICT(id) DO UPDATE SET
      timestamp = excluded.timestamp,
      json_data = excluded.json_data
    """,
    (flow_id, timestamp_ms, flow_json),
)
conn.commit()
conn.close()
PY

echo -e "${GREEN}OK${NC} Tdarr flow preset applied: $flow_id"
