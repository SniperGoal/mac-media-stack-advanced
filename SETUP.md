# Media Server Setup Guide (Advanced)

Everything from the [basic setup](https://github.com/liamvibecodes/mac-media-stack), plus transcoding, quality profiles, metadata automation, download watchdog, VPN failover, and automated backups.

**Time to complete:** About 30 minutes

---

## Quick Option: One-Command Install

If you already have OrbStack (or Docker Desktop) and Plex installed, you can run a single command that handles the core setup:

```bash
curl -fsSL https://raw.githubusercontent.com/liamvibecodes/mac-media-stack-advanced/main/bootstrap.sh | bash
```

It will prompt you for VPN keys, configure all core services, auto-wire Recyclarr + Unpackerr API keys, and install automation jobs. You'll still need to do Step 7 for Kometa/Tdarr manual setup afterward.

To run from a local clone with custom paths:

```bash
bash bootstrap.sh --media-dir /Volumes/T9/Media --install-dir ~/mac-media-stack-advanced
```

Already running the basic stack and want an in-place migration? Use [UPGRADE.md](UPGRADE.md).

---

## Prerequisites

- A Mac (any recent macOS)
- At least 50GB free disk space (media libraries will need more)
- [OrbStack](https://orbstack.dev) (recommended) or [Docker Desktop](https://www.docker.com/products/docker-desktop/) installed and running
- **Plex** installed and signed in, OR use **Jellyfin** (runs in Docker, no install needed)
- ProtonVPN WireGuard credentials
- A free TMDB API key (https://www.themoviedb.org/settings/api) (Plex/Kometa only)

> **Why OrbStack?** It starts in ~2 seconds (vs 30s for Docker Desktop), uses ~1GB RAM (vs 4GB), and has 2-10x faster file I/O. It's a drop-in replacement that runs the same Docker commands. Docker Desktop works fine too.

---

## Step 1: Install a Container Runtime

You need a container runtime to run the behind-the-scenes services. Pick one:

### Option A: OrbStack (Recommended)

OrbStack is faster and lighter than Docker Desktop (~2s startup, ~1GB RAM).

```bash
brew install --cask orbstack
```

Or download from https://orbstack.dev. Open it once after installing.

### Option B: Docker Desktop

1. Go to https://www.docker.com/products/docker-desktop/
2. Click "Download for Mac"
   - If you have an M-series Mac (M1, M2, M3, M4): choose "Apple Silicon"
   - If you're not sure, click the Apple icon top-left of your screen > "About This Mac" and check the chip
3. Open the downloaded `.dmg` file
4. Drag Docker to your Applications folder
5. Open Docker Desktop from Applications
6. It will ask for your password to install components. Enter it.
7. Wait for it to finish starting (the whale icon in your menu bar will stop animating)
8. In Docker Desktop settings (gear icon), go to "General" and make sure "Start Docker Desktop when you sign in" is checked

Both options use the same `docker` and `docker compose` commands. Everything in this guide works identically with either one.

If you use a custom media location (`MEDIA_DIR` in `.env`), replace any `~/Media` path below with that value.

---

## Choose Your Media Server

This stack supports two media servers. Choose one:

**Plex (default):** Runs natively on macOS. Requires the Plex app installed. Supports Kometa metadata automation and franchise sorting.

**Jellyfin:** Free and open-source. Runs entirely in Docker. No app install needed. Kometa and franchise-sort are skipped automatically (Jellyfin has built-in collection management).

To use Jellyfin, pass `--jellyfin` to the bootstrap command, or set `MEDIA_SERVER=jellyfin` in your `.env` file.

---

## Step 2: Download and Setup

```bash
cd ~
git clone https://github.com/liamvibecodes/mac-media-stack-advanced.git
cd mac-media-stack-advanced
bash scripts/setup.sh
# or:
# bash scripts/setup.sh --media-dir /Volumes/T9/Media
```

---

## Step 3: Add VPN Keys

```bash
open -a TextEdit .env
```

Fill in `WIREGUARD_PRIVATE_KEY` and `WIREGUARD_ADDRESSES` from your ProtonVPN account.

Get your WireGuard private key from https://account.protonvpn.com/downloads#wireguard-configuration

---

## Step 4: Start the Stack

Run preflight checks before first startup:

```bash
bash scripts/doctor.sh
```

Then start the stack:

```bash
docker compose up -d
bash scripts/health-check.sh
```

If using Jellyfin, start with the profile enabled:

```bash
docker compose --profile jellyfin up -d
```

Wait for all containers to show OK. First pull takes 3-5 GB.

Optional: enable automatic container updates (Watchtower):
```bash
docker compose --profile autoupdate up -d watchtower
```

---

## Verify Your VPN Kill Switch

Once the stack is running, confirm your real IP is never exposed through the VPN tunnel:

```bash
# 1. Check the VPN's IP (should be your VPN provider, not your ISP)
docker exec gluetun sh -c 'wget -qO- https://ipinfo.io/ip'

# 2. Check your real IP (run outside Docker)
curl -s https://ipinfo.io/ip

# 3. Confirm they're different
```

To test the kill switch (traffic should be blocked when the VPN drops):

```bash
# Stop the VPN container
docker stop gluetun

# Try reaching the internet from qBittorrent — should fail/timeout
# (qBittorrent is routed through gluetun and should have no network when gluetun is down)
docker exec qbittorrent wget -qO- --timeout=5 https://ipinfo.io/ip 2>&1 || echo "Kill switch works: qBittorrent has no network"

# Restore the VPN
docker start gluetun
```

If the second `wget` returns an IP instead of timing out, your kill switch isn't working. Check your Gluetun configuration.

> **macOS note:** On macOS, Docker runs inside a Linux VM (OrbStack or Docker Desktop). The kill switch blocks traffic at the container/VM level, not at the macOS network layer. This means containers routed through Gluetun are protected, but apps running directly on macOS are not affected. This is normal and expected.

---

## Step 5: Auto-Configure Services

```bash
bash scripts/configure.sh
```

This configures qBittorrent, Prowlarr (indexers), Radarr, Sonarr, and Seerr. It will print your API keys at the end. **Save them.**
It also writes credentials/API keys to `<MEDIA_DIR>/state/first-run-credentials.txt` (mode `600`, default path `~/Media/state/first-run-credentials.txt`).

---

## Step 6: Set Up Media Server Libraries

### Plex

1. Open http://localhost:32400/web
2. Settings > Libraries > Add Library
3. Add Movies (your home folder > Media > Movies)
4. Add TV Shows (your home folder > Media > TV Shows)

### Jellyfin

1. Open http://localhost:8096
2. Complete the setup wizard
3. Add libraries: Movies = `/data/movies`, TV Shows = `/data/tvshows`
4. Generate an API key (Administration > API Keys) if you plan to use `archive-media.sh --only-watched`

---

## Step 7: Configure Advanced Services

> **Jellyfin users:** Skip the Kometa section below. Kometa is Plex-only and is automatically skipped when `MEDIA_SERVER=jellyfin`. Franchise sorting is also Plex-only; Jellyfin has built-in collection management via the Collections plugin.

### Recyclarr (TRaSH quality profiles)

`scripts/configure.sh` now auto-injects your Sonarr/Radarr API keys into `<MEDIA_DIR>/config/recyclarr/recyclarr.yml` (default: `~/Media/config/recyclarr/recyclarr.yml`).
You only need to review it if you want to customize profile behavior.

Recyclarr runs automatically at 3am daily. To trigger a manual sync:
```bash
docker compose run --rm recyclarr sync
```

### Kometa (Plex metadata)

Open the Kometa config and add your Plex token and TMDB API key:

```bash
open -a TextEdit ~/Media/config/kometa/config.yml
```

- **Plex token:** Follow https://support.plex.tv/articles/204059436-finding-an-authentication-token-x-plex-token/
- **TMDB API key:** Create a free account at https://www.themoviedb.org/settings/api

Replace `YOUR_PLEX_TOKEN` and `YOUR_TMDB_API_KEY`, then save.

### Tdarr (transcoding)

1. Open http://localhost:8265
2. Configure your libraries (Movies: `/movies`, TV: `/tv`)
3. Add transcode plugins based on your preference (H.265 conversion saves ~50% disk space)
4. Set the temp/cache directory to `/temp`

### Unpackerr

`scripts/configure.sh` now auto-writes `UN_SONARR_0_API_KEY` and `UN_RADARR_0_API_KEY` in `.env` and restarts Unpackerr.
No manual edit is required unless you want to override defaults.

---

## Step 8: Install Automation Jobs

```bash
bash scripts/install-launchd-jobs.sh
```

This installs:
- Auto-healer (hourly VPN/container health check + restart)
- Nightly backup (configs + databases, 14-day retention)
- Log prune (daily cleanup, removes logs older than 30 days)
- Download watchdog (stalled torrent auto-fix every 15 min)
- Kometa scheduler (metadata refresh every 4 hours)

Automation logs go to `<MEDIA_DIR>/logs/` and launchd stdout/stderr logs go to `<MEDIA_DIR>/logs/launchd/` (default `~/Media/...`).

### Optional: VPN Failover

If you have a NordVPN account as backup:

1. Copy `.env.nord.example` to `.env.nord`
2. Add your NordVPN WireGuard private key
3. Install the failover watcher:
```bash
bash scripts/install-vpn-failover.sh
```

This checks every 2 minutes and auto-switches between Proton and Nord after 3 consecutive failures.
Use `docker-compose.nord-fallback.yml` only for Nord mode; Proton remains the default compose path.

Check current provider anytime:
```bash
bash scripts/vpn-mode.sh status
```

---

## Day-to-Day Usage

| What | Where |
|------|-------|
| Browse and request | http://localhost:5055 |
| Watch (Plex) | http://localhost:32400/web |
| Watch (Jellyfin) | http://localhost:8096 |
| Check downloads | http://localhost:8080 |
| Transcode status | http://localhost:8265 |

Everything else is fully automated.

---

## Troubleshooting

**Check overall health:**
```bash
bash scripts/health-check.sh
```

**View automation logs:**
```bash
tail -50 ~/Media/logs/auto-heal.log
tail -50 ~/Media/logs/download-watchdog.log
tail -50 ~/Media/logs/vpn-failover.log
tail -50 ~/Media/logs/log-prune.log
```

**Manual VPN switch:**
```bash
bash scripts/vpn-mode.sh status    # check current provider
bash scripts/vpn-mode.sh proton    # switch to Proton
bash scripts/vpn-mode.sh nord      # switch to Nord
```

**Restart everything:**
```bash
docker compose down && docker compose up -d
```

**Uninstall automation jobs:**
```bash
for f in ~/Library/LaunchAgents/com.media-stack.*.plist; do launchctl unload "$f" && rm "$f"; done
```
