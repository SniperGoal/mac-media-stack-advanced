# Upgrade Guide: Basic -> Advanced

This guide upgrades an existing `mac-media-stack` install to `mac-media-stack-advanced` without losing your media library or app config.

## Before You Start

- Stop any active downloads first (recommended).
- Keep your existing `MEDIA_DIR` path exactly the same.
- Do not run basic and advanced at the same time.

## What Carries Over

If you reuse the same `MEDIA_DIR`, advanced will reuse your existing:

- Movies/TV library files
- Radarr/Sonarr/Prowlarr/qBittorrent/Bazarr/Seerr configs
- API keys and existing app state inside `${MEDIA_DIR}/config`

## 1. Backup (Required)

```bash
# adjust if your media path is not ~/Media
MEDIA_DIR=~/Media

# backup media stack config/state quickly
mkdir -p ~/media-stack-upgrade-backup
cp -a "$MEDIA_DIR/config" ~/media-stack-upgrade-backup/config
cp -a "$MEDIA_DIR/state" ~/media-stack-upgrade-backup/state 2>/dev/null || true
cp -a "$MEDIA_DIR/logs" ~/media-stack-upgrade-backup/logs 2>/dev/null || true
```

If you already use the advanced backup repo/tooling, run that instead.

## 2. Stop Basic Stack

```bash
cd ~/mac-media-stack
docker compose down
```

## 3. Clone Advanced

```bash
cd ~
git clone https://github.com/liamvibecodes/mac-media-stack-advanced.git
cd mac-media-stack-advanced
```

## 4. Configure `.env` for Existing Media Path

Generate a starter `.env` if needed:

```bash
bash scripts/setup.sh
```

Open `.env` and confirm:

- `MEDIA_DIR` points to your existing library path from basic
- your VPN keys are set (`WIREGUARD_PRIVATE_KEY`, `WIREGUARD_ADDRESSES`)

```bash
open -a TextEdit .env
```

## 5. Run Preflight + Start Advanced

```bash
bash scripts/doctor.sh
docker compose up -d
```

## 6. Run Auto-Configuration

```bash
bash scripts/configure.sh
```

This auto-wires:

- qBittorrent, Radarr, Sonarr, Prowlarr, Seerr
- Recyclarr API keys
- Unpackerr API keys (+ Unpackerr restart)

## 7. Complete Advanced-Only Manual Setup

Still manual by design:

- Kometa: add `PLEX_TOKEN` + TMDB API key in `${MEDIA_DIR}/config/kometa/config.yml`
- Tdarr: configure libraries/plugins in Web UI (`http://localhost:8265`)

## 8. Install Automation Jobs

```bash
bash scripts/install-launchd-jobs.sh
```

This installs auto-heal, backup, watchdog, Kometa runner, and log-prune.

## 9. Validate

```bash
bash scripts/health-check.sh
```

Confirm:

- core services show `OK`
- VPN shows healthy
- Plex can still see your existing libraries

## Optional: Enable Watchtower

```bash
docker compose --profile autoupdate up -d watchtower
```

## Rollback (If Needed)

```bash
# stop advanced
cd ~/mac-media-stack-advanced
docker compose down

# bring basic back
cd ~/mac-media-stack
docker compose up -d
```

Because both stacks use the same `MEDIA_DIR`, rollback is quick.
