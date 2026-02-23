#!/bin/bash
# Media Stack Auto-Configurator (Advanced)
# Run once after "docker compose up -d". Use --force to re-run explicitly.
# Usage: bash scripts/configure.sh [--non-interactive] [--skip-wait] [--force] [--help]

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
NON_INTERACTIVE=false
SKIP_WAIT=false
FORCE=false

usage() {
    cat <<EOF
Usage: bash scripts/configure.sh [OPTIONS]

Options:
  --non-interactive   Skip interactive Seerr Plex login wiring
  --skip-wait         Assume services are already up (skip readiness checks)
  --force             Re-run even if configure.done marker exists
  --help              Show this help message
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --non-interactive)
            NON_INTERACTIVE=true
            shift
            ;;
        --skip-wait)
            SKIP_WAIT=true
            shift
            ;;
        --force)
            FORCE=true
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

if [[ ! -f "$SCRIPT_DIR/.env" ]]; then
    echo -e "${RED}Error:${NC} .env file not found. Run setup.sh first."
    exit 1
fi
source "$SCRIPT_DIR/.env"

MEDIA_SERVER="${MEDIA_SERVER:-plex}"
TDARR_MODE="${TDARR_MODE:-native}"

QB_PASSWORD="media$(openssl rand -hex 12)"
CREDS_FILE="$MEDIA_DIR/state/first-run-credentials.txt"
CONFIG_DONE_FILE="$MEDIA_DIR/state/configure.done"

log() { echo -e "  ${GREEN}OK${NC}  $1"; }
warn() { echo -e "  ${YELLOW}..${NC}  $1"; }
fail() { echo -e "  ${RED}FAIL${NC}  $1"; }

if [[ -f "$CONFIG_DONE_FILE" && "$FORCE" != true ]]; then
    warn "Configuration already completed ($CONFIG_DONE_FILE)."
    warn "Use --force to re-run configuration."
    exit 0
fi

save_credentials() {
    mkdir -p "$(dirname "$CREDS_FILE")"
    cat > "$CREDS_FILE" <<EOF
# Media Stack (Advanced) first-run credentials
# Generated: $(date '+%Y-%m-%d %H:%M:%S')
qBittorrent Username: admin
qBittorrent Password: $QB_PASSWORD
Radarr API Key: $RADARR_KEY
Sonarr API Key: $SONARR_KEY
Prowlarr API Key: $PROWLARR_KEY
EOF
    chmod 600 "$CREDS_FILE"
}

mark_config_done() {
    mkdir -p "$(dirname "$CONFIG_DONE_FILE")"
    cat > "$CONFIG_DONE_FILE" <<EOF
# Media Stack configure completion marker
timestamp=$(date '+%Y-%m-%d %H:%M:%S')
media_server=$MEDIA_SERVER
tdarr_mode=$TDARR_MODE
EOF
    chmod 600 "$CONFIG_DONE_FILE"
}

set_env_key() {
    local key="$1"
    local value="$2"
    local file="$3"
    local safe_value

    if [[ ! -f "$file" ]]; then
        return 1
    fi

    safe_value="${value//\\/\\\\}"
    safe_value="${safe_value//&/\\&}"

    if grep -q "^${key}=" "$file"; then
        sed -i '' "s|^${key}=.*|${key}=${safe_value}|" "$file"
    else
        printf '\n%s=%s\n' "$key" "$value" >> "$file"
    fi
}

wire_recyclarr_keys() {
    local recyclarr_cfg="$MEDIA_DIR/config/recyclarr/recyclarr.yml"
    local tmp

    if [[ ! -f "$recyclarr_cfg" ]]; then
        warn "Recyclarr config not found at $recyclarr_cfg (skipping key injection)"
        return 0
    fi

    tmp="$(mktemp)"
    awk -v sonarr_key="$SONARR_KEY" -v radarr_key="$RADARR_KEY" '
        /^sonarr:/ {section="sonarr"}
        /^radarr:/ {section="radarr"}
        {
            if (section=="sonarr" && $0 ~ /^[[:space:]]+api_key:[[:space:]]*/) {
                print "    api_key: " sonarr_key
                next
            }
            if (section=="radarr" && $0 ~ /^[[:space:]]+api_key:[[:space:]]*/) {
                print "    api_key: " radarr_key
                next
            }
            print
        }
    ' "$recyclarr_cfg" > "$tmp"
    mv "$tmp" "$recyclarr_cfg"
    log "Recyclarr API keys written to $recyclarr_cfg"
}

wire_unpackerr_keys() {
    local env_file="$SCRIPT_DIR/.env"
    local unpackerr_state

    if ! set_env_key "UN_SONARR_0_API_KEY" "$SONARR_KEY" "$env_file"; then
        warn "Could not update UN_SONARR_0_API_KEY in $env_file"
        return 0
    fi
    if ! set_env_key "UN_RADARR_0_API_KEY" "$RADARR_KEY" "$env_file"; then
        warn "Could not update UN_RADARR_0_API_KEY in $env_file"
        return 0
    fi
    log "Unpackerr API keys updated in .env"

    unpackerr_state=$(docker inspect -f '{{.State.Status}}' unpackerr 2>/dev/null || true)
    if [[ "$unpackerr_state" == "running" || "$unpackerr_state" == "created" || "$unpackerr_state" == "restarting" ]]; then
        if docker compose restart unpackerr >/dev/null 2>&1; then
            log "Unpackerr restarted to apply new API keys"
        else
            warn "Unpackerr restart failed; run 'docker compose restart unpackerr' manually"
        fi
    else
        warn "Unpackerr container not found/running; start stack then run 'docker compose restart unpackerr'"
    fi
}

api_post_json() {
    local label="$1"
    local url="$2"
    local api_key="$3"
    local payload="$4"
    local body_file http_code

    body_file="$(mktemp)"
    http_code=$(curl -sS -o "$body_file" -w "%{http_code}" \
        -H "Content-Type: application/json" \
        -H "X-Api-Key: $api_key" \
        -d "$payload" "$url" || echo "000")

    if [[ "$http_code" =~ ^2 ]]; then
        log "$label"
        rm -f "$body_file"
        return 0
    fi

    if grep -qiE "already exists|must be unique|duplicate" "$body_file"; then
        warn "$label (already configured)"
        rm -f "$body_file"
        return 0
    fi

    fail "$label (HTTP $http_code)"
    sed -n '1,2p' "$body_file" >&2 || true
    rm -f "$body_file"
    return 1
}

api_post_form() {
    local label="$1"
    local url="$2"
    local cookie="$3"
    shift 3

    if curl -fsS -b "$cookie" "$url" "$@" >/dev/null; then
        log "$label"
        return 0
    fi

    fail "$label"
    return 1
}

wait_for_services_batch() {
    local timeout_seconds="${1:-60}"
    shift

    local names=()
    local urls=()
    while [[ $# -gt 1 ]]; do
        names+=("$1")
        urls+=("$2")
        shift 2
    done

    local total="${#names[@]}"
    local ready=()
    local ready_count=0
    local start now elapsed i status
    for ((i = 0; i < total; i++)); do
        ready[$i]=0
    done

    warn "Waiting for services..."
    start=$(date +%s)
    while true; do
        for ((i = 0; i < total; i++)); do
            if [[ "${ready[$i]}" -eq 1 ]]; then
                continue
            fi
            status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "${urls[$i]}" 2>/dev/null || true)
            if [[ "$status" =~ ^(200|301|302|401|403)$ ]]; then
                ready[$i]=1
                ready_count=$((ready_count + 1))
                log "${names[$i]} is ready"
            fi
        done

        if [[ "$ready_count" -eq "$total" ]]; then
            return 0
        fi

        now=$(date +%s)
        elapsed=$((now - start))
        if [[ "$elapsed" -ge "$timeout_seconds" ]]; then
            local pending=()
            for ((i = 0; i < total; i++)); do
                if [[ "${ready[$i]}" -eq 0 ]]; then
                    pending+=("${names[$i]}")
                fi
            done
            fail "Timed out waiting for services after ${timeout_seconds}s: ${pending[*]}"
            return 1
        fi
        sleep 2
    done
}

get_api_keys_batch() {
    local max_attempts=30
    local attempt=0
    local radarr_cfg="$MEDIA_DIR/config/radarr/config.xml"
    local sonarr_cfg="$MEDIA_DIR/config/sonarr/config.xml"
    local prowlarr_cfg="$MEDIA_DIR/config/prowlarr/config.xml"

    RADARR_KEY=""
    SONARR_KEY=""
    PROWLARR_KEY=""

    while [[ $attempt -lt $max_attempts ]]; do
        if [[ -z "$RADARR_KEY" && -f "$radarr_cfg" ]]; then
            RADARR_KEY=$(grep -o '<ApiKey>[^<]*</ApiKey>' "$radarr_cfg" 2>/dev/null | sed 's/<[^>]*>//g' | head -1)
        fi
        if [[ -z "$SONARR_KEY" && -f "$sonarr_cfg" ]]; then
            SONARR_KEY=$(grep -o '<ApiKey>[^<]*</ApiKey>' "$sonarr_cfg" 2>/dev/null | sed 's/<[^>]*>//g' | head -1)
        fi
        if [[ -z "$PROWLARR_KEY" && -f "$prowlarr_cfg" ]]; then
            PROWLARR_KEY=$(grep -o '<ApiKey>[^<]*</ApiKey>' "$prowlarr_cfg" 2>/dev/null | sed 's/<[^>]*>//g' | head -1)
        fi

        if [[ -n "$RADARR_KEY" && -n "$SONARR_KEY" && -n "$PROWLARR_KEY" ]]; then
            return 0
        fi

        sleep 2
        ((attempt++))
    done

    local missing=()
    [[ -z "$RADARR_KEY" ]] && missing+=("radarr")
    [[ -z "$SONARR_KEY" ]] && missing+=("sonarr")
    [[ -z "$PROWLARR_KEY" ]] && missing+=("prowlarr")
    fail "Could not read API keys: ${missing[*]}"
    return 1
}

echo ""
echo "=============================="
echo "  Media Stack Configurator"
echo "=============================="
echo ""

# 1. Wait for services
echo -e "${CYAN}[1/6] Waiting for services...${NC}"
echo ""
if [[ "$SKIP_WAIT" == true ]]; then
    warn "Skipping service readiness checks (--skip-wait)"
else
    wait_for_services_batch 60 \
        "qBittorrent" "http://localhost:8080" \
        "Prowlarr" "http://localhost:9696" \
        "Radarr" "http://localhost:7878" \
        "Sonarr" "http://localhost:8989" \
        "Bazarr" "http://localhost:6767" \
        "FlareSolverr" "http://localhost:8191" \
        "Seerr" "http://localhost:5055"
fi
echo ""

# 2. Extract API keys
echo -e "${CYAN}[2/6] Reading API keys...${NC}"
echo ""
get_api_keys_batch
log "Radarr API key: ${RADARR_KEY:0:8}..."
log "Sonarr API key: ${SONARR_KEY:0:8}..."
log "Prowlarr API key: ${PROWLARR_KEY:0:8}..."
echo ""

echo -e "${CYAN}[*] Wiring advanced configs...${NC}"
wire_recyclarr_keys
wire_unpackerr_keys
echo ""

# 3. Configure qBittorrent
echo -e "${CYAN}[3/6] Configuring qBittorrent...${NC}"
echo ""
QB_TEMP_PASS=$(docker logs qbittorrent 2>&1 | grep -o 'temporary password is provided for this session: [^ ]*' | tail -1 | awk '{print $NF}')
if [[ -z "$QB_TEMP_PASS" ]]; then
    QB_TEMP_PASS=$(docker logs qbittorrent 2>&1 | sed -n 's/.*password: \([^[:space:]]*\).*/\1/p' | tail -1)
fi

qb_saved_pass=""
if [[ -f "$CREDS_FILE" ]]; then
    qb_saved_pass=$(sed -n 's/^qBittorrent Password: //p' "$CREDS_FILE" | head -1)
fi

QB_COOKIE=""
for candidate in "$QB_TEMP_PASS" "$qb_saved_pass" "${QBIT_PASSWORD:-}" "adminadmin"; do
    [[ -z "$candidate" ]] && continue
    QB_COOKIE=$(curl -s -c - "http://localhost:8080/api/v2/auth/login" \
        --data-urlencode "username=admin" \
        --data-urlencode "password=$candidate" 2>/dev/null | awk '/SID/ {print $NF; exit}')
    if [[ -n "$QB_COOKIE" ]]; then
        break
    fi
done

if [[ -z "$QB_COOKIE" ]]; then
    fail "Could not authenticate with qBittorrent. Aborting configuration."
    fail "Check qBittorrent Web UI credentials and re-run configure.sh."
    exit 1
fi

api_post_form "Password set and preferences configured" "http://localhost:8080/api/v2/app/setPreferences" "SID=$QB_COOKIE" \
    --data-urlencode "json={
        \"web_ui_password\": \"$QB_PASSWORD\",
        \"max_ratio\": 0,
        \"max_seeding_time\": 0,
        \"max_ratio_act\": 0,
        \"up_limit\": 1024,
        \"save_path\": \"/downloads/complete\",
        \"temp_path_enabled\": true,
        \"temp_path\": \"/downloads/incomplete\",
        \"preallocate_all\": false
    }"

api_post_form "Download category created: radarr" "http://localhost:8080/api/v2/torrents/createCategory" "SID=$QB_COOKIE" \
    --data-urlencode "category=radarr" --data-urlencode "savePath=/downloads/complete/radarr"
api_post_form "Download category created: tv-sonarr" "http://localhost:8080/api/v2/torrents/createCategory" "SID=$QB_COOKIE" \
    --data-urlencode "category=tv-sonarr" --data-urlencode "savePath=/downloads/complete/tv-sonarr"
save_credentials
echo ""

# 4. Configure Radarr & Sonarr
echo -e "${CYAN}[4/6] Configuring Radarr & Sonarr...${NC}"
echo ""
api_post_json "Radarr root folder set" \
    "http://localhost:7878/api/v3/rootfolder" \
    "$RADARR_KEY" \
    '{"path": "/movies"}'
api_post_json "Radarr download client configured" \
    "http://localhost:7878/api/v3/downloadclient" \
    "$RADARR_KEY" \
    "{\"enable\":true,\"protocol\":\"torrent\",\"name\":\"qBittorrent\",\"implementation\":\"QBittorrent\",\"configContract\":\"QBittorrentSettings\",\"fields\":[{\"name\":\"host\",\"value\":\"gluetun\"},{\"name\":\"port\",\"value\":8080},{\"name\":\"username\",\"value\":\"admin\"},{\"name\":\"password\",\"value\":\"$QB_PASSWORD\"},{\"name\":\"movieCategory\",\"value\":\"radarr\"},{\"name\":\"recentMoviePriority\",\"value\":0},{\"name\":\"olderMoviePriority\",\"value\":0},{\"name\":\"initialState\",\"value\":0},{\"name\":\"sequentialOrder\",\"value\":false},{\"name\":\"firstAndLast\",\"value\":false}],\"removeCompletedDownloads\":true,\"removeFailedDownloads\":true}"
api_post_json "Sonarr root folder set" \
    "http://localhost:8989/api/v3/rootfolder" \
    "$SONARR_KEY" \
    '{"path": "/tv"}'
api_post_json "Sonarr download client configured" \
    "http://localhost:8989/api/v3/downloadclient" \
    "$SONARR_KEY" \
    "{\"enable\":true,\"protocol\":\"torrent\",\"name\":\"qBittorrent\",\"implementation\":\"QBittorrent\",\"configContract\":\"QBittorrentSettings\",\"fields\":[{\"name\":\"host\",\"value\":\"gluetun\"},{\"name\":\"port\",\"value\":8080},{\"name\":\"username\",\"value\":\"admin\"},{\"name\":\"password\",\"value\":\"$QB_PASSWORD\"},{\"name\":\"tvCategory\",\"value\":\"tv-sonarr\"},{\"name\":\"recentTvPriority\",\"value\":0},{\"name\":\"olderTvPriority\",\"value\":0},{\"name\":\"initialState\",\"value\":0},{\"name\":\"sequentialOrder\",\"value\":false},{\"name\":\"firstAndLast\",\"value\":false}],\"removeCompletedDownloads\":true,\"removeFailedDownloads\":true}"
echo ""

# 5. Configure Prowlarr
echo -e "${CYAN}[5/6] Configuring Prowlarr...${NC}"
echo ""
FLARE_TAG_ID=$(curl -fsS "http://localhost:9696/api/v1/tag" -H "X-Api-Key: $PROWLARR_KEY" -H "Content-Type: application/json" -d '{"label":"flaresolverr"}' 2>/dev/null | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
FLARE_TAG_ID="${FLARE_TAG_ID:-1}"
log "FlareSolverr tag created"

api_post_json "FlareSolverr proxy added" \
    "http://localhost:9696/api/v1/indexerProxy" \
    "$PROWLARR_KEY" \
    "{\"name\":\"FlareSolverr\",\"implementation\":\"FlareSolverr\",\"configContract\":\"FlareSolverrSettings\",\"fields\":[{\"name\":\"host\",\"value\":\"http://flaresolverr:8191\"},{\"name\":\"requestTimeout\",\"value\":60}],\"tags\":[$FLARE_TAG_ID]}"

add_indexer() {
    local name="$1" def="$2" url="$3" tags="$4"
    api_post_json "Indexer added: $name" \
        "http://localhost:9696/api/v1/indexer" \
        "$PROWLARR_KEY" \
        "{\"name\":\"$name\",\"definitionName\":\"$def\",\"implementation\":\"Cardigann\",\"configContract\":\"CardigannSettings\",\"protocol\":\"torrent\",\"enable\":true,\"appProfileId\":1,\"fields\":[{\"name\":\"baseUrl\",\"value\":\"$url\"},{\"name\":\"sortRequestLimit\",\"value\":100},{\"name\":\"multiLanguages\",\"value\":[]}],\"tags\":[$tags]}"
}

add_indexer "YTS" "yts" "https://yts.mx" ""
add_indexer "1337x" "1337x" "https://1337x.to" "$FLARE_TAG_ID"
add_indexer "EZTV" "eztv" "https://eztvx.to" ""
add_indexer "TorrentGalaxy" "torrentgalaxy" "https://torrentgalaxy.to" ""

api_post_json "Prowlarr connected to Radarr" \
    "http://localhost:9696/api/v1/applications" \
    "$PROWLARR_KEY" \
    "{\"name\":\"Radarr\",\"implementation\":\"Radarr\",\"configContract\":\"RadarrSettings\",\"syncLevel\":\"fullSync\",\"fields\":[{\"name\":\"prowlarrUrl\",\"value\":\"http://prowlarr:9696\"},{\"name\":\"baseUrl\",\"value\":\"http://radarr:7878\"},{\"name\":\"apiKey\",\"value\":\"$RADARR_KEY\"},{\"name\":\"syncCategories\",\"value\":[2000,2010,2020,2030,2040,2045,2050,2060,2070,2080]}],\"tags\":[]}"
api_post_json "Prowlarr connected to Sonarr" \
    "http://localhost:9696/api/v1/applications" \
    "$PROWLARR_KEY" \
    "{\"name\":\"Sonarr\",\"implementation\":\"Sonarr\",\"configContract\":\"SonarrSettings\",\"syncLevel\":\"fullSync\",\"fields\":[{\"name\":\"prowlarrUrl\",\"value\":\"http://prowlarr:9696\"},{\"name\":\"baseUrl\",\"value\":\"http://sonarr:8989\"},{\"name\":\"apiKey\",\"value\":\"$SONARR_KEY\"},{\"name\":\"syncCategories\",\"value\":[5000,5010,5020,5030,5040,5045,5050,5060,5070,5080]}],\"tags\":[]}"
api_post_json "Indexer sync triggered" \
    "http://localhost:9696/api/v1/command" \
    "$PROWLARR_KEY" \
    '{"name":"SyncIndexers"}'
echo ""

# 6. Seerr
echo -e "${CYAN}[6/6] Configuring Seerr...${NC}"
echo ""
if [[ "$MEDIA_SERVER" == "jellyfin" ]]; then
    if [[ "$NON_INTERACTIVE" == true ]]; then
        warn "Non-interactive mode: skipping Seerr Jellyfin sign-in prompt."
        warn "Manually open http://localhost:5055 and select 'Use your Jellyfin account'."
        warn "Jellyfin URL: http://jellyfin:8096"
    else
        echo -e "  ${YELLOW}ACTION NEEDED:${NC} Open ${CYAN}http://localhost:5055${NC} in your browser"
        echo "  Select \"Use your Jellyfin account\" and enter:"
        echo "    Jellyfin URL: http://jellyfin:8096"
        echo ""
        read -p "  Press Enter after you've signed in to Seerr..."
        echo ""
        sleep 3
    fi
elif [[ "$NON_INTERACTIVE" == true ]]; then
    warn "Non-interactive mode: skipping Seerr Plex sign-in prompt."
    warn "Manually open http://localhost:5055 and sign in with Plex, then configure services in Seerr."
else
    echo -e "  ${YELLOW}ACTION NEEDED:${NC} Open ${CYAN}http://localhost:5055${NC} in your browser"
    echo "  and click \"Sign In With Plex\"."
    echo ""
    read -p "  Press Enter after you've signed in to Seerr..."
    echo ""
    sleep 3
fi

SEERR_KEY=$(curl -fsS "http://localhost:5055/api/v1/settings/main" 2>/dev/null | grep -o '"apiKey":"[^"]*"' | cut -d'"' -f4)
if [[ -z "$SEERR_KEY" ]]; then
    warn "Could not get Seerr API key. Configure Radarr/Sonarr in Seerr manually."
else
    RADARR_PROFILE_ID=$(curl -fsS "http://localhost:7878/api/v3/qualityprofile" -H "X-Api-Key: $RADARR_KEY" 2>/dev/null | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
    RADARR_PROFILE_ID="${RADARR_PROFILE_ID:-1}"
    SONARR_PROFILE_ID=$(curl -fsS "http://localhost:8989/api/v3/qualityprofile" -H "X-Api-Key: $SONARR_KEY" 2>/dev/null | grep -o '"id":[0-9]*' | head -1 | cut -d: -f2)
    SONARR_PROFILE_ID="${SONARR_PROFILE_ID:-1}"

    api_post_json "Seerr connected to Radarr" \
        "http://localhost:5055/api/v1/settings/radarr" \
        "$SEERR_KEY" \
        "[{\"name\":\"Radarr\",\"hostname\":\"radarr\",\"port\":7878,\"apiKey\":\"$RADARR_KEY\",\"useSsl\":false,\"activeProfileId\":$RADARR_PROFILE_ID,\"activeDirectory\":\"/movies\",\"is4k\":false,\"isDefault\":true,\"externalUrl\":\"http://localhost:7878\"}]"
    api_post_json "Seerr connected to Sonarr" \
        "http://localhost:5055/api/v1/settings/sonarr" \
        "$SEERR_KEY" \
        "[{\"name\":\"Sonarr\",\"hostname\":\"sonarr\",\"port\":8989,\"apiKey\":\"$SONARR_KEY\",\"useSsl\":false,\"activeProfileId\":$SONARR_PROFILE_ID,\"activeDirectory\":\"/tv\",\"activeAnimeProfileId\":$SONARR_PROFILE_ID,\"activeAnimeDirectory\":\"/tv\",\"is4k\":false,\"isDefault\":true,\"enableSeasonFolders\":true,\"externalUrl\":\"http://localhost:8989\"}]"
fi

echo ""

# 7. Jellyfin plugins (Intro Skipper + TMDb Box Sets)
if [[ "$MEDIA_SERVER" == "jellyfin" ]]; then
    echo -e "${CYAN}[*] Installing Jellyfin plugins...${NC}"
    echo ""

    # Wait for Jellyfin API
    JF_READY=false
    for i in $(seq 1 30); do
        jf_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "http://localhost:8096/health" 2>/dev/null || true)
        if [[ "$jf_status" == "200" ]]; then
            JF_READY=true
            break
        fi
        sleep 2
    done

    if [[ "$JF_READY" == true ]]; then
        # Extract API key from Jellyfin system.xml
        JF_XML="$MEDIA_DIR/config/jellyfin/config/system.xml"
        JF_API_KEY=""
        if [[ -f "$JF_XML" ]]; then
            JF_API_KEY=$(grep -o '<ApiKey>[^<]*</ApiKey>' "$JF_XML" 2>/dev/null | sed 's/<[^>]*>//g' || true)
        fi

        if [[ -z "$JF_API_KEY" ]]; then
            warn "Could not extract Jellyfin API key from system.xml"
            warn "Generate one in Jellyfin > Administration > API Keys, then install plugins manually:"
            warn "  - Intro Skipper: Administration > Plugins > Catalog > Intro Skipper > Install"
            warn "  - TMDb Box Sets: Administration > Plugins > Catalog > TMDb Box Sets > Install"
        else
            # Fetch plugin catalog
            PLUGIN_CATALOG=$(curl -fsS "http://localhost:8096/Packages" -H "X-Emby-Token: $JF_API_KEY" 2>/dev/null || true)

            url_encode() {
                local raw="$1"
                if command -v python3 >/dev/null 2>&1; then
                    python3 - "$raw" <<'PY'
import sys, urllib.parse
print(urllib.parse.quote(sys.argv[1], safe=""))
PY
                else
                    # Best-effort fallback for environments without python3
                    printf '%s\n' "${raw// /%20}"
                fi
            }

            resolve_jf_plugin() {
                local requested="$1"
                if ! command -v python3 >/dev/null 2>&1; then
                    return 1
                fi

                printf '%s' "$PLUGIN_CATALOG" | python3 - "$requested" <<'PY'
import json, sys

wanted = sys.argv[1].strip().lower()
try:
    payload = json.load(sys.stdin)
except Exception:
    sys.exit(1)

items = payload.get("Items", payload) if isinstance(payload, dict) else payload
if not isinstance(items, list):
    sys.exit(1)

for item in items:
    if not isinstance(item, dict):
        continue
    name = str(item.get("name", item.get("Name", ""))).strip()
    guid = str(item.get("guid", item.get("Guid", ""))).strip()
    if name.lower() == wanted:
        print(name)
        print(guid)
        sys.exit(0)

sys.exit(1)
PY
            }

            install_jf_plugin() {
                local plugin_name="$1"
                if [[ -z "$PLUGIN_CATALOG" ]]; then
                    warn "$plugin_name: could not fetch plugin catalog"
                    return 0
                fi

                local plugin_info plugin_guid resolved_name
                plugin_info="$(resolve_jf_plugin "$plugin_name" || true)"
                resolved_name="$(echo "$plugin_info" | sed -n '1p')"
                plugin_guid="$(echo "$plugin_info" | sed -n '2p')"

                if [[ -z "$resolved_name" ]]; then
                    warn "$plugin_name: not found in plugin catalog"
                    warn "  Install manually: Administration > Plugins > Catalog > $plugin_name"
                    return 0
                fi

                local install_result encoded_name install_url
                encoded_name="$(url_encode "$resolved_name")"
                install_url="http://localhost:8096/Packages/Installed/$encoded_name"
                if [[ -n "$plugin_guid" ]]; then
                    install_url="${install_url}?assemblyGuid=$plugin_guid"
                fi

                install_result=$(curl -s -o /dev/null -w "%{http_code}" -X POST \
                    "$install_url" \
                    -H "X-Emby-Token: $JF_API_KEY" 2>/dev/null || echo "000")

                if [[ "$install_result" =~ ^2 ]]; then
                    log "$resolved_name plugin installed"
                else
                    warn "$resolved_name: install returned HTTP $install_result"
                    warn "  Install manually: Administration > Plugins > Catalog > $plugin_name"
                fi
            }

            install_jf_plugin "Intro Skipper"
            install_jf_plugin "TMDb Box Sets"

            echo ""
            if [[ "$NON_INTERACTIVE" == true ]]; then
                warn "Restart Jellyfin to activate plugins: docker compose restart jellyfin"
            else
                echo -e "  ${YELLOW}Plugins require a Jellyfin restart to activate.${NC}"
                read -p "  Restart Jellyfin now? [Y/n] " -r restart_jf
                if [[ "$restart_jf" =~ ^[Nn]$ ]]; then
                    warn "Skipped. Run 'docker compose restart jellyfin' when ready."
                else
                    if docker compose restart jellyfin >/dev/null 2>&1; then
                        log "Jellyfin restarted"
                    else
                        warn "Restart failed. Run 'docker compose restart jellyfin' manually."
                    fi
                fi
            fi
        fi
    else
        warn "Jellyfin not ready after 60 seconds. Skipping plugin install."
        warn "Install manually after Jellyfin is running:"
        warn "  - Intro Skipper: Administration > Plugins > Catalog > Intro Skipper > Install"
        warn "  - TMDb Box Sets: Administration > Plugins > Catalog > TMDb Box Sets > Install"
    fi
    echo ""
fi

mark_config_done

# Print API keys for user to update config templates
echo "=============================="
echo -e "  ${GREEN}Configuration complete!${NC}"
echo "=============================="
echo ""
echo "Your services are ready. Credentials:"
echo ""
echo "  qBittorrent: admin / $QB_PASSWORD"
echo "  Radarr API Key:   $RADARR_KEY"
echo "  Sonarr API Key:   $SONARR_KEY"
echo "  Prowlarr API Key: $PROWLARR_KEY"
echo "  Saved credentials: $CREDS_FILE"
echo "  Configure marker:  $CONFIG_DONE_FILE"
echo ""
echo -e "  ${YELLOW}Auto-wired:${NC} Recyclarr + Unpackerr API keys"
if [[ "$MEDIA_SERVER" == "plex" ]]; then
    echo "  Remaining manual keys:"
    echo "    - $MEDIA_DIR/config/kometa/config.yml (PLEX_TOKEN, TMDB API key)"
fi
echo ""
echo "  Seerr:       http://localhost:5055"
if [[ "$MEDIA_SERVER" == "jellyfin" ]]; then
    echo "  Jellyfin:    http://localhost:8096"
else
    echo "  Plex:        http://localhost:32400/web"
fi
echo "  Tdarr:       http://localhost:8265"
if [[ "$TDARR_MODE" == "native" ]]; then
    echo "  Tdarr mode:  native (launchd)"
else
    echo "  Tdarr mode:  docker (tdarr-docker profile)"
fi
echo "  Tdarr flow:  Quality-First HEVC (Resolution Preserving)"
echo ""
