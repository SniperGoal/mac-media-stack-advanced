#!/bin/bash
# Mac Media Stack (Advanced) - One-Shot Installer
# Usage: curl -fsSL https://raw.githubusercontent.com/liamvibecodes/mac-media-stack-advanced/main/bootstrap.sh | bash

set -euo pipefail

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

BOOTSTRAP_DIR="$(cd "$(dirname "$0")" && pwd)"
MEDIA_DIR="$HOME/Media"
INSTALL_DIR="$HOME/mac-media-stack-advanced"
NON_INTERACTIVE=false
MEDIA_SERVER=plex
TDARR_MODE=native
CLOUD_STORAGE=false
NAS_STORAGE=false
FORCE_CONFIGURE=false

usage() {
    cat <<EOF
Usage: bash bootstrap.sh [OPTIONS]

Options:
  --media-dir DIR       Media root path (default: ~/Media)
  --install-dir DIR     Repo install directory (default: ~/mac-media-stack-advanced)
  --jellyfin            Use Jellyfin instead of Plex as the media server
  --tdarr-mode MODE     Tdarr mode: native (default) or docker
  --tdarr-docker        Shortcut for --tdarr-mode docker
  --cloud-storage       Enable cloud storage (rclone + mergerfs)
  --nas-storage         Enable NAS storage via SFTP (rclone + mergerfs)
  --force-configure     Re-run configure.sh even if configure.done exists
  --non-interactive     Skip interactive prompts (manual Seerr wiring required)
  --help                Show this help message

Examples:
  bash bootstrap.sh
  bash bootstrap.sh --media-dir /Volumes/T9/Media
  bash bootstrap.sh --tdarr-docker
  bash bootstrap.sh --jellyfin --cloud-storage --tdarr-docker
  bash bootstrap.sh --jellyfin --nas-storage --tdarr-docker
  bash bootstrap.sh --force-configure
  bash bootstrap.sh --media-dir /Volumes/T9/Media --non-interactive
EOF
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        --media-dir)
            if [[ $# -lt 2 || "$2" == --* ]]; then
                echo "Missing value for --media-dir"
                exit 1
            fi
            MEDIA_DIR="$2"
            shift 2
            ;;
        --install-dir)
            if [[ $# -lt 2 || "$2" == --* ]]; then
                echo "Missing value for --install-dir"
                exit 1
            fi
            INSTALL_DIR="$2"
            shift 2
            ;;
        --jellyfin)
            MEDIA_SERVER=jellyfin
            shift
            ;;
        --tdarr-mode)
            if [[ $# -lt 2 || "$2" == --* ]]; then
                echo "Missing value for --tdarr-mode"
                exit 1
            fi
            TDARR_MODE="$2"
            shift 2
            ;;
        --tdarr-docker)
            TDARR_MODE="docker"
            shift
            ;;
        --cloud-storage)
            CLOUD_STORAGE=true
            shift
            ;;
        --nas-storage)
            NAS_STORAGE=true
            CLOUD_STORAGE=true
            shift
            ;;
        --force-configure)
            FORCE_CONFIGURE=true
            shift
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

MEDIA_DIR="${MEDIA_DIR/#\~/$HOME}"
INSTALL_DIR="${INSTALL_DIR/#\~/$HOME}"

if [[ "$TDARR_MODE" != "native" && "$TDARR_MODE" != "docker" ]]; then
    echo -e "${RED}Invalid TDARR mode:${NC} $TDARR_MODE"
    echo "Use --tdarr-mode native or --tdarr-mode docker"
    exit 1
fi

echo ""
echo "======================================="
echo "  Mac Media Stack Installer (Advanced)"
echo "======================================="
echo ""

# Detect container runtime
if [[ -f "$BOOTSTRAP_DIR/scripts/lib/runtime.sh" ]]; then
    # shellcheck source=scripts/lib/runtime.sh
    source "$BOOTSTRAP_DIR/scripts/lib/runtime.sh"
else
    detect_installed_runtime() {
        local has_orbstack=0
        local has_docker_desktop=0

        if [[ -d "/Applications/OrbStack.app" ]] || command -v orbstack &>/dev/null; then
            has_orbstack=1
        fi
        if [[ -d "/Applications/Docker.app" ]]; then
            has_docker_desktop=1
        fi

        if [[ $has_orbstack -eq 1 && $has_docker_desktop -eq 1 ]]; then
            echo "OrbStack or Docker Desktop"
        elif [[ $has_orbstack -eq 1 ]]; then
            echo "OrbStack"
        elif [[ $has_docker_desktop -eq 1 ]]; then
            echo "Docker Desktop"
        else
            echo "none"
        fi
    }

    detect_running_runtime() {
        local os_name
        os_name=$(docker info --format '{{.OperatingSystem}}' 2>/dev/null || true)
        if [[ "$os_name" == *"OrbStack"* ]]; then
            echo "OrbStack"
        elif [[ "$os_name" == *"Docker Desktop"* ]]; then
            echo "Docker Desktop"
        else
            echo "Docker"
        fi
    }

    wait_for_service() {
        local name="$1"
        local url="$2"
        local max_attempts="${3:-45}"
        local attempt=0
        local status

        while [[ $attempt -lt $max_attempts ]]; do
            status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 3 "$url" 2>/dev/null || true)
            if [[ "$status" =~ ^(200|301|302|401|403)$ ]]; then
                echo -e "  ${GREEN}OK${NC}  $name is reachable"
                return 0
            fi
            sleep 2
            attempt=$((attempt + 1))
        done

        echo -e "  ${YELLOW}WARN${NC}  $name is not reachable yet (continuing anyway)"
        return 1
    }
fi

resolve_compose_container() {
    local service="$1"
    local container_name

    if docker inspect "$service" >/dev/null 2>&1; then
        echo "$service"
        return 0
    fi

    container_name=$(docker ps -a --filter "label=com.docker.compose.service=$service" --format '{{.Names}}' | head -1)
    if [[ -n "$container_name" ]]; then
        echo "$container_name"
        return 0
    fi

    return 1
}

wait_for_healthy_container() {
    local service="$1"
    local max_attempts="${2:-30}"
    local attempt=0
    local container_name
    local health

    while [[ $attempt -lt $max_attempts ]]; do
        container_name="$(resolve_compose_container "$service" || true)"
        if [[ -n "$container_name" ]]; then
            health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unknown{{end}}' "$container_name" 2>/dev/null || true)
            if [[ "$health" == "healthy" ]]; then
                echo -e "  ${GREEN}OK${NC}  $service is healthy"
                return 0
            fi
        fi
        sleep 2
        attempt=$((attempt + 1))
    done

    echo -e "  ${YELLOW}WARN${NC}  $service is not healthy yet (continuing anyway)"
    return 1
}

wait_for_services_batch() {
    local timeout_seconds="${1:-90}"
    shift
    local names=()
    local urls=()
    local ready=()
    local total ready_count start now elapsed i status

    while [[ $# -gt 1 ]]; do
        names+=("$1")
        urls+=("$2")
        shift 2
    done

    total="${#names[@]}"
    ready_count=0
    for ((i = 0; i < total; i++)); do
        ready[$i]=0
    done

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
                echo -e "  ${GREEN}OK${NC}  ${names[$i]} is reachable"
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
            echo -e "  ${YELLOW}WARN${NC}  Timed out waiting after ${timeout_seconds}s: ${pending[*]}"
            return 1
        fi
        sleep 2
    done
}

INSTALLED_RUNTIME=$(detect_installed_runtime)

if ! docker info &>/dev/null; then
    if [[ "$INSTALLED_RUNTIME" == "none" ]]; then
        echo -e "${RED}No container runtime found.${NC}"
        echo ""
        echo "Install one of these:"
        echo "  OrbStack (recommended):  brew install --cask orbstack"
        echo "  Docker Desktop:          https://www.docker.com/products/docker-desktop/"
    else
        echo -e "${RED}No container runtime is running.${NC}"
        echo "Start $INSTALLED_RUNTIME, wait for it to start, then run this again."
    fi
    exit 1
fi
RUNTIME=$(detect_running_runtime)
echo -e "${GREEN}OK${NC}  $RUNTIME is running"

# Check media server
if [[ "$MEDIA_SERVER" == "jellyfin" ]]; then
    echo -e "${GREEN}OK${NC}  Media server: Jellyfin (will run in Docker)"
else
    if [[ -d "/Applications/Plex Media Server.app" ]] || pgrep -x "Plex Media Server" &>/dev/null; then
        echo -e "${GREEN}OK${NC}  Plex detected"
    else
        echo -e "${YELLOW}WARN${NC}  Plex not detected. Install from https://www.plex.tv/media-server-downloads/"
        echo "  You can continue and install Plex later."
    fi
fi
echo -e "${GREEN}OK${NC}  Tdarr mode: $TDARR_MODE"

# Check git
if ! command -v git &>/dev/null; then
    echo -e "${YELLOW}..${NC}  git not found, installing Command Line Tools..."
    xcode-select --install 2>/dev/null || true
    echo "  Click Install when prompted, then run this again."
    exit 1
fi

echo ""
echo "Install dir: $INSTALL_DIR"
echo "Media dir:   $MEDIA_DIR"
echo ""

# Clone
if [[ -d "$INSTALL_DIR" ]]; then
    echo -e "${YELLOW}Note:${NC} $INSTALL_DIR already exists. Pulling latest..."
    if ! git -C "$INSTALL_DIR" pull --ff-only; then
        echo -e "${RED}Failed to update existing repo at $INSTALL_DIR.${NC}"
        echo "Resolve local git issues, then re-run bootstrap."
        echo "Suggested check: cd $INSTALL_DIR && git status"
        exit 1
    fi
else
    echo -e "${CYAN}Cloning repo...${NC}"
    git clone https://github.com/liamvibecodes/mac-media-stack-advanced.git "$INSTALL_DIR"
fi
cd "$INSTALL_DIR"

echo ""

# Setup
echo -e "${CYAN}Running setup...${NC}"
bash scripts/setup.sh --media-dir "$MEDIA_DIR"

# Write media server choice to .env
if [[ -f .env ]]; then
    if grep -q '^MEDIA_SERVER=' .env; then
        sed -i '' "s|^MEDIA_SERVER=.*|MEDIA_SERVER=$MEDIA_SERVER|" .env
    else
        sed -i '' "1s|^|MEDIA_SERVER=$MEDIA_SERVER\n|" .env
    fi
    if grep -q '^TDARR_MODE=' .env; then
        sed -i '' "s|^TDARR_MODE=.*|TDARR_MODE=$TDARR_MODE|" .env
    else
        printf '\nTDARR_MODE=%s\n' "$TDARR_MODE" >> .env
    fi
fi

# Create Jellyfin config directory if needed
if [[ "$MEDIA_SERVER" == "jellyfin" ]]; then
    mkdir -p "$MEDIA_DIR/config/jellyfin"
fi

echo ""

# VPN keys
if grep -q "your_wireguard_private_key_here" .env 2>/dev/null; then
    if [[ "$NON_INTERACTIVE" == true ]]; then
        echo -e "${YELLOW}WARN${NC}  Non-interactive mode: VPN placeholders still present in .env"
        echo "  Update WIREGUARD_PRIVATE_KEY and WIREGUARD_ADDRESSES before using the stack."
    else
        echo -e "${CYAN}VPN Configuration${NC}"
        echo ""

        # Loop until we get a non-empty private key
        vpn_key=""
        while [[ -z "$vpn_key" ]]; do
            read -s -p "  WireGuard Private Key: " vpn_key
            echo ""
            if [[ -z "$vpn_key" ]]; then
                echo -e "  ${RED}Private key cannot be empty. Please enter a valid key.${NC}"
            fi
        done

        read -p "  WireGuard Address (e.g. 10.2.0.2/32): " vpn_addr

        if [[ -n "$vpn_key" && -n "$vpn_addr" ]]; then
            sed -i '' "s|WIREGUARD_PRIVATE_KEY=.*|WIREGUARD_PRIVATE_KEY=$vpn_key|" .env
            sed -i '' "s|WIREGUARD_ADDRESSES=.*|WIREGUARD_ADDRESSES=$vpn_addr|" .env
            echo -e "  ${GREEN}VPN keys saved${NC}"
        else
            echo -e "  ${YELLOW}Skipped.${NC} Edit .env manually: open -a TextEdit $INSTALL_DIR/.env"
        fi
    fi
fi

# Cloud storage setup
if [[ "$CLOUD_STORAGE" == true ]]; then
    echo ""
    echo -e "${CYAN}Setting up cloud storage...${NC}"
    SETUP_ARGS=("--media-dir" "$MEDIA_DIR")
    if [[ "$NAS_STORAGE" == true ]]; then
        SETUP_ARGS+=("--storage-type" "nas")
    fi
    if [[ "$NON_INTERACTIVE" == true ]]; then
        SETUP_ARGS+=("--non-interactive")
    fi
    bash scripts/setup-cloud-storage.sh "${SETUP_ARGS[@]}"
fi

echo ""

# Preflight
echo -e "${CYAN}Running preflight checks...${NC}"
if ! bash scripts/doctor.sh --media-dir "$MEDIA_DIR"; then
    echo ""
    echo -e "${RED}Preflight checks failed.${NC} Fix the FAIL items above, then re-run bootstrap."
    exit 1
fi

echo ""

# Start stack
echo -e "${CYAN}Starting media stack (first run downloads ~3-5 GB)...${NC}"
echo ""
COMPOSE_FILES=("-f" "docker-compose.yml")
COMPOSE_PROFILES=()

# Detect cloud storage from .env (may have been set by setup-cloud-storage.sh or flag)
CLOUD_ENABLED_ENV=""
STORAGE_TYPE_ENV=""
if [[ -f .env ]]; then
    CLOUD_ENABLED_ENV=$(sed -n 's/^CLOUD_STORAGE_ENABLED=//p' .env | head -1)
    STORAGE_TYPE_ENV=$(sed -n 's/^STORAGE_TYPE=//p' .env | head -1)
fi
CLOUD_ACTIVE=false
if [[ "$CLOUD_STORAGE" == true || "$CLOUD_ENABLED_ENV" == "true" ]]; then
    CLOUD_ACTIVE=true
fi
STORAGE_TYPE_EFFECTIVE="$STORAGE_TYPE_ENV"
if [[ "$NAS_STORAGE" == true ]]; then
    STORAGE_TYPE_EFFECTIVE="nas"
elif [[ -z "$STORAGE_TYPE_EFFECTIVE" && "$CLOUD_ACTIVE" == true ]]; then
    STORAGE_TYPE_EFFECTIVE="cloud"
fi

if [[ "$CLOUD_ACTIVE" == true && "$MEDIA_SERVER" == "plex" ]]; then
    echo -e "${RED}Cloud storage requires Jellyfin in this stack.${NC}"
    echo ""
    echo "Reason:"
    echo "  Plex runs natively on macOS, but rclone/mergerfs mounts exist inside the Docker VM."
    echo "  Native Plex cannot read those merged cloud mount paths on macOS."
    echo ""
    echo "Use one of these options:"
    if [[ "$STORAGE_TYPE_EFFECTIVE" == "nas" ]]; then
        echo "  1. Re-run with Jellyfin: bash bootstrap.sh --jellyfin --nas-storage"
    else
        echo "  1. Re-run with Jellyfin: bash bootstrap.sh --jellyfin --cloud-storage"
    fi
    echo "  2. Disable cloud storage and keep Plex: set CLOUD_STORAGE_ENABLED=false in .env"
    exit 1
fi

if [[ "$CLOUD_ACTIVE" == true && "$TDARR_MODE" == "native" ]]; then
    echo -e "${YELLOW}WARN${NC}  Cloud storage + native Tdarr is not supported on macOS."
    echo "  Switching TDARR_MODE to docker so Tdarr can read merged cloud paths."
    TDARR_MODE="docker"
    if [[ -f .env ]]; then
        if grep -q '^TDARR_MODE=' .env; then
            sed -i '' "s|^TDARR_MODE=.*|TDARR_MODE=docker|" .env
        else
            printf '\nTDARR_MODE=docker\n' >> .env
        fi
    fi
fi

if [[ "$CLOUD_ACTIVE" == true ]]; then
    COMPOSE_FILES+=("-f" "docker-compose.cloud-storage.yml")
    COMPOSE_PROFILES+=(--profile cloud-storage)
fi

if [[ "$MEDIA_SERVER" == "jellyfin" ]]; then
    COMPOSE_PROFILES+=(--profile jellyfin)
fi
if [[ "$TDARR_MODE" == "docker" ]]; then
    COMPOSE_PROFILES+=(--profile tdarr-docker)
fi

if ! docker compose "${COMPOSE_FILES[@]}" "${COMPOSE_PROFILES[@]}" up -d; then
    echo ""
    echo -e "${RED}Failed to start the stack.${NC} Check the error output above."
    echo "Common issues:"
    echo "  - Missing or invalid VPN credentials in .env"
    echo "  - Conflicting port bindings (close other apps using ports 8080, 9696, etc.)"
    echo "  - Insufficient disk space"
    exit 1
fi

echo ""
echo "Waiting for core services..."
core_service_checks=(
    "qBittorrent" "http://localhost:8080"
    "Prowlarr" "http://localhost:9696"
    "Radarr" "http://localhost:7878"
    "Sonarr" "http://localhost:8989"
    "Seerr" "http://localhost:5055"
)
if [[ "$MEDIA_SERVER" == "jellyfin" ]]; then
    core_service_checks+=("Jellyfin" "http://localhost:8096/health")
fi
if [[ "$TDARR_MODE" == "docker" ]]; then
    core_service_checks+=("Tdarr" "http://localhost:8265")
fi
wait_for_services_batch 90 "${core_service_checks[@]}" || true

if [[ "$CLOUD_ACTIVE" == true ]]; then
    echo ""
    echo "Waiting for cloud storage..."
    wait_for_healthy_container "rclone-mount" || true
    wait_for_healthy_container "mergerfs" || true
fi

if [[ "$TDARR_MODE" == "native" ]]; then
    echo ""
    echo -e "${CYAN}Setting up native Tdarr...${NC}"
    if ! bash scripts/setup-tdarr-native.sh --media-dir "$MEDIA_DIR"; then
        echo -e "${RED}Native Tdarr setup failed.${NC}"
        echo "Run this after fixing the issue:"
        echo "  bash scripts/setup-tdarr-native.sh --media-dir $MEDIA_DIR"
        exit 1
    fi
fi

# Configure
echo ""
CONFIG_ARGS=(--skip-wait)
if [[ "$NON_INTERACTIVE" == true ]]; then
    CONFIG_ARGS+=(--non-interactive)
fi
if [[ "$FORCE_CONFIGURE" == true ]]; then
    CONFIG_ARGS+=(--force)
fi
bash scripts/configure.sh "${CONFIG_ARGS[@]}"

# Install automation
echo ""
echo -e "${CYAN}Installing automation jobs...${NC}"
bash scripts/install-launchd-jobs.sh

echo ""
echo "======================================="
echo -e "  ${GREEN}Installation complete!${NC}"
echo "======================================="
echo ""
echo "  Seerr:  http://localhost:5055"
if [[ "$MEDIA_SERVER" == "jellyfin" ]]; then
    echo "  Jellyfin: http://localhost:8096"
else
    echo "  Plex:   http://localhost:32400/web"
fi
echo "  Tdarr:  http://localhost:8265"
echo ""
echo "  Media location: $MEDIA_DIR"
echo ""

if [[ "$TDARR_MODE" == "docker" ]]; then
    TDARR_MOVIES_PATH="/movies"
    TDARR_TV_PATH="/tv"
else
    TDARR_MOVIES_PATH="$MEDIA_DIR/Movies"
    TDARR_TV_PATH="$MEDIA_DIR/TV Shows"
fi

PLEX_MOVIES_PATH="$MEDIA_DIR/Movies"
PLEX_TV_PATH="$MEDIA_DIR/TV Shows"

echo "  Remaining manual steps:"
if [[ "$MEDIA_SERVER" == "jellyfin" ]]; then
    echo "    1. Complete Jellyfin setup wizard at http://localhost:8096"
    if [[ "$CLOUD_ACTIVE" == true ]]; then
        echo "       Add libraries: Movies = /data/movies, TV Shows = /data/tvshows (merged remote/local)"
    else
        echo "       Add libraries: Movies = /data/movies, TV Shows = /data/tvshows"
    fi
    echo "    2. In Tdarr, add libraries ($TDARR_MOVIES_PATH and $TDARR_TV_PATH) and assign the preloaded"
    echo "       'Quality-First HEVC (Resolution Preserving)' flow"
else
    echo "    1. Set up Plex libraries (Movies: $PLEX_MOVIES_PATH, TV: $PLEX_TV_PATH)"
    echo "    2. Edit $MEDIA_DIR/config/kometa/config.yml with Plex token + TMDB key"
    echo "    3. In Tdarr, add libraries ($TDARR_MOVIES_PATH and $TDARR_TV_PATH) and assign the preloaded"
    echo "       'Quality-First HEVC (Resolution Preserving)' flow"
fi
echo ""
if [[ "$CLOUD_ACTIVE" == true ]]; then
    if [[ "$STORAGE_TYPE_EFFECTIVE" == "nas" ]]; then
        echo "  NAS storage: enabled (rclone SFTP + mergerfs)"
        echo "  Uploads run every 2 hours via launchd"
    else
        echo "  Cloud storage: enabled (rclone + mergerfs)"
        echo "  Uploads run every 6 hours via launchd"
    fi
    echo ""
fi

echo "  Optional - Music (Lidarr + Tidarr):"
echo "    bash scripts/setup-music.sh"
if [[ "$CLOUD_ACTIVE" == true ]]; then
    echo "    docker compose -f docker-compose.yml -f docker-compose.cloud-storage.yml --profile cloud-storage --profile music up -d"
else
    echo "    docker compose --profile music up -d"
fi
echo "    Then open http://localhost:8484 to authenticate with Tidal"
echo ""
echo "  API keys were printed and Recyclarr/Unpackerr were auto-wired by configure.sh."
echo ""
