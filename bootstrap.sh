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

usage() {
    cat <<EOF
Usage: bash bootstrap.sh [OPTIONS]

Options:
  --media-dir DIR       Media root path (default: ~/Media)
  --install-dir DIR     Repo install directory (default: ~/mac-media-stack-advanced)
  --non-interactive     Skip interactive prompts (manual Seerr wiring required)
  --help                Show this help message

Examples:
  bash bootstrap.sh
  bash bootstrap.sh --media-dir /Volumes/T9/Media
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

# Check Plex
if [[ -d "/Applications/Plex Media Server.app" ]] || pgrep -x "Plex Media Server" &>/dev/null; then
    echo -e "${GREEN}OK${NC}  Plex detected"
else
    echo -e "${YELLOW}WARN${NC}  Plex not detected. Install from https://www.plex.tv/media-server-downloads/"
    echo "  You can continue and install Plex later."
fi

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
if ! docker compose up -d; then
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
wait_for_service "qBittorrent" "http://localhost:8080" || true
wait_for_service "Prowlarr" "http://localhost:9696" || true
wait_for_service "Radarr" "http://localhost:7878" || true
wait_for_service "Sonarr" "http://localhost:8989" || true
wait_for_service "Seerr" "http://localhost:5055" || true
wait_for_service "Tdarr" "http://localhost:8265" || true

# Configure
echo ""
if [[ "$NON_INTERACTIVE" == true ]]; then
    bash scripts/configure.sh --non-interactive
else
    bash scripts/configure.sh
fi

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
echo "  Plex:   http://localhost:32400/web"
echo "  Tdarr:  http://localhost:8265"
echo ""
echo "  Media location: $MEDIA_DIR"
echo ""
echo "  Remaining manual steps:"
echo "    1. Set up Plex libraries (Movies: $MEDIA_DIR/Movies, TV: $MEDIA_DIR/TV Shows)"
echo "    2. Edit $MEDIA_DIR/config/kometa/config.yml with Plex token + TMDB key"
echo "    3. Configure Tdarr at http://localhost:8265"
echo ""
echo "  Optional - Music (Lidarr + Tidarr):"
echo "    bash scripts/setup-music.sh"
echo "    docker compose --profile music up -d"
echo "    Then open http://localhost:8484 to authenticate with Tidal"
echo ""
echo "  API keys were printed and Recyclarr/Unpackerr were auto-wired by configure.sh."
echo ""
