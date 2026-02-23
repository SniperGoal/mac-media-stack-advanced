#!/bin/bash
# Cloud / NAS Storage Setup (rclone + mergerfs)
# Creates directories, configures rclone remote, writes cloud storage env vars.
# Usage: bash scripts/setup-cloud-storage.sh [--media-dir DIR] [--non-interactive] [--storage-type TYPE] [--help]

set -e

YELLOW='\033[1;33m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
RED='\033[0;31m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/media-path.sh
source "$SCRIPT_DIR/scripts/lib/media-path.sh"

NON_INTERACTIVE=false
STORAGE_TYPE=""

usage() {
    cat <<EOF
Usage: bash scripts/setup-cloud-storage.sh [OPTIONS]

Sets up rclone + mergerfs cloud storage integration.

Options:
  --media-dir DIR       Media root path (default: from .env, otherwise ~/Media)
  --non-interactive     Skip interactive prompts (requires RCLONE_REMOTE in .env)
  --storage-type TYPE   Storage type: cloud (default) or nas
  --help                Show this help message
EOF
}

MEDIA_DIR_OVERRIDE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --media-dir)
            if [[ $# -lt 2 || "$2" == --* ]]; then
                echo "Missing value for --media-dir"
                exit 1
            fi
            MEDIA_DIR_OVERRIDE="$2"
            shift 2
            ;;
        --non-interactive)
            NON_INTERACTIVE=true
            shift
            ;;
        --storage-type)
            if [[ $# -lt 2 || "$2" == --* ]]; then
                echo "Missing value for --storage-type"
                exit 1
            fi
            STORAGE_TYPE="$2"
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

if [[ -n "$MEDIA_DIR_OVERRIDE" ]]; then
    MEDIA_DIR="$MEDIA_DIR_OVERRIDE"
else
    MEDIA_DIR="$(resolve_media_dir "$SCRIPT_DIR")"
fi

echo ""
echo "=============================="
echo "  Cloud / NAS Storage Setup"
echo "=============================="
echo ""

# Determine storage type
if [[ -z "$STORAGE_TYPE" && "$NON_INTERACTIVE" == false ]]; then
    echo "What type of storage backend?"
    echo ""
    echo "  1) Cloud provider (Google Drive, S3, B2, Dropbox, etc.)"
    echo "  2) NAS (TrueNAS, Synology, Unraid — SFTP over LAN)"
    echo ""
    read -p "  Choice [1/2]: " storage_choice
    echo ""
    case "$storage_choice" in
        2) STORAGE_TYPE="nas" ;;
        *) STORAGE_TYPE="cloud" ;;
    esac
elif [[ -z "$STORAGE_TYPE" ]]; then
    STORAGE_TYPE="cloud"
fi

MEDIA_SERVER="plex"
TDARR_MODE="native"
if [[ -f "$SCRIPT_DIR/.env" ]]; then
    env_server=$(sed -n 's/^MEDIA_SERVER=//p' "$SCRIPT_DIR/.env" | head -1)
    env_tdarr_mode=$(sed -n 's/^TDARR_MODE=//p' "$SCRIPT_DIR/.env" | head -1)
    [[ -n "$env_server" ]] && MEDIA_SERVER="$env_server"
    [[ -n "$env_tdarr_mode" ]] && TDARR_MODE="$env_tdarr_mode"
fi

if [[ "$MEDIA_SERVER" != "jellyfin" ]]; then
    echo -e "${YELLOW}WARN${NC}  Cloud merged mounts are only readable by Docker containers on macOS."
    echo "      Native Plex cannot read merged cloud mount paths."
    echo "      Use Jellyfin for cloud-backed playback (set MEDIA_SERVER=jellyfin)."
    echo ""
fi

if [[ "$TDARR_MODE" == "native" ]]; then
    echo -e "${YELLOW}WARN${NC}  Native Tdarr cannot read merged cloud mount paths."
    echo "      Use TDARR_MODE=docker when cloud storage is enabled."
    echo ""
fi

# Warn if free space is low for VFS cache + active downloads
available_kb=$(df -k "$MEDIA_DIR" 2>/dev/null | awk 'NR==2 {print $4}')
if [[ -n "$available_kb" && "$available_kb" =~ ^[0-9]+$ ]]; then
    available_gb=$((available_kb / 1024 / 1024))
    if ((available_gb < 100)); then
        echo -e "${YELLOW}WARN${NC}  Only ~${available_gb}GB free at $MEDIA_DIR."
        echo "      Cloud VFS cache + active downloads can consume space quickly."
        echo "      Recommended free space: at least 100GB."
        echo ""
    fi
fi

# Create directories
echo "Creating cloud storage directories..."
mkdir -p "$MEDIA_DIR"/{config/rclone,cloud,merged}
echo -e "  ${GREEN}Done${NC}"
echo ""

setup_nas_sftp() {
    echo "NAS SFTP Configuration"
    echo ""

    read -p "  NAS hostname or IP: " nas_host
    read -p "  SSH username: " nas_user

    echo ""
    echo "  SSH authentication:"
    echo "    a) Generate a new SSH key pair"
    echo "    b) Use an existing SSH key"
    echo "    c) Use password authentication"
    echo ""
    read -p "  Choice [a/b/c]: " auth_choice
    echo ""

    NAS_KEY_PATH=""
    NAS_USE_PASSWORD=false

    case "$auth_choice" in
        a)
            NAS_KEY_PATH="$MEDIA_DIR/config/rclone/nas_key.pem"
            echo "  Generating SSH key pair..."
            ssh-keygen -t ed25519 -f "$NAS_KEY_PATH" -N "" -q
            chmod 600 "$NAS_KEY_PATH"
            echo -e "  ${GREEN}Key generated:${NC} $NAS_KEY_PATH"
            echo ""
            echo -e "  ${CYAN}Add this public key to your NAS authorized_keys:${NC}"
            echo ""
            cat "${NAS_KEY_PATH}.pub"
            echo ""
            read -p "  Press Enter after adding the key to your NAS..." _
            ;;
        b)
            read -p "  Path to existing SSH private key: " existing_key
            existing_key="${existing_key/#\~/$HOME}"
            if [[ -f "$existing_key" ]]; then
                NAS_KEY_PATH="$MEDIA_DIR/config/rclone/nas_key.pem"
                cp "$existing_key" "$NAS_KEY_PATH"
                chmod 600 "$NAS_KEY_PATH"
                echo -e "  ${GREEN}Copied${NC}"
            else
                echo -e "  ${RED}File not found:${NC} $existing_key"
                return 1
            fi
            ;;
        c)
            NAS_USE_PASSWORD=true
            echo -e "  ${YELLOW}Note:${NC} Password auth works but SSH key auth is recommended for unattended operation."
            ;;
    esac

    echo ""
    echo "  Common NAS media paths:"
    echo "    TrueNAS:  /mnt/pool/dataset/media"
    echo "    Synology:  /volume1/media"
    echo "    Unraid:    /mnt/user/media"
    echo ""
    read -p "  Media path on NAS: " nas_path
    echo ""

    # Detect Synology (path starts with /volume)
    SFTP_OVERRIDE=""
    if [[ "$nas_path" == /volume* ]]; then
        echo -e "  ${CYAN}Detected Synology path.${NC} Adding --sftp-path-override for SFTP chroot compatibility."
        SFTP_OVERRIDE="true"
    fi

    # Write rclone.conf for NAS SFTP
    RCLONE_CONF="$MEDIA_DIR/config/rclone/rclone.conf"
    RCLONE_REMOTE="${RCLONE_REMOTE:-mynas}"
    RCLONE_REMOTE_PATH="$nas_path"

    cat > "$RCLONE_CONF" <<RCLONEEOF
[$RCLONE_REMOTE]
type = sftp
host = $nas_host
user = $nas_user
RCLONEEOF

    if [[ "$NAS_USE_PASSWORD" == true ]]; then
        echo "# Run: rclone obscure YOUR_PASSWORD, then set pass = RESULT" >> "$RCLONE_CONF"
    elif [[ -n "$NAS_KEY_PATH" ]]; then
        echo "key_file = /config/rclone/nas_key.pem" >> "$RCLONE_CONF"
    fi

    if [[ "$SFTP_OVERRIDE" == "true" ]]; then
        echo "sftp_path_override = $nas_path" >> "$RCLONE_CONF"
    fi

    echo "" >> "$RCLONE_CONF"
    echo -e "  ${GREEN}rclone.conf written${NC}"

    # Test connectivity
    echo ""
    echo "  Testing NAS connectivity..."
    if docker run --rm \
        -v "$MEDIA_DIR/config/rclone:/config/rclone" \
        rclone/rclone lsd "${RCLONE_REMOTE}:${RCLONE_REMOTE_PATH}" \
        --contimeout 10s 2>/dev/null; then
        echo -e "  ${GREEN}Connected to NAS${NC}"
    else
        echo -e "  ${YELLOW}WARN${NC}  Could not connect to NAS. Check hostname, credentials, and path."
        echo "  You can edit $RCLONE_CONF manually and retry."
    fi
}

# Branch on storage type
if [[ "$STORAGE_TYPE" == "nas" ]]; then
    setup_nas_sftp
fi

# Check for existing rclone.conf
RCLONE_CONF="$MEDIA_DIR/config/rclone/rclone.conf"

if [[ "$STORAGE_TYPE" != "nas" ]]; then
if [[ -f "$RCLONE_CONF" ]]; then
    echo -e "${GREEN}Found${NC} existing rclone.conf at $RCLONE_CONF"
    echo ""
else
    if [[ "$NON_INTERACTIVE" == true ]]; then
        echo -e "${YELLOW}WARN${NC}  No rclone.conf found. Create one manually at:"
        echo "  $RCLONE_CONF"
        echo ""
        echo "  Or copy the example:"
        echo "  cp $SCRIPT_DIR/configs/rclone.conf.example $RCLONE_CONF"
    else
        echo "No rclone.conf found. How would you like to configure your cloud remote?"
        echo ""
        echo "  1) Run rclone config wizard (interactive, in Docker)"
        echo "  2) Copy an existing rclone.conf from another location"
        echo "  3) Skip (configure manually later)"
        echo ""
        read -p "  Choice [1/2/3]: " choice
        echo ""

        case "$choice" in
            1)
                echo -e "${CYAN}Starting rclone config wizard...${NC}"
                echo "  (This runs inside Docker. Follow the prompts to set up your remote.)"
                echo ""
                docker run --rm -it \
                    -v "$MEDIA_DIR/config/rclone:/config/rclone" \
                    rclone/rclone config
                echo ""
                ;;
            2)
                read -p "  Path to existing rclone.conf: " existing_conf
                existing_conf="${existing_conf/#\~/$HOME}"
                if [[ -f "$existing_conf" ]]; then
                    cp "$existing_conf" "$RCLONE_CONF"
                    echo -e "  ${GREEN}Copied${NC}"
                else
                    echo -e "  ${RED}File not found:${NC} $existing_conf"
                    echo "  You can copy it manually later to: $RCLONE_CONF"
                fi
                echo ""
                ;;
            3|*)
                echo "  Skipped. Copy your rclone.conf to: $RCLONE_CONF"
                echo "  Or copy the example: cp $SCRIPT_DIR/configs/rclone.conf.example $RCLONE_CONF"
                echo ""
                ;;
        esac
    fi
fi
fi

# Get remote name and path
RCLONE_REMOTE=""
RCLONE_REMOTE_PATH=""

if [[ -f "$SCRIPT_DIR/.env" ]]; then
    existing_remote=$(sed -n 's/^RCLONE_REMOTE=//p' "$SCRIPT_DIR/.env" | head -1)
    existing_path=$(sed -n 's/^RCLONE_REMOTE_PATH=//p' "$SCRIPT_DIR/.env" | head -1)
    if [[ -n "$existing_remote" ]]; then
        RCLONE_REMOTE="$existing_remote"
        RCLONE_REMOTE_PATH="${existing_path:-}"
    fi
fi

if [[ -z "$RCLONE_REMOTE" && "$NON_INTERACTIVE" == false ]]; then
    if [[ -f "$RCLONE_CONF" ]]; then
        echo "Available remotes in your rclone.conf:"
        grep '^\[' "$RCLONE_CONF" | tr -d '[]' | while read -r name; do
            echo "  - $name"
        done
        echo ""
    fi

    read -p "  Remote name (from rclone.conf): " RCLONE_REMOTE
    read -p "  Remote path (leave empty for root): " RCLONE_REMOTE_PATH
    echo ""
fi

if [[ -z "$RCLONE_REMOTE" ]]; then
    echo -e "${YELLOW}WARN${NC}  No remote configured. Set RCLONE_REMOTE in .env before starting."
else
    echo -e "  Remote: ${GREEN}${RCLONE_REMOTE}:${RCLONE_REMOTE_PATH}${NC}"
fi

# Write to .env
ENV_FILE="$SCRIPT_DIR/.env"
if [[ -f "$ENV_FILE" ]]; then
    # Append or update cloud storage vars
    for var in CLOUD_STORAGE_ENABLED RCLONE_REMOTE RCLONE_REMOTE_PATH; do
        if grep -q "^${var}=" "$ENV_FILE" 2>/dev/null; then
            case "$var" in
                CLOUD_STORAGE_ENABLED) sed -i '' "s|^${var}=.*|${var}=true|" "$ENV_FILE" ;;
                RCLONE_REMOTE) [[ -n "$RCLONE_REMOTE" ]] && sed -i '' "s|^${var}=.*|${var}=$RCLONE_REMOTE|" "$ENV_FILE" ;;
                RCLONE_REMOTE_PATH) sed -i '' "s|^${var}=.*|${var}=$RCLONE_REMOTE_PATH|" "$ENV_FILE" ;;
            esac
        elif grep -q "^# ${var}=" "$ENV_FILE" 2>/dev/null; then
            case "$var" in
                CLOUD_STORAGE_ENABLED) sed -i '' "s|^# ${var}=.*|${var}=true|" "$ENV_FILE" ;;
                RCLONE_REMOTE) [[ -n "$RCLONE_REMOTE" ]] && sed -i '' "s|^# ${var}=.*|${var}=$RCLONE_REMOTE|" "$ENV_FILE" ;;
                RCLONE_REMOTE_PATH) sed -i '' "s|^# ${var}=.*|${var}=$RCLONE_REMOTE_PATH|" "$ENV_FILE" ;;
            esac
        else
            case "$var" in
                CLOUD_STORAGE_ENABLED) printf '\n%s=true\n' "$var" >> "$ENV_FILE" ;;
                RCLONE_REMOTE) [[ -n "$RCLONE_REMOTE" ]] && printf '%s=%s\n' "$var" "$RCLONE_REMOTE" >> "$ENV_FILE" ;;
                RCLONE_REMOTE_PATH) printf '%s=%s\n' "$var" "$RCLONE_REMOTE_PATH" >> "$ENV_FILE" ;;
            esac
        fi
    done

    # Add VFS cache defaults if not present
    for default_var in "RCLONE_VFS_CACHE_MODE=full" "RCLONE_VFS_CACHE_MAX_SIZE=50G" "RCLONE_VFS_CACHE_MAX_AGE=72h" "RCLONE_VFS_READ_CHUNK_SIZE=128M" "CLOUD_UPLOAD_MIN_AGE_HOURS=24"; do
        var_name="${default_var%%=*}"
        if ! grep -q "^${var_name}=" "$ENV_FILE" 2>/dev/null && ! grep -q "^# ${var_name}=" "$ENV_FILE" 2>/dev/null; then
            printf '# %s\n' "$default_var" >> "$ENV_FILE"
        fi
    done

    echo -e "  ${GREEN}Updated .env${NC}"

    if [[ "$STORAGE_TYPE" == "nas" ]]; then
        # Write NAS-optimized defaults
        for nas_default in "STORAGE_TYPE=nas" "RCLONE_VFS_CACHE_MAX_SIZE=10G" "RCLONE_VFS_CACHE_MAX_AGE=1h" "RCLONE_VFS_READ_CHUNK_SIZE=32M" "RCLONE_DIR_CACHE_TIME=30s" "CLOUD_UPLOAD_MIN_AGE_HOURS=2"; do
            var_name="${nas_default%%=*}"
            var_value="${nas_default#*=}"
            if grep -q "^${var_name}=" "$ENV_FILE" 2>/dev/null; then
                sed -i '' "s|^${var_name}=.*|${var_name}=$var_value|" "$ENV_FILE"
            elif grep -q "^# ${var_name}=" "$ENV_FILE" 2>/dev/null; then
                sed -i '' "s|^# ${var_name}=.*|${var_name}=$var_value|" "$ENV_FILE"
            else
                printf '%s=%s\n' "$var_name" "$var_value" >> "$ENV_FILE"
            fi
        done
        echo -e "  ${GREEN}NAS-optimized defaults written${NC}"
    fi
else
    echo -e "  ${YELLOW}WARN${NC}  No .env file found. Run scripts/setup.sh first."
fi

# Create remote directories
if [[ -n "$RCLONE_REMOTE" && -f "$RCLONE_CONF" ]]; then
    echo ""
    echo "Creating remote directories..."
    docker run --rm \
        -v "$MEDIA_DIR/config/rclone:/config/rclone" \
        rclone/rclone mkdir "${RCLONE_REMOTE}:${RCLONE_REMOTE_PATH:+${RCLONE_REMOTE_PATH}/}Movies" 2>/dev/null && \
        echo -e "  ${GREEN}OK${NC}  ${RCLONE_REMOTE}:Movies" || \
        echo -e "  ${YELLOW}WARN${NC}  Could not create Movies on remote"

    docker run --rm \
        -v "$MEDIA_DIR/config/rclone:/config/rclone" \
        rclone/rclone mkdir "${RCLONE_REMOTE}:${RCLONE_REMOTE_PATH:+${RCLONE_REMOTE_PATH}/}TV Shows" 2>/dev/null && \
        echo -e "  ${GREEN}OK${NC}  ${RCLONE_REMOTE}:TV Shows" || \
        echo -e "  ${YELLOW}WARN${NC}  Could not create TV Shows on remote"
fi

# Disk space warning
available_gb=$(df -g "$MEDIA_DIR" 2>/dev/null | awk 'NR==2{print $4}' || echo "0")
if [[ "$available_gb" -lt 100 && "$available_gb" -gt 0 ]]; then
    echo ""
    echo -e "  ${YELLOW}WARN${NC}  Only ${available_gb}GB free on $(df "$MEDIA_DIR" | awk 'NR==2{print $1}')"
    echo "  VFS cache defaults to 50GB. Adjust RCLONE_VFS_CACHE_MAX_SIZE in .env if needed."
fi

echo ""
echo "=============================="
if [[ "$STORAGE_TYPE" == "nas" ]]; then
    echo "  NAS storage setup complete!"
else
    echo "  Cloud storage setup complete!"
fi
echo "=============================="
echo ""
echo "Next steps:"
echo "  1. Verify your rclone.conf at: $RCLONE_CONF"
echo "  2. Start with cloud storage:"
echo "     docker compose -f docker-compose.yml -f docker-compose.cloud-storage.yml --profile cloud-storage up -d"
echo ""
echo "  Or use bootstrap.sh --cloud-storage for a full install."
echo ""
echo "Optional - Periodic cloud upload:"
echo "  bash scripts/install-launchd-jobs.sh  (installs cloud-upload every 6 hours)"
echo ""
