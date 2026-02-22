#!/usr/bin/env python3
"""
Franchise Sort — auto-sets sort titles for movies in Plex collections.

For each collection, orders movies by release date and sets sort titles
like "Collection Name 01", "Collection Name 02", etc. This makes franchise
movies appear grouped and in chronological order in the main library view.

Runs after Kometa (which creates the collections) via launchd or manually.

Usage:
  python3 franchise-sort.py                                    # uses env vars
  PLEX_URL=http://localhost:32400 PLEX_TOKEN=xxx python3 franchise-sort.py
  python3 franchise-sort.py --url http://localhost:32400 --token xxx
  python3 franchise-sort.py --path ~/Media/logs               # custom log dir
  python3 franchise-sort.py --section 2                        # TV library
  python3 franchise-sort.py --dry-run                          # preview only
"""

import urllib.request
import urllib.parse
import xml.etree.ElementTree as ET
import logging
import os
import sys
from pathlib import Path

def load_default_media_log_dir() -> str:
    env_media = os.getenv("MEDIA_DIR")
    if env_media:
        return os.path.expanduser(os.path.join(env_media, "logs"))

    env_path = Path(__file__).resolve().parents[1] / ".env"
    if env_path.exists():
        for line in env_path.read_text(errors="ignore").splitlines():
            if line.startswith("MEDIA_DIR="):
                value = line.split("=", 1)[1].strip().strip('"').strip("'")
                if value:
                    return os.path.expanduser(os.path.join(value, "logs"))

    return os.path.expanduser("~/Media/logs")


PLEX_URL = os.environ.get("PLEX_URL", "http://localhost:32400")
PLEX_TOKEN = os.environ.get("PLEX_TOKEN", "")
SECTION_ID = os.environ.get("PLEX_SECTION_ID", "1")
LOG_DIR = os.environ.get("MEDIA_LOG_DIR", load_default_media_log_dir())
DRY_RUN = False


def parse_args():
    global PLEX_URL, PLEX_TOKEN, SECTION_ID, LOG_DIR, DRY_RUN
    args = sys.argv[1:]
    i = 0
    def require_arg(flag: str) -> str:
        nonlocal i
        if i + 1 >= len(args) or args[i + 1].startswith("--"):
            print(f"Missing value for {flag}")
            sys.exit(1)
        return args[i + 1]
    while i < len(args):
        if args[i] == "--url":
            PLEX_URL = require_arg("--url")
            i += 2
        elif args[i] == "--token":
            PLEX_TOKEN = require_arg("--token")
            i += 2
        elif args[i] == "--section":
            SECTION_ID = require_arg("--section")
            i += 2
        elif args[i] in ("--log-dir", "--path"):
            LOG_DIR = require_arg(args[i])
            i += 2
        elif args[i] == "--dry-run":
            DRY_RUN = True
            i += 1
        elif args[i] in ("-h", "--help"):
            print(__doc__.strip())
            sys.exit(0)
        else:
            print(f"Unknown option: {args[i]}")
            sys.exit(1)


parse_args()

if not PLEX_TOKEN:
    print("ERROR: PLEX_TOKEN not set. Pass --token or set the PLEX_TOKEN env var.")
    print("Find your token: https://support.plex.tv/articles/204059436/")
    sys.exit(1)

os.makedirs(LOG_DIR, exist_ok=True)

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s %(message)s",
    handlers=[
        logging.FileHandler(f"{LOG_DIR}/franchise-sort.log"),
        logging.StreamHandler(),
    ],
)
log = logging.getLogger("franchise-sort")


def plex_get(path):
    url = f"{PLEX_URL}{path}?X-Plex-Token={PLEX_TOKEN}"
    resp = urllib.request.urlopen(url)
    return ET.parse(resp).getroot()


def plex_put(path, params):
    params["X-Plex-Token"] = PLEX_TOKEN
    url = f"{PLEX_URL}{path}?{urllib.parse.urlencode(params)}"
    req = urllib.request.Request(url, method="PUT")
    return urllib.request.urlopen(req)


def get_collections():
    root = plex_get(f"/library/sections/{SECTION_ID}/collections")
    collections = []
    for d in root.findall(".//Directory"):
        title = d.get("title", "")
        rating_key = d.get("ratingKey", "")
        child_count = int(d.get("childCount", "0"))
        if child_count >= 2:
            collections.append((rating_key, title, child_count))
    return collections


def get_collection_movies(collection_key):
    root = plex_get(f"/library/collections/{collection_key}/children")
    movies = []
    for v in root.findall(".//Video"):
        rating_key = v.get("ratingKey", "")
        title = v.get("title", "")
        year = v.get("year", "9999")
        orig_date = v.get("originallyAvailableAt", f"{year}-01-01")
        sort_title = v.get("titleSort", "")
        movies.append({
            "key": rating_key,
            "title": title,
            "date": orig_date,
            "current_sort": sort_title,
        })
    movies.sort(key=lambda m: m["date"])
    return movies


def set_sort_title(rating_key, sort_title):
    plex_put(f"/library/sections/{SECTION_ID}/all", {
        "type": 1,
        "id": rating_key,
        "titleSort.value": sort_title,
        "titleSort.locked": 1,
    })


def main():
    mode = "DRY RUN" if DRY_RUN else "LIVE"
    log.info(f"Starting franchise sort ({mode}) section={SECTION_ID}")
    collections = get_collections()
    log.info(f"Found {len(collections)} collections with 2+ items")

    updated = 0
    for coll_key, coll_title, count in collections:
        movies = get_collection_movies(coll_key)
        log.info(f"Collection: {coll_title} ({len(movies)} items)")

        for i, movie in enumerate(movies, 1):
            new_sort = f"{coll_title} {i:02d}"
            if movie["current_sort"] != new_sort:
                if not DRY_RUN:
                    set_sort_title(movie["key"], new_sort)
                log.info(f"  {movie['title']} -> {new_sort}")
                updated += 1
            else:
                log.info(f"  {movie['title']} already correct")

    log.info(f"Done. {'Would update' if DRY_RUN else 'Updated'} {updated} sort titles.")


if __name__ == "__main__":
    main()
