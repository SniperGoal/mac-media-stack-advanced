#!/bin/bash
# Media Stack Auto-Healer
# Runs hourly via launchd. Checks VPN and container health, restarts what's broken.

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
# shellcheck source=scripts/lib/media-path.sh
source "$SCRIPT_DIR/lib/media-path.sh"

BASE_DIR="$(resolve_media_dir "$PROJECT_DIR")"
LOG_DIR="$BASE_DIR/logs"
mkdir -p "$LOG_DIR"
LOG="$LOG_DIR/auto-heal.log"

timestamp() { date "+%Y-%m-%d %H:%M:%S"; }
log() { echo "$(timestamp) $1" >> "$LOG"; }

# Trim log
if [[ -f "$LOG" ]] && [[ $(wc -l < "$LOG") -gt 500 ]]; then
    tmp=$(mktemp)
    trap "rm -f '$tmp'" EXIT
    tail -n 1000 "$LOG" > "$tmp" && mv "$tmp" "$LOG"
    trap - EXIT
fi

log "--- Health check started ---"

if ! docker info &>/dev/null; then
    log "ERROR: Container runtime not running"
    exit 1
fi

HEALED=0

# Check VPN
vpn_ip=$(docker exec gluetun sh -lc 'cat /tmp/gluetun/ip 2>/dev/null || true' 2>/dev/null)
vpn_iface=$(docker exec gluetun sh -lc 'ls /sys/class/net 2>/dev/null | grep -E "^(tun|wg)[0-9]+$" | head -1' 2>/dev/null)
vpn_health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unknown{{end}}' gluetun 2>/dev/null || true)

if [[ -z "$vpn_ip" || -z "$vpn_iface" || "$vpn_health" == "unhealthy" ]]; then
    log "WARN: VPN issue (health=${vpn_health:-unknown}, ip=${vpn_ip:-none}, iface=${vpn_iface:-none}). Restarting gluetun..."
    docker restart gluetun >> "$LOG" 2>&1
    sleep 15
    vpn_ip=$(docker exec gluetun sh -lc 'cat /tmp/gluetun/ip 2>/dev/null || true' 2>/dev/null)
    vpn_iface=$(docker exec gluetun sh -lc 'ls /sys/class/net 2>/dev/null | grep -E "^(tun|wg)[0-9]+$" | head -1' 2>/dev/null)
    vpn_health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unknown{{end}}' gluetun 2>/dev/null || true)
    if [[ -n "$vpn_ip" && -n "$vpn_iface" && "$vpn_health" != "unhealthy" ]]; then
        log "OK: VPN recovered (IP: $vpn_ip, iface=$vpn_iface, health=${vpn_health:-unknown})"
    else
        log "ERROR: VPN still down after restart (health=${vpn_health:-unknown}, ip=${vpn_ip:-none}, iface=${vpn_iface:-none})"
    fi
    ((HEALED++))
else
    log "OK: VPN active (IP: $vpn_ip, iface=$vpn_iface, health=${vpn_health:-unknown})"
fi

# Read media server choice
# shellcheck disable=SC1091
source "$PROJECT_DIR/.env" 2>/dev/null || true
TDARR_MODE="${TDARR_MODE:-native}"
if [[ "$TDARR_MODE" != "native" && "$TDARR_MODE" != "docker" ]]; then
    TDARR_MODE="native"
fi

# Check containers
CONTAINERS="gluetun qbittorrent prowlarr sonarr radarr bazarr flaresolverr seerr unpackerr recyclarr lidarr tidarr"
if [[ "$TDARR_MODE" == "docker" ]]; then
    CONTAINERS="$CONTAINERS tdarr"
fi
if [[ "${MEDIA_SERVER:-plex}" == "jellyfin" ]]; then
    CONTAINERS="$CONTAINERS jellyfin jellystat-db jellystat"
fi
for name in $CONTAINERS; do
    state=$(docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null)
    # Skip music services if not installed
    if [[ "$name" == "lidarr" || "$name" == "tidarr" ]] && [[ -z "$state" ]]; then
        continue
    fi
    if [[ "$state" != "running" ]]; then
        log "WARN: $name is $state. Starting..."
        docker start "$name" >> "$LOG" 2>&1
        ((HEALED++))
    fi
done

if [[ "$TDARR_MODE" == "native" ]]; then
    tdarr_ok=true
    if ! launchctl print "gui/$UID/com.media-stack.tdarr.server" >/dev/null 2>&1; then
        tdarr_ok=false
        log "WARN: tdarr-server launchd job missing. Attempting load..."
        launchctl load "$HOME/Library/LaunchAgents/com.media-stack.tdarr.server.plist" >> "$LOG" 2>&1 || true
        launchctl kickstart -k "gui/$UID/com.media-stack.tdarr.server" >> "$LOG" 2>&1 || true
        ((HEALED++))
    fi
    if ! launchctl print "gui/$UID/com.media-stack.tdarr.node" >/dev/null 2>&1; then
        tdarr_ok=false
        log "WARN: tdarr-node launchd job missing. Attempting load..."
        launchctl load "$HOME/Library/LaunchAgents/com.media-stack.tdarr.node.plist" >> "$LOG" 2>&1 || true
        launchctl kickstart -k "gui/$UID/com.media-stack.tdarr.node" >> "$LOG" 2>&1 || true
        ((HEALED++))
    fi

    tdarr_http=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 http://localhost:8265 2>/dev/null || echo "000")
    if [[ "$tdarr_http" =~ ^(200|301|302|307|401|403)$ ]]; then
        if [[ "$tdarr_ok" == true ]]; then
            log "OK: Tdarr native healthy"
        fi
    else
        log "WARN: Tdarr UI check failed (HTTP $tdarr_http). Restarting tdarr launchd jobs..."
        launchctl kickstart -k "gui/$UID/com.media-stack.tdarr.server" >> "$LOG" 2>&1 || true
        sleep 3
        launchctl kickstart -k "gui/$UID/com.media-stack.tdarr.node" >> "$LOG" 2>&1 || true
        ((HEALED++))
    fi
fi

if [[ $HEALED -gt 0 ]]; then
    log "Healed $HEALED issue(s)"
else
    log "All healthy"
fi
