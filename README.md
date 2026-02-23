<div align="center">
  <br>
  <a href="#one-command-install">
    <img src="https://img.shields.io/badge/MAC_MEDIA_STACK-00C853?style=for-the-badge&logo=apple&logoColor=white" alt="Mac Media Stack" height="40" />
  </a>
  <br>
  <img src="https://img.shields.io/badge/ADVANCED-FFD700?style=flat-square&labelColor=333" alt="Advanced" />
  <br><br>
  <strong>Fully automated, self-healing media server for macOS</strong>
  <br>
  <sub>Everything from the <a href="https://github.com/liamvibecodes/mac-media-stack">basic stack</a>, plus transcoding, quality profiles, metadata automation, download watchdog, VPN failover, and automated backups.</sub>
  <br><br>
  <img src="https://img.shields.io/badge/Docker-2496ED?style=flat-square&logo=docker&logoColor=white" />
  <img src="https://img.shields.io/badge/OrbStack-000000?style=flat-square&logo=data:image/svg+xml;base64,PHN2ZyB3aWR0aD0iMjQiIGhlaWdodD0iMjQiIHZpZXdCb3g9IjAgMCAyNCAyNCIgZmlsbD0ibm9uZSIgeG1sbnM9Imh0dHA6Ly93d3cudzMub3JnLzIwMDAvc3ZnIj48Y2lyY2xlIGN4PSIxMiIgY3k9IjEyIiByPSIxMCIgZmlsbD0id2hpdGUiLz48L3N2Zz4=&logoColor=white" />
  <img src="https://img.shields.io/badge/Plex-EBAF00?style=flat-square&logo=plex&logoColor=white" />
  <img src="https://img.shields.io/badge/Jellyfin-00A4DC?style=flat-square&logo=jellyfin&logoColor=white" />
  <img src="https://img.shields.io/badge/Sonarr-00CCFF?style=flat-square&logo=sonarr&logoColor=white" />
  <img src="https://img.shields.io/badge/Radarr-FFC230?style=flat-square&logo=radarr&logoColor=black" />
  <img src="https://img.shields.io/badge/Lidarr-00CC66?style=flat-square&logo=lidarr&logoColor=white" />
  <img src="https://img.shields.io/badge/Tdarr-5C2D91?style=flat-square&logoColor=white" />
  <img src="https://img.shields.io/badge/Tidarr-1DB954?style=flat-square&logoColor=white" />
  <img src="https://img.shields.io/badge/Recyclarr-FF6B35?style=flat-square&logoColor=white" />
  <img src="https://img.shields.io/badge/Kometa-FF4081?style=flat-square&logoColor=white" />
  <img src="https://img.shields.io/badge/rclone-2596be?style=flat-square&logo=rclone&logoColor=white" />
  <img src="https://img.shields.io/badge/macOS-000000?style=flat-square&logo=apple&logoColor=white" />
  <br><br>
  <img src="https://img.shields.io/github/stars/liamvibecodes/mac-media-stack-advanced?style=flat-square&color=yellow" />
  <img src="https://img.shields.io/github/license/liamvibecodes/mac-media-stack-advanced?style=flat-square" />
  <br><br>
</div>

## Why This One?

There are dozens of *arr stack Docker Compose repos on GitHub. Almost all of them dump a compose file and leave you to figure out the rest. This one is different:

- **One command to install.** Clone, configure, and start everything with a single `curl | bash`. No 45-minute manual setup.
- **Auto-configures itself.** The configure script wires up the core request/download stack via API (qBittorrent, Prowlarr, Radarr, Sonarr, Seerr). No clicking through those web UIs.
- **Auto-wires keys.** The configure script also writes Radarr/Sonarr API keys into Recyclarr and Unpackerr automatically.
- **Built for macOS.** Native paths, launchd instead of systemd, OrbStack or Docker Desktop instead of bare Docker. Not a Linux guide with "should work on Mac" in the footnotes.
- **Self-healing.** Hourly health checks, download watchdog, VPN failover between providers. Runs unattended.
- **Quality automation.** TRaSH Guides profiles filter out bad releases. Kometa keeps Plex metadata clean. Tdarr runs native-first on macOS with a quality-preserving flow preset.

New to self-hosted media? Start with the [basic version](https://github.com/liamvibecodes/mac-media-stack) first.

---

## What's Added Over Basic

| Service | What It Does |
|---------|-------------|
| **Tdarr** | Native-first transcoding on macOS with quality-preserving HEVC flow preset |
| **Recyclarr** | TRaSH Guides quality profiles (penalizes bad release groups, scene releases) |
| **Kometa** | Plex metadata automation (franchise collections, resolution overlays, RT ratings) |
| **Unpackerr** | Auto-extracts RAR'd downloads for Radarr/Sonarr |
| **Jellyfin** | Free, open-source media server (alternative to Plex, runs in Docker) |
| **Intro Skipper** | Jellyfin plugin: auto-detects intros and adds a "Skip Intro" button on TV shows |
| **TMDb Box Sets** | Jellyfin plugin: auto-creates franchise collections from TMDb data (Jellyfin's Kometa) |
| **Jellystat** | Jellyfin analytics dashboard (like Tautulli for Plex: watch history, user stats, library insights) |
| **Cloud / NAS Storage** | rclone + mergerfs: transparent remote/local merged library (Google Drive, S3, B2, Dropbox, NAS via SFTP) |

## Choosing Your Media Server

| | Plex | Jellyfin |
|---|------|----------|
| **Cost** | Free tier + optional Plex Pass | Completely free and open-source |
| **Setup** | Install macOS app, runs natively | Runs in Docker, no app install |
| **Remote access** | Built-in (Plex account) | Manual (reverse proxy) |
| **Kometa support** | Yes (metadata automation) | No (use Jellyfin's built-in collections) |
| **Franchise sort** | Yes (via franchise-sort.py) | No (TMDb Box Sets plugin auto-creates collections) |
| **Analytics** | Tautulli (external) | Jellystat (included, Docker) |
| **Intro skip** | Plex Pass feature | Intro Skipper plugin (free, auto-installed) |
| **Client apps** | Plex apps on all platforms | Jellyfin apps + browser |

Default is **Plex**. To use Jellyfin, pass `--jellyfin` to the bootstrap command.

## Jellyfin-Specific Features

When running with `MEDIA_SERVER=jellyfin`, the stack includes these extras that close the gap with Plex Pass users:

| Feature | What It Does | Plex Equivalent |
|---------|-------------|-----------------|
| **Intro Skipper** | Detects TV show intros via audio fingerprinting, adds a "Skip Intro" button | Plex Pass intro skip |
| **TMDb Box Sets** | Auto-creates franchise collections (Marvel, Star Wars, etc.) from TMDb data | Kometa collections |
| **Jellystat** | Watch history, user activity, library stats dashboard at `http://localhost:3000` | Tautulli |

Intro Skipper and TMDb Box Sets are auto-installed as Jellyfin plugins by `configure.sh`. Jellystat runs as a separate Docker service behind the `jellyfin` profile.

### Jellystat Setup

After the stack is running:

1. Open `http://localhost:3000`
2. Create an admin account
3. Connect to your Jellyfin server: `http://jellyfin:8096`
4. Enter your Jellyfin API key (Administration > API Keys)

Jellystat will start tracking watch history, user activity, and library statistics automatically.

## Optional: Cloud / NAS Storage (rclone + mergerfs)

Transparent cloud/local or NAS/local merged library. rclone FUSE-mounts your remote storage inside Docker (where FUSE works natively on macOS), mergerfs overlays it with local storage, and all existing services see a single unified path. Local-first writes keep downloads fast; a periodic upload script moves stable media to the remote.

Supports Google Drive, S3, Backblaze B2, Dropbox, NAS via SFTP (TrueNAS, Synology, Unraid), and [40+ other providers](https://rclone.org/overview/).

### Compatibility Requirements (macOS)

- Set `MEDIA_SERVER=jellyfin` for cloud-backed playback.
- Set `TDARR_MODE=docker` if you use Tdarr with cloud storage.
- Native macOS apps (like Plex app and native Tdarr) cannot read Docker FUSE merged mounts directly.

### Quick Start

```bash
bash scripts/setup-cloud-storage.sh
docker compose -f docker-compose.yml -f docker-compose.cloud-storage.yml --profile cloud-storage --profile jellyfin --profile tdarr-docker up -d
```

If you also use optional profiles, append them to the same command (example: `--profile jellyfin`, `--profile music`, `--profile tdarr-docker`).

Or include it in bootstrap:

```bash
bash bootstrap.sh --cloud-storage
```

### NAS Quick Start

```bash
bash scripts/setup-cloud-storage.sh --storage-type nas
docker compose -f docker-compose.yml -f docker-compose.cloud-storage.yml --profile cloud-storage --profile jellyfin --profile tdarr-docker up -d
```

Or include it in bootstrap:

```bash
bash bootstrap.sh --nas-storage
```

### How It Works

```
rclone-mount  -->  FUSE mounts cloud provider to /cloud
mergerfs      -->  overlays /local + /cloud into /merged
Radarr/Sonarr -->  read/write /merged (local-first writes)
cloud-upload  -->  periodically moves stable files to remote (6h/24h for cloud, 2h for NAS)
```

### Library paths when cloud storage is enabled

- **Jellyfin (Docker):** keep `/data/movies` and `/data/tvshows` (override maps those to merged paths).
- **Tdarr Docker mode:** keep `/movies` and `/tv` (override maps those to merged paths).

### Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `CLOUD_STORAGE_ENABLED` | `false` | Set to `true` to enable |
| `RCLONE_REMOTE` | (required) | Remote name from rclone.conf |
| `RCLONE_REMOTE_PATH` | (empty) | Subfolder on remote |
| `RCLONE_VFS_CACHE_MODE` | `full` | VFS cache mode (full recommended) |
| `RCLONE_VFS_CACHE_MAX_SIZE` | `50G` | Max local cache size |
| `RCLONE_VFS_CACHE_MAX_AGE` | `72h` | Max cache age |
| `RCLONE_VFS_READ_CHUNK_SIZE` | `128M` | Read chunk size |
| `CLOUD_UPLOAD_MIN_AGE_HOURS` | `24` | Only upload files older than this |

### NAS Configuration (LAN-Optimized Defaults)

| Variable | Default | Description |
|----------|---------|-------------|
| `STORAGE_TYPE` | (empty) | Set to `nas` for NAS mode |
| `RCLONE_DIR_CACHE_TIME` | `30s` | Directory listing cache (shorter for LAN) |
| `RCLONE_VFS_CACHE_MAX_SIZE` | `10G` | Smaller cache needed on fast LAN |
| `RCLONE_VFS_CACHE_MAX_AGE` | `1h` | Shorter cache age on LAN |
| `RCLONE_VFS_READ_CHUNK_SIZE` | `32M` | Read chunk size |
| `CLOUD_UPLOAD_MIN_AGE_HOURS` | `2` | Upload files older than 2h (vs 24h for cloud) |

**Platform notes:**
- **TrueNAS:** Media path is typically `/mnt/pool/dataset/media`
- **Synology:** Path is `/volume1/media`. The setup wizard auto-adds `--sftp-path-override` for SFTP chroot compatibility.
- **Unraid:** Path is `/mnt/user/media`

**Performance:** rclone SFTP delivers ~100MB/s on Gigabit LAN, adequate for multiple concurrent 4K streams.

**Cloud mode note:** Use `TDARR_MODE=docker` when cloud storage is enabled. Native Tdarr cannot access merged Docker FUSE mounts on macOS.

## Optional: Music (Lidarr + Tidarr)

| Service | What It Does |
|---------|-------------|
| **Lidarr** | Automatic music management (like Sonarr/Radarr but for music albums) |
| **Tidarr** | Downloads FLAC from Tidal (up to 24-bit/192kHz). Web UI + Lidarr integration |

Music services use Docker Compose profiles and are not started by default. To enable:

```bash
bash scripts/setup-music.sh
docker compose --profile music up -d
```

If cloud storage is enabled, use:

```bash
docker compose -f docker-compose.yml -f docker-compose.cloud-storage.yml --profile cloud-storage --profile music up -d
```

Then open Tidarr at `http://localhost:8484` to authenticate with your Tidal account, and Lidarr at `http://localhost:8686` to configure your music library. See the [Music Setup](#music-setup) section below for details.

## Automation

| Script | Schedule | What It Does |
|--------|----------|-------------|
| Auto-healer | Hourly | Restarts VPN/containers if they go down (includes Jellyfin + Jellystat when active) |
| Nightly backup | Daily | Backs up all configs and databases (14-day retention) |
| Download watchdog | Every 15 min | Detects stalled/slow torrents, auto-fixes or swaps them |
| Kometa | Every 4 hours | Updates Plex collections and metadata overlays |
| Log prune | Daily | Removes log files older than 30 days |
| Franchise sort | Optional/manual | Sorts franchise collection movies by release date in Plex (Plex only) |
| VPN failover | Every 2 min (optional) | Auto-switches between ProtonVPN and NordVPN on sustained failure |
| Cloud upload | Every 2-6 hours (optional) | Moves stable local media to remote storage (NAS: 2h, cloud: 6h) |
| Watchtower | Daily at 04:00 (optional) | Auto-pulls latest container images and recreates updated services |

Franchise sorting is kept manual by default because it requires your Plex token:
`PLEX_TOKEN=... python3 scripts/franchise-sort.py`

### Tdarr Mode

- Default is `TDARR_MODE=native` (recommended on macOS).
- Native Tdarr is installed and managed by `scripts/setup-tdarr-native.sh` (launchd server + node).
- Docker Tdarr remains available via `TDARR_MODE=docker` and `--profile tdarr-docker`.
- The stack preloads this Tdarr flow preset: `Quality-First HEVC (Resolution Preserving)`.
  - No resolution downscale
  - No hard bitrate cap
  - H.264 -> H.265 (CRF 19, preset slow)
  - Replace only when output size ratio stays within 25-99%

### Download Watchdog Configuration

The download watchdog reads qBittorrent credentials and behavior settings from environment variables or automatically detects them from your config files. Optional environment variables:

- `QBIT_USERNAME` (default: `admin`)
- `QBIT_PASSWORD` (auto-detected from qBittorrent config if not set)
- `WATCHDOG_STALL_SECONDS` (default: `1800` — how long a torrent must be stalled before auto-swap)
- `WATCHDOG_SLOW_SECONDS` (default: `1200` — how long a torrent must be slow before auto-swap)
- `WATCHDOG_MIN_SPEED_BPS` (default: `307200` — 300 KB/s minimum speed threshold)
- `WATCHDOG_MAX_SWAP_PROGRESS` (default: `0.25` — never swap torrents past 25% complete)

Set these in `.env` or your shell environment if you need to customize watchdog behavior.

## One-Command Install

Requires OrbStack (or Docker Desktop) and either Plex installed or the `--jellyfin` flag. Handles everything else.

```bash
curl -fsSL https://raw.githubusercontent.com/liamvibecodes/mac-media-stack-advanced/main/bootstrap.sh | bash
```

Optional flags when running from a local clone:

```bash
bash bootstrap.sh --media-dir /Volumes/T9/Media --install-dir ~/mac-media-stack-advanced --non-interactive
```

Use Docker-based Tdarr instead of native Tdarr:

```bash
bash bootstrap.sh --tdarr-docker
```

To use Jellyfin instead of Plex:

```bash
bash bootstrap.sh --jellyfin
```

NAS storage via SFTP (TrueNAS, Synology, Unraid):

```bash
bash bootstrap.sh --nas-storage
```

## Update Existing Clone

Already cloned an older version and want the latest release tag without reinstalling?

One-liner (run inside your existing clone directory):

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/liamvibecodes/mac-media-stack-advanced/main/scripts/update-to-latest-release.sh)
```

Local script (once present):

```bash
bash scripts/update-to-latest-release.sh
```

## Upgrading From Basic

Already running `mac-media-stack` and want to keep your existing library/configs?

Use the one-shot upgrader: [UPGRADE.md](UPGRADE.md)

```bash
bash scripts/upgrade-from-basic.sh
```

<details>
<summary>See it in action</summary>
<br>
<img src="demo.gif" alt="Mac Media Stack install demo" width="700" />
</details>

## Manual Quick Start

If you prefer to run each step yourself:

```bash
git clone https://github.com/liamvibecodes/mac-media-stack-advanced.git
cd mac-media-stack-advanced
bash scripts/setup.sh            # or: bash scripts/setup.sh --media-dir /Volumes/T9/Media
# edit .env with VPN keys
bash scripts/doctor.sh           # preflight validation before first boot
docker compose up -d
# if MEDIA_SERVER=jellyfin in .env:
docker compose --profile jellyfin up -d
# if TDARR_MODE=docker in .env:
docker compose --profile tdarr-docker up -d
# if TDARR_MODE=native in .env (default):
bash scripts/setup-tdarr-native.sh
docker compose --profile autoupdate up -d watchtower  # optional auto-updates
bash scripts/configure.sh
bash scripts/install-launchd-jobs.sh
```

The `watchtower` line above enables automatic container image updates (scheduled daily at 04:00 in compose). It's optional but recommended so your services stay patched without manual pulls.

## Full Setup Guide

See [SETUP.md](SETUP.md) for the complete walkthrough.
Upgrading from basic? See [UPGRADE.md](UPGRADE.md).
Pinned digest matrix: [IMAGE_LOCK.md](IMAGE_LOCK.md)

By default, Seerr is bound to `127.0.0.1` for safer local-only access. Set `SEERR_BIND_IP=0.0.0.0` in `.env` only if you intentionally want LAN exposure.

## What It Looks Like

<img src="ui-flow.gif" alt="Request to streaming UI flow" width="700" />

## How It Works

<img src="flow.gif" alt="Request to streaming flow" width="700" />

```
Seerr (request) -> Radarr/Sonarr -> Prowlarr (search) -> qBittorrent (via VPN) -> Plex or Jellyfin (watch)
                                                           |
                                     Unpackerr (extract) --+
                                     Bazarr (subtitles) ----+
                                     Tdarr (transcode) -----+
                                     Kometa (metadata) ------> Plex
                                     Recyclarr (quality) ----> Radarr/Sonarr

Optional music:
                   Lidarr (music management) -> Prowlarr / Tidarr -> Plex (listen)
                   Tidarr (Tidal FLAC downloads) ----^
```

All download traffic routes through ProtonVPN (with optional NordVPN failover). Gluetun's built-in kill switch blocks traffic if the VPN drops, so your real IP is never exposed through the tunnel. Everything else uses your normal connection. All services auto-start on boot and self-heal if they go down.

To manually switch providers after creating `.env.nord` from `.env.nord.example`:

```bash
bash scripts/vpn-mode.sh nord
```

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/setup.sh` | Creates folders, generates .env, copies config templates |
| `scripts/doctor.sh` | Runs preflight checks (runtime, env, compose, ports) |
| `scripts/upgrade-from-basic.sh` | One-shot migration from basic stack to advanced |
| `scripts/configure.sh` | Auto-configures all service connections via API |
| `scripts/health-check.sh` | Full stack health diagnostic |
| `scripts/install-launchd-jobs.sh` | Installs all automation as background jobs |
| `scripts/install-vpn-failover.sh` | Installs VPN failover (requires NordVPN backup) |
| `scripts/auto-heal.sh` | Hourly self-healer |
| `scripts/backup.sh` | Config and database backup |
| `scripts/download-watchdog.py` | Stalled torrent detection and auto-fix |
| `scripts/update-to-latest-release.sh` | Updates an older clone to the latest tagged release safely |
| `scripts/setup-tdarr-native.sh` | Installs/updates native Tdarr and launchd services |
| `scripts/tdarr-apply-quality-flow.sh` | Loads quality-first HEVC flow preset into Tdarr DB |
| `scripts/vpn-mode.sh` | Manual VPN provider switcher |
| `scripts/vpn-failover-watch.sh` | Automatic VPN failover daemon |
| `scripts/run-kometa.sh` | Trigger Kometa metadata run |
| `scripts/setup-cloud-storage.sh` | Sets up rclone + mergerfs cloud storage integration |
| `scripts/cloud-upload.sh` | Periodic upload of local media to cloud storage |
| `scripts/setup-music.sh` | Creates music directories and Tidarr config (optional) |
| `scripts/log-prune.sh` | Prunes old log files (30-day default retention) |
| `scripts/franchise-sort.py` | Auto-sorts franchise collections in Plex by release date (Plex only) |
| `scripts/music-cleanup.py` | Fixes music metadata and folder naming (optional, music profile) |
| `scripts/archive-media.sh` | Move old/watched media to an external archive drive (supports Plex and Jellyfin) |
| `scripts/refresh-image-lock.sh` | Refreshes pinned image digests and regenerates IMAGE_LOCK.md |

## Config Templates

Pre-configured templates in `configs/` (copy to your Media folder after first boot):

- **recyclarr.yml** - TRaSH Guides quality profiles for Radarr and Sonarr
- **kometa.yml** - Plex metadata automation (franchise collections, resolution overlays)
- **tdarr-flow-quality-first-hevc.json** - Quality-first H.264 -> H.265 flow preset loaded by `scripts/tdarr-apply-quality-flow.sh`

Recyclarr API keys are auto-injected by `scripts/configure.sh`. Kometa still needs your manual Plex token + TMDB API key.

## Music Setup

Music is optional and uses Docker Compose [profiles](https://docs.docker.com/compose/profiles/). The core stack works without it.

### What You Get

- **Lidarr** manages your music library the same way Radarr handles movies. It monitors artists, searches for albums via Prowlarr, and imports downloads into your Plex music folder.
- **Tidarr** downloads FLAC directly from Tidal (up to 24-bit/192kHz Hi-Res). It has a web UI for manual downloads and also acts as an indexer + download client for Lidarr, so Lidarr can search and download from Tidal automatically.

### Quick Start

```bash
# 1. Create music directories and config
bash scripts/setup-music.sh

# 2. Start the music services
docker compose --profile music up -d

# 3. Authenticate with Tidal
#    Open http://localhost:8484 and follow the OAuth device flow

# 4. Configure Lidarr
#    Open http://localhost:8686
#    - Settings > Media Management > Add root folder: /music
#    - Settings > Download Clients > Add SABnzbd:
#        Host: tidarr, Port: 8484, URL Base: /api/sabnzbd
#    - Settings > Indexers > Add Newznab:
#        URL: http://tidarr:8484, API Path: /api/lidarr
#        Categories: 3000, 3010, 3040
#    - Settings > Download Clients > Add qBittorrent (for torrent fallback):
#        Host: gluetun, Port: 8080
```

If cloud storage is enabled, use this start command in step 2 instead:

```bash
docker compose -f docker-compose.yml -f docker-compose.cloud-storage.yml --profile cloud-storage --profile music up -d
```

### Tidarr Download Config

The setup script creates a default `tiddl` config at `<MEDIA_DIR>/config/tidarr/.tiddl/config.toml` (default `<MEDIA_DIR>` is `~/Media`). Key settings:

- **Quality:** `max` (24-bit Hi-Res FLAC when available, falls back to 16-bit/44.1kHz)
- **Download path:** Your Plex music folder (files go directly to the library)
- **Skip existing:** Won't re-download albums you already have
- **File template:** `Artist/Album/01 Track Title.flac` (Plex-compatible naming)

### Day-to-Day

| What | Where |
|------|-------|
| Search and download from Tidal manually | http://localhost:8484 |
| Manage music library (add artists, monitor) | http://localhost:8686 |
| Listen via Plex/Plexamp | http://localhost:32400/web |

### Music Library Cleanup

If your music files have inconsistent metadata (different featuring formats, year suffixes in folder names, missing album artist tags), the cleanup script fixes common issues:

```bash
# Preview what would change (dry run, nothing is modified)
python3 scripts/music-cleanup.py

# Apply fixes
python3 scripts/music-cleanup.py --apply

# Custom music directory
python3 scripts/music-cleanup.py --path /Volumes/External/Music
```

Requires `mutagen`: `pip install mutagen`

### Starting/Stopping Music Services

```bash
# Start music services
docker compose --profile music up -d

# Stop only music services (keeps everything else running)
docker compose --profile music stop lidarr tidarr

# Include music in all future docker compose commands
# Add to your shell profile:
export COMPOSE_PROFILES=music
```

If cloud storage is enabled, include both compose files and profiles when starting music services:

```bash
docker compose -f docker-compose.yml -f docker-compose.cloud-storage.yml --profile cloud-storage --profile music up -d
```

## Media Archiving

If you're running out of space on your primary drive, the archive script moves old or watched media to an external drive. Dry-run by default so you can preview what would be moved before committing.

```bash
# Preview candidates (nothing gets moved)
bash scripts/archive-media.sh --archive /Volumes/External/Media-Archive

# Archive movies older than 6 months that are 8GB+
bash scripts/archive-media.sh --execute --archive /Volumes/External/Media-Archive --type movies

# Only archive stuff you've already watched (uses Plex watch state)
bash scripts/archive-media.sh --execute --archive /Volumes/External/Media-Archive --only-watched

# Jellyfin users: pass your API key for watched-state filtering
bash scripts/archive-media.sh --execute --archive /Volumes/External/Media-Archive --only-watched --jellyfin-api-key YOUR_KEY
```

**Protecting favorites:** `scripts/setup.sh` creates `<MEDIA_DIR>/config/archive-exceptions.txt` for you (default `<MEDIA_DIR>` is `~/Media`). Add one title per line and anything listed won't be archived regardless of age or size. See `configs/archive-exceptions.txt.example` for the format.

The script verifies file counts after copying and only deletes the source if the counts match. If verification fails, your original files are untouched.

## Companion Tools

| Tool | What It Does |
|------|-------------|
| [mac-media-stack-permissions](https://github.com/liamvibecodes/mac-media-stack-permissions) | Audit and fix file permissions across your stack |
| [mac-media-stack-backup](https://github.com/liamvibecodes/mac-media-stack-backup) | Automated backup and restore for configs and databases |

## Author

Built by [@liamvibecodes](https://github.com/liamvibecodes)

## License

[MIT](LICENSE)
