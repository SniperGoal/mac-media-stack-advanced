#!/bin/bash
# archive-media.sh — Move old/watched media to an external archive drive.
# Dry-run by default. Pass --execute to actually move files.

set -euo pipefail

EXECUTE=0
DAYS=180
MIN_SIZE_GB=8
TYPE="both"
SOURCE_ROOT="$HOME/Media"
ARCHIVE_ROOT=""
LOG_FILE=""
ONLY_WATCHED=0
PLEX_URL="http://localhost:32400"
PLEX_TOKEN=""
PLEX_MOVIES_SECTION="1"
PLEX_TV_SECTION="2"
WATCHED_TMP_DIR=""
EXCEPTIONS_FILE=""
RSYNC_SUPPORTS_PROTECT_ARGS=0

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

EXCLUDED_NAMES=()

cleanup_tmp_dir() {
    if [[ -n "${WATCHED_TMP_DIR:-}" && -d "${WATCHED_TMP_DIR:-}" ]]; then
        rm -rf "$WATCHED_TMP_DIR"
    fi
}

usage() {
    cat <<'EOF'
Usage:
  archive-media.sh [--execute] [--days N] [--min-size-gb N] [--type movies|tv|both]
                   [--source PATH] [--archive PATH] [--log PATH]
                   [--exceptions PATH]
                   [--only-watched] [--plex-url URL] [--plex-token TOKEN]
                   [--plex-movies-section ID] [--plex-tv-section ID]

Moves old or watched media from your active library to an external archive drive.
Dry-run by default — nothing is moved until you pass --execute.

Options:
  --execute               Actually move files (default: dry-run)
  --days N                Minimum age in days (default: 180)
  --min-size-gb N         Minimum folder size in GB (default: 8)
  --type movies|tv|both   Which libraries to process (default: both)
  --source PATH           Source media root (default: ~/Media)
  --archive PATH          Archive destination root (required)
  --log PATH              Log file path (default: <source>/logs/archive-media.log)
  --exceptions PATH       Exceptions file (default: <source>/config/archive-exceptions.txt)
  --only-watched          Only archive content marked as watched in Plex
  --plex-url URL          Plex server URL (default: http://localhost:32400)
  --plex-token TOKEN      Plex auth token (auto-detected from Kometa config if not set)
  --plex-movies-section N Plex movies library section ID (default: 1)
  --plex-tv-section N     Plex TV library section ID (default: 2)
  -h, --help              Show this help

Examples:
  # Preview what would be archived
  archive-media.sh --archive /Volumes/External/Media-Archive

  # Archive movies older than 90 days, 4GB+
  archive-media.sh --execute --archive /Volumes/External/Media-Archive --days 90 --min-size-gb 4 --type movies

  # Only archive watched content
  archive-media.sh --execute --archive /Volumes/External/Media-Archive --only-watched --plex-token YOUR_TOKEN
EOF
}

timestamp() {
    date '+%Y-%m-%d %H:%M:%S'
}

log() {
    local msg="$1"
    local line="$(timestamp) ${msg}"
    echo "$line"
    if [[ -n "$LOG_FILE" ]]; then
        echo "$line" >> "$LOG_FILE"
    fi
}

trim_whitespace() {
    local value="$1"
    value="${value#"${value%%[![:space:]]*}"}"
    value="${value%"${value##*[![:space:]]}"}"
    echo "$value"
}

normalize_name() {
    local value="$1"
    value="$(trim_whitespace "$value")"
    value="$(echo "$value" | tr '[:upper:]' '[:lower:]')"
    value="$(echo "$value" | tr -s ' ')"
    echo "$value"
}

load_excluded_names() {
    EXCLUDED_NAMES=()

    if [[ ! -f "$EXCEPTIONS_FILE" ]]; then
        return
    fi

    while IFS= read -r line || [[ -n "$line" ]]; do
        local trimmed
        trimmed="$(trim_whitespace "$line")"
        if [[ -z "$trimmed" || "$trimmed" == \#* ]]; then
            continue
        fi
        EXCLUDED_NAMES+=("$trimmed")
    done < "$EXCEPTIONS_FILE"
}

is_excluded_name() {
    local dir_name="$1"
    local normalized
    normalized="$(normalize_name "$dir_name")"
    local excluded
    for excluded in "${EXCLUDED_NAMES[@]+"${EXCLUDED_NAMES[@]}"}"; do
        if [[ "$(normalize_name "$excluded")" == "$normalized" ]]; then
            return 0
        fi
    done
    return 1
}

parse_args() {
    require_arg() {
        local flag="$1"
        local value="${2:-}"
        if [[ -z "$value" || "$value" == --* ]]; then
            echo -e "${RED}ERR${NC} Missing value for $flag" >&2
            exit 1
        fi
        echo "$value"
    }

    while [[ $# -gt 0 ]]; do
        case "$1" in
            --execute) EXECUTE=1; shift ;;
            --days) DAYS="$(require_arg --days "${2:-}")"; shift 2 ;;
            --min-size-gb) MIN_SIZE_GB="$(require_arg --min-size-gb "${2:-}")"; shift 2 ;;
            --type) TYPE="$(require_arg --type "${2:-}")"; shift 2 ;;
            --source) SOURCE_ROOT="$(require_arg --source "${2:-}")"; shift 2 ;;
            --archive) ARCHIVE_ROOT="$(require_arg --archive "${2:-}")"; shift 2 ;;
            --log) LOG_FILE="$(require_arg --log "${2:-}")"; shift 2 ;;
            --exceptions) EXCEPTIONS_FILE="$(require_arg --exceptions "${2:-}")"; shift 2 ;;
            --only-watched) ONLY_WATCHED=1; shift ;;
            --plex-url) PLEX_URL="$(require_arg --plex-url "${2:-}")"; shift 2 ;;
            --plex-token) PLEX_TOKEN="$(require_arg --plex-token "${2:-}")"; shift 2 ;;
            --plex-movies-section) PLEX_MOVIES_SECTION="$(require_arg --plex-movies-section "${2:-}")"; shift 2 ;;
            --plex-tv-section) PLEX_TV_SECTION="$(require_arg --plex-tv-section "${2:-}")"; shift 2 ;;
            -h|--help) usage; exit 0 ;;
            *) echo -e "${RED}ERR${NC} Unknown argument: $1" >&2; usage; exit 1 ;;
        esac
    done
}

validate_inputs() {
    case "$TYPE" in
        movies|tv|both) ;;
        *) echo -e "${RED}ERR${NC} --type must be one of: movies|tv|both" >&2; exit 1 ;;
    esac

    if ! [[ "$DAYS" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}ERR${NC} --days must be a non-negative integer" >&2; exit 1
    fi
    if ! [[ "$MIN_SIZE_GB" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}ERR${NC} --min-size-gb must be a non-negative integer" >&2; exit 1
    fi

    if [[ -z "$ARCHIVE_ROOT" ]]; then
        echo -e "${RED}ERR${NC} --archive is required. Specify where to move archived media." >&2
        echo "    Example: --archive /Volumes/External/Media-Archive" >&2
        exit 1
    fi

    if [[ ! -d "$SOURCE_ROOT" ]]; then
        echo -e "${RED}ERR${NC} Source root not found: $SOURCE_ROOT" >&2; exit 1
    fi

    if [[ ! -d "$ARCHIVE_ROOT" ]]; then
        echo -e "${YELLOW}WRN${NC} Archive root doesn't exist, creating: $ARCHIVE_ROOT"
        mkdir -p "$ARCHIVE_ROOT"
    fi

    # Default log file
    if [[ -z "$LOG_FILE" ]]; then
        LOG_FILE="$SOURCE_ROOT/logs/archive-media.log"
    fi
    mkdir -p "$(dirname "$LOG_FILE")"

    # Default exceptions file
    if [[ -z "$EXCEPTIONS_FILE" ]]; then
        EXCEPTIONS_FILE="$SOURCE_ROOT/config/archive-exceptions.txt"
    fi

    if [[ -f "$EXCEPTIONS_FILE" && ! -r "$EXCEPTIONS_FILE" ]]; then
        echo -e "${RED}ERR${NC} Exceptions file is not readable: $EXCEPTIONS_FILE" >&2; exit 1
    fi
}

load_plex_token_default() {
    if [[ -n "$PLEX_TOKEN" ]]; then
        return
    fi

    local kometa_cfg="$SOURCE_ROOT/config/kometa/config.yml"
    if [[ -f "$kometa_cfg" ]]; then
        PLEX_TOKEN="$(sed -n 's/^  token: //p' "$kometa_cfg" | head -n1)"
    fi
}

build_watched_file_movies() {
    local src_root="$1"
    local section_id="$2"
    local out_file="$3"

    python3 - "$PLEX_URL" "$PLEX_TOKEN" "$section_id" "$src_root" <<'PY' > "$out_file"
import os, sys, urllib.parse, urllib.request, xml.etree.ElementTree as ET

base_url, token, section_id, library_root = sys.argv[1:]
library_root = os.path.normpath(library_root)
container_size = 200
start = 0
watched_dirs = set()

while True:
    query = urllib.parse.urlencode({
        "X-Plex-Token": token,
        "X-Plex-Container-Start": str(start),
        "X-Plex-Container-Size": str(container_size),
    })
    url = f"{base_url.rstrip('/')}/library/sections/{section_id}/all?{query}"
    with urllib.request.urlopen(url, timeout=60) as resp:
        payload = resp.read()
    root = ET.fromstring(payload)
    videos = root.findall("Video")
    for video in videos:
        try:
            watched = int(video.attrib.get("viewCount", "0")) > 0
        except ValueError:
            watched = False
        if not watched:
            continue
        for media in video.findall("Media"):
            for part in media.findall("Part"):
                file_path = part.attrib.get("file")
                if not file_path:
                    continue
                normalized = os.path.normpath(file_path)
                prefix = library_root + os.sep
                if normalized.startswith(prefix):
                    watched_dirs.add(os.path.dirname(normalized))
    start += len(videos)
    total = int(root.attrib.get("totalSize", root.attrib.get("size", "0")))
    if len(videos) == 0 or start >= total:
        break

for path in sorted(watched_dirs):
    print(path)
PY
}

build_watched_file_tv() {
    local src_root="$1"
    local section_id="$2"
    local out_file="$3"

    python3 - "$PLEX_URL" "$PLEX_TOKEN" "$section_id" "$src_root" <<'PY' > "$out_file"
import os, sys, urllib.parse, urllib.request, xml.etree.ElementTree as ET

base_url, token, section_id, library_root = sys.argv[1:]
library_root = os.path.normpath(library_root)
container_size = 200
start = 0
total_ep = {}
watched_ep = {}

while True:
    query = urllib.parse.urlencode({
        "X-Plex-Token": token,
        "X-Plex-Container-Start": str(start),
        "X-Plex-Container-Size": str(container_size),
    })
    url = f"{base_url.rstrip('/')}/library/sections/{section_id}/allLeaves?{query}"
    with urllib.request.urlopen(url, timeout=60) as resp:
        payload = resp.read()
    root = ET.fromstring(payload)
    videos = root.findall("Video")
    for video in videos:
        try:
            watched = int(video.attrib.get("viewCount", "0")) > 0
        except ValueError:
            watched = False
        for media in video.findall("Media"):
            for part in media.findall("Part"):
                file_path = part.attrib.get("file")
                if not file_path:
                    continue
                normalized = os.path.normpath(file_path)
                prefix = library_root + os.sep
                if not normalized.startswith(prefix):
                    continue
                rel = normalized[len(prefix):]
                show_name = rel.split(os.sep, 1)[0]
                show_root = os.path.join(library_root, show_name)
                total_ep[show_root] = total_ep.get(show_root, 0) + 1
                if watched:
                    watched_ep[show_root] = watched_ep.get(show_root, 0) + 1
    start += len(videos)
    total = int(root.attrib.get("totalSize", root.attrib.get("size", "0")))
    if len(videos) == 0 or start >= total:
        break

for show_root, total in sorted(total_ep.items()):
    if total > 0 and watched_ep.get(show_root, 0) >= total:
        print(show_root)
PY
}

prepare_watched_files() {
    WATCHED_TMP_DIR="$(mktemp -d)"

    if [[ "$TYPE" == "movies" || "$TYPE" == "both" ]]; then
        build_watched_file_movies "$SOURCE_ROOT/Movies" "$PLEX_MOVIES_SECTION" "$WATCHED_TMP_DIR/movies.txt"
    else
        : > "$WATCHED_TMP_DIR/movies.txt"
    fi
    if [[ "$TYPE" == "tv" || "$TYPE" == "both" ]]; then
        build_watched_file_tv "$SOURCE_ROOT/TV Shows" "$PLEX_TV_SECTION" "$WATCHED_TMP_DIR/tv.txt"
    else
        : > "$WATCHED_TMP_DIR/tv.txt"
    fi
}

get_dir_basename() {
    basename "$1"
}

process_library() {
    local label="$1"
    local src_root="$2"
    local dst_root="$3"
    local cutoff_epoch="$4"
    local min_kb="$5"
    local watched_file="${6:-}"

    if [[ ! -d "$src_root" ]]; then
        log "[WARN] ${label}: source path missing, skipping: $src_root"
        return
    fi

    mkdir -p "$dst_root"

    local total=0
    local candidates=0
    local moved=0
    local skipped=0

    while IFS= read -r src_dir; do
        local name
        name="$(get_dir_basename "$src_dir")"
        if [[ "$name" == .* ]]; then
            continue
        fi

        (( total += 1 )) || true

        if is_excluded_name "$name"; then
            log "[SKIP] ${label}: protected by exceptions list: $name"
            (( skipped += 1 )) || true
            continue
        fi

        local mtime_epoch
        mtime_epoch="$(stat -f %m "$src_dir" 2>/dev/null || stat -c %Y "$src_dir" 2>/dev/null)"
        if (( mtime_epoch > cutoff_epoch )); then
            (( skipped += 1 )) || true
            continue
        fi

        local size_kb
        size_kb="$(du -sk "$src_dir" | awk '{print $1}')"
        if (( size_kb < min_kb )); then
            (( skipped += 1 )) || true
            continue
        fi

        if (( ONLY_WATCHED == 1 )); then
            if [[ -z "$watched_file" || ! -f "$watched_file" ]]; then
                log "[WARN] ${label}: watched filter file missing; skipping $name"
                (( skipped += 1 )) || true
                continue
            fi
            if ! grep -Fxq -- "$src_dir" "$watched_file"; then
                (( skipped += 1 )) || true
                continue
            fi
        fi

        (( candidates += 1 )) || true

        local size_h
        size_h="$(du -sh "$src_dir" | awk '{print $1}')"
        local mtime_h
        mtime_h="$(date -r "$mtime_epoch" '+%Y-%m-%d' 2>/dev/null || date -d "@$mtime_epoch" '+%Y-%m-%d' 2>/dev/null)"
        local dst_dir="$dst_root/$name"

        if (( EXECUTE == 0 )); then
            echo -e "${CYAN}DRY${NC}  $name ($size_h, last modified $mtime_h)"
            log "[DRYRUN] ${label}: $name -> archive ($size_h, mtime=$mtime_h)"
            continue
        fi

        if [[ -e "$dst_dir" ]]; then
            echo -e "${YELLOW}WRN${NC}  Skipping $name (already exists in archive)"
            log "[SKIP] ${label}: destination already exists: $dst_dir"
            (( skipped += 1 )) || true
            continue
        fi

        echo -e "${CYAN}MOV${NC}  $name ($size_h)"
        log "[MOVE] ${label}: copying $name -> $dst_dir"
        if (( RSYNC_SUPPORTS_PROTECT_ARGS == 1 )); then
            rsync -a --protect-args -- "$src_dir/" "$dst_dir/"
        else
            rsync -a -- "$src_dir/" "$dst_dir/"
        fi

        local src_count dst_count
        src_count="$(find "$src_dir" -type f | wc -l | tr -d ' ')"
        dst_count="$(find "$dst_dir" -type f | wc -l | tr -d ' ')"

        if [[ "$src_count" != "$dst_count" ]]; then
            echo -e "${RED}ERR${NC}  Verification failed for $name (src=$src_count files, dst=$dst_count files). Source kept."
            log "[FAIL] ${label}: verification mismatch for $name (src=$src_count dst=$dst_count); source retained"
            continue
        fi

        rm -rf "$src_dir"
        (( moved += 1 )) || true
        echo -e "${GREEN}OK${NC}   Archived $name ($size_h)"
        log "[OK] ${label}: archived $name ($size_h)"
    done < <(find "$src_root" -mindepth 1 -maxdepth 1 -type d | sort)

    echo ""
    log "[SUMMARY] ${label}: total=$total candidates=$candidates moved=$moved skipped=$skipped execute=$EXECUTE"
}

main() {
    parse_args "$@"

    if ! command -v rsync >/dev/null 2>&1; then
        echo -e "${RED}ERR${NC} rsync is required but not found" >&2; exit 1
    fi
    if rsync --help 2>&1 | grep -q -- '--protect-args'; then
        RSYNC_SUPPORTS_PROTECT_ARGS=1
    fi

    validate_inputs
    load_excluded_names

    echo ""
    echo "=============================="
    echo "  Media Archiver"
    echo "=============================="
    echo ""
    echo -e "${CYAN}INF${NC}  Source: $SOURCE_ROOT"
    echo -e "${CYAN}INF${NC}  Archive: $ARCHIVE_ROOT"
    echo -e "${CYAN}INF${NC}  Filter: older than ${DAYS} days, larger than ${MIN_SIZE_GB}GB"
    echo -e "${CYAN}INF${NC}  Type: $TYPE"

    if [[ -f "$EXCEPTIONS_FILE" ]]; then
        echo -e "${CYAN}INF${NC}  Exceptions: ${#EXCLUDED_NAMES[@]} title(s) protected"
    fi

    if (( EXECUTE == 0 )); then
        echo -e "${YELLOW}WRN${NC}  Dry-run mode. No files will be moved. Pass --execute to apply."
    fi
    echo ""

    if (( ONLY_WATCHED == 1 )); then
        if ! command -v python3 >/dev/null 2>&1; then
            echo -e "${RED}ERR${NC} python3 is required for --only-watched" >&2; exit 1
        fi
        load_plex_token_default
        if [[ -z "$PLEX_TOKEN" ]]; then
            echo -e "${RED}ERR${NC} --only-watched requires --plex-token or a token in $SOURCE_ROOT/config/kometa/config.yml" >&2
            exit 1
        fi
        prepare_watched_files
        trap cleanup_tmp_dir EXIT
    fi

    local cutoff_epoch
    cutoff_epoch="$(date -v-"${DAYS}"d +%s 2>/dev/null || date -d "${DAYS} days ago" +%s)"
    local min_kb=$(( MIN_SIZE_GB * 1024 * 1024 ))

    if [[ "$TYPE" == "movies" || "$TYPE" == "both" ]]; then
        echo -e "${CYAN}--- Movies ---${NC}"
        process_library "movies" "$SOURCE_ROOT/Movies" "$ARCHIVE_ROOT/Movies" "$cutoff_epoch" "$min_kb" "${WATCHED_TMP_DIR:-}/movies.txt"
    fi
    if [[ "$TYPE" == "tv" || "$TYPE" == "both" ]]; then
        echo -e "${CYAN}--- TV Shows ---${NC}"
        process_library "tv" "$SOURCE_ROOT/TV Shows" "$ARCHIVE_ROOT/TV Shows" "$cutoff_epoch" "$min_kb" "${WATCHED_TMP_DIR:-}/tv.txt"
    fi

    echo "=============================="
    if (( EXECUTE == 0 )); then
        echo -e "  Dry-run complete. Run with ${CYAN}--execute${NC} to apply."
    else
        echo -e "  ${GREEN}Archive complete.${NC}"
    fi
    echo "=============================="
    echo ""
}

main "$@"
