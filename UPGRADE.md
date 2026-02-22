# Upgrade Guide: Basic -> Advanced

This guide upgrades an existing `mac-media-stack` install to `mac-media-stack-advanced` without moving your media library.

## Recommended: One-shot upgrader

Use the built-in migration script:

```bash
cd ~/mac-media-stack-advanced
bash scripts/upgrade-from-basic.sh
```

### Common flags

```bash
# Non-default basic repo location
bash scripts/upgrade-from-basic.sh --basic-dir /path/to/mac-media-stack

# Override MEDIA_DIR (if different from basic .env)
bash scripts/upgrade-from-basic.sh --media-dir /Volumes/T9/Media

# Fully non-interactive run (skips Seerr sign-in prompt in configure.sh)
bash scripts/upgrade-from-basic.sh --yes --non-interactive

# Skip backup snapshot (not recommended)
bash scripts/upgrade-from-basic.sh --yes --skip-backup

# Start watchtower profile after upgrade
bash scripts/upgrade-from-basic.sh --enable-watchtower
```

What the upgrader does:

1. Validates basic + advanced repo paths
2. Creates a backup snapshot (env + config/state/logs)
3. Migrates shared env keys from basic to advanced
4. Stops basic stack
5. Runs advanced setup + preflight doctor checks
6. Starts advanced stack
7. Runs auto-configuration
8. Installs launchd automation jobs
9. Runs health checks

## Manual upgrade (step-by-step)

If you prefer full manual control:

1. Backup:
```bash
MEDIA_DIR=~/Media
mkdir -p ~/media-stack-upgrade-backup
cp -a "$MEDIA_DIR/config" ~/media-stack-upgrade-backup/config
cp -a "$MEDIA_DIR/state" ~/media-stack-upgrade-backup/state 2>/dev/null || true
cp -a "$MEDIA_DIR/logs" ~/media-stack-upgrade-backup/logs 2>/dev/null || true
```
2. Stop basic:
```bash
cd ~/mac-media-stack
docker compose down
```
3. Prepare advanced:
```bash
cd ~/mac-media-stack-advanced
bash scripts/setup.sh
bash scripts/doctor.sh
```
4. Start and configure:
```bash
docker compose up -d
# If using Jellyfin:
docker compose --profile jellyfin up -d
bash scripts/configure.sh
bash scripts/install-launchd-jobs.sh
```
5. Validate:
```bash
bash scripts/health-check.sh
```

## Advanced-only follow-up

After either upgrade path, confirm:

1. `~/Media/config/kometa/config.yml` has `PLEX_TOKEN` + TMDB key
2. Tdarr libraries/plugins are configured at `http://localhost:8265`
3. `bash scripts/health-check.sh` reports clean results

## Rollback

Quick rollback:

```bash
cd ~/mac-media-stack-advanced
docker compose down

cd ~/mac-media-stack
docker compose up -d
# If your basic stack uses Jellyfin:
docker compose --profile jellyfin up -d
```

If you used the one-shot script, backup snapshots are saved under:

`~/media-stack-upgrade-backup/YYYYMMDD-HHMMSS/`
