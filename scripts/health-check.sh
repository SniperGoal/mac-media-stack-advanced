#!/bin/bash
# Media Stack Health Check (Advanced)
# Checks all containers including Tdarr, Recyclarr, Unpackerr, Kometa.

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=scripts/lib/runtime.sh
source "$SCRIPT_DIR/scripts/lib/runtime.sh"

PASS=0
FAIL=0

check_service() {
    local name="$1" url="$2"
    status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "$url" 2>/dev/null)
    if [[ "$status" =~ ^[23][0-9][0-9]$ ]]; then
        echo -e "  ${GREEN}OK${NC}  $name"
        ((PASS++))
    else
        echo -e "  ${RED}FAIL${NC}  $name (HTTP $status)"
        ((FAIL++))
    fi
}

echo ""
echo "=============================="
echo "  Media Stack Health Check"
echo "=============================="
echo ""

RUNTIME=$(detect_installed_runtime)

if docker info &>/dev/null; then
    RUNTIME=$(detect_running_runtime)
    echo -e "  ${GREEN}OK${NC}  $RUNTIME"
    ((PASS++))
else
    echo -e "  ${RED}FAIL${NC}  $RUNTIME (not running)"
    exit 1
fi
echo ""

echo "Containers:"
for name in gluetun qbittorrent prowlarr sonarr radarr bazarr flaresolverr seerr tdarr unpackerr recyclarr kometa tautulli lidarr tidarr; do
    state=$(docker inspect -f '{{.State.Status}}' "$name" 2>/dev/null)
    if [[ "$state" == "running" ]]; then
        echo -e "  ${GREEN}OK${NC}  $name"
        ((PASS++))
    elif [[ "$name" == "kometa" ]] && [[ "$state" == "exited" || "$state" == "created" ]]; then
        # Kometa runs as a one-shot, exited is normal
        echo -e "  ${YELLOW}OK${NC}  $name (one-shot, not always running)"
    elif [[ "$name" == "tautulli" ]] && [[ -z "$state" ]]; then
        echo -e "  ${YELLOW}SKIP${NC}  $name (not installed)"
    elif [[ "$name" == "lidarr" || "$name" == "tidarr" ]] && [[ -z "$state" ]]; then
        echo -e "  ${YELLOW}SKIP${NC}  $name (music profile not enabled)"
    else
        echo -e "  ${RED}FAIL${NC}  $name (${state:-not found})"
        ((FAIL++))
    fi
done

watchtower_state=$(docker inspect -f '{{.State.Status}}' watchtower 2>/dev/null || true)
if [[ "$watchtower_state" == "running" ]]; then
    echo -e "  ${GREEN}OK${NC}  watchtower (autoupdate profile enabled)"
    ((PASS++))
else
    echo -e "  ${YELLOW}SKIP${NC}  watchtower (optional; enable with --profile autoupdate)"
fi

echo ""
echo "Web UIs:"
check_service "qBittorrent" "http://localhost:8080"
check_service "Prowlarr" "http://localhost:9696"
check_service "Sonarr" "http://localhost:8989"
check_service "Radarr" "http://localhost:7878"
check_service "Bazarr" "http://localhost:6767"
check_service "Seerr" "http://localhost:5055"
check_service "Tdarr" "http://localhost:8265"
check_service "FlareSolverr" "http://localhost:8191"

# Tautulli (optional, not part of compose by default)
if docker inspect -f '{{.State.Status}}' tautulli &>/dev/null; then
    check_service "Tautulli" "http://localhost:8181"
fi

# Music services (only if profile enabled)
if docker inspect -f '{{.State.Status}}' lidarr &>/dev/null; then
    check_service "Lidarr" "http://localhost:8686"
    check_service "Tidarr" "http://localhost:8484"
fi

echo ""
echo "VPN:"
vpn_ip=$(docker exec gluetun sh -lc 'cat /tmp/gluetun/ip 2>/dev/null || true' 2>/dev/null)
vpn_iface=$(docker exec gluetun sh -lc 'ls /sys/class/net 2>/dev/null | grep -E "^(tun|wg)[0-9]+$" | head -1' 2>/dev/null)
vpn_health=$(docker inspect -f '{{if .State.Health}}{{.State.Health.Status}}{{else}}unknown{{end}}' gluetun 2>/dev/null || true)
if [[ -n "$vpn_ip" && -n "$vpn_iface" && "$vpn_health" != "unhealthy" ]]; then
    echo -e "  ${GREEN}OK${NC}  VPN active (IP: $vpn_ip, iface: $vpn_iface, health: ${vpn_health:-unknown})"
    ((PASS++))
elif [[ -z "$vpn_ip" ]]; then
    echo -e "  ${RED}FAIL${NC}  VPN not connected (missing /tmp/gluetun/ip)"
    ((FAIL++))
elif [[ -z "$vpn_iface" ]]; then
    echo -e "  ${RED}FAIL${NC}  VPN tunnel interface not detected in gluetun"
    ((FAIL++))
else
    echo -e "  ${RED}FAIL${NC}  VPN health is unhealthy"
    ((FAIL++))
fi

echo ""
echo "Plex:"
plex_status=$(curl -s -o /dev/null -w "%{http_code}" --max-time 5 "http://localhost:32400/web" 2>/dev/null)
if [[ "$plex_status" =~ ^(200|301|302)$ ]]; then
    echo -e "  ${GREEN}OK${NC}  Plex"
    ((PASS++))
else
    echo -e "  ${YELLOW}SKIP${NC}  Plex not detected"
fi

echo ""
echo "=============================="
echo -e "  Results: ${GREEN}$PASS passed${NC}, ${RED}$FAIL failed${NC}"
echo "=============================="
echo ""

if [[ $FAIL -gt 0 ]]; then
    echo "Something's not right. Check the FAIL items above."
    echo "Most common fix: restart your container runtime (OrbStack or Docker Desktop) and wait 30 seconds."
    exit 1
else
    echo "Everything looks good!"
fi
