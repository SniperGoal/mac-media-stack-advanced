#!/usr/bin/env python3
"""
Music library cleanup — fixes common naming and metadata issues.

Fixes:
  - Featuring format: Ft/Ft./FT → feat. (Apple Music/Plex standard)
  - "and" → "&" inside featuring credits
  - Double-dash filenames: "01 - - Song.mp3" → "01 Song.mp3"
  - Artist prefix in title: "Artist - Song" → "Song"
  - Year in folder names: "Album (2024)" → "Album"
  - Missing album_artist tag (derived from folder structure)
  - Extra whitespace in tags

Supports: MP3, M4A, FLAC

Requires: pip install mutagen

Usage:
  python3 music-cleanup.py                          # dry run (default)
  python3 music-cleanup.py --apply                  # apply changes
  python3 music-cleanup.py --path /path/to/Music    # custom music dir
"""

import os
import re
import sys
from pathlib import Path

try:
    from mutagen.mp3 import MP3
    from mutagen.mp4 import MP4
    from mutagen.flac import FLAC
    from mutagen.id3 import TIT2, TPE1, TPE2, TALB
except ImportError:
    print("ERROR: mutagen not installed. Run: pip install mutagen")
    sys.exit(1)

def load_default_music_root() -> str:
    env_music = os.environ.get("MUSIC_DIR")
    if env_music:
        return os.path.expanduser(env_music)

    env_media = os.environ.get("MEDIA_DIR")
    if env_media:
        return os.path.expanduser(os.path.join(env_media, "Music"))

    env_path = Path(__file__).resolve().parents[1] / ".env"
    if env_path.exists():
        for line in env_path.read_text(errors="ignore").splitlines():
            if line.startswith("MEDIA_DIR="):
                value = line.split("=", 1)[1].strip().strip('"').strip("'")
                if value:
                    return os.path.expanduser(os.path.join(value, "Music"))

    return os.path.expanduser("~/Media/Music")


MUSIC_ROOT = load_default_music_root()
DRY_RUN = True
stats = {"meta": 0, "file_renames": 0, "dir_renames": 0, "errors": 0}


def parse_args():
    global MUSIC_ROOT, DRY_RUN
    args = sys.argv[1:]
    i = 0
    def require_arg(flag: str) -> str:
        nonlocal i
        if i + 1 >= len(args) or args[i + 1].startswith("--"):
            print(f"Missing value for {flag}")
            sys.exit(1)
        return args[i + 1]
    while i < len(args):
        if args[i] == "--apply":
            DRY_RUN = False
            i += 1
        elif args[i] == "--path":
            MUSIC_ROOT = require_arg("--path")
            i += 2
        elif args[i] in ("-h", "--help"):
            print(__doc__.strip())
            sys.exit(0)
        else:
            print(f"Unknown option: {args[i]}")
            sys.exit(1)


def fix_featuring_text(text):
    """Standardize all featuring variants to 'feat.' format."""
    if not text:
        return text
    text = re.sub(r'\(Ft\.?\s+', '(feat. ', text)
    text = re.sub(r'\(ft\.?\s+', '(feat. ', text)

    def fix_and_in_feat(m):
        inner = m.group(0)
        inner = re.sub(r'\band\b', '&', inner)
        return inner
    text = re.sub(r'\(feat\.[^)]+\)', fix_and_in_feat, text, flags=re.IGNORECASE)
    text = re.sub(r'\(Feat\.\s', '(feat. ', text)
    text = re.sub(r'\(FEAT\.\s', '(feat. ', text)
    return text


def fix_double_dash_filename(filename):
    """Fix '01 - - Song.mp3' patterns."""
    m = re.match(r'^(\d+)\s*-\s*-\s*(.+)$', filename)
    if m:
        return f"{m.group(1)} {m.group(2).strip()}"
    return filename


def strip_artist_from_title(title, artist):
    """Remove 'Artist - ' prefix from title if present."""
    if not title or not artist:
        return title
    for sep in (" - ", " \u2013 "):
        prefix = f"{artist}{sep}"
        if title.startswith(prefix):
            return title[len(prefix):]
    return title


def strip_year_from_folder(name):
    """Remove (YYYY) suffix and YYYY - prefix from folder names."""
    cleaned = re.sub(r'\s*\(\d{4}\)$', '', name)
    cleaned = re.sub(r'^\d{4}\s*-\s*', '', cleaned)
    return cleaned


def clean_all(text):
    """Apply all text fixes."""
    if not text:
        return text
    text = fix_featuring_text(text)
    text = re.sub(r'  +', ' ', text)
    return text.strip()


# --- Metadata ---

def read_meta(fp):
    ext = fp.suffix.lower()
    try:
        if ext == '.mp3':
            audio = MP3(fp)
            tags = audio.tags
            if not tags:
                return {}
            return {
                'title': str(tags.get('TIT2', '')).strip() or None,
                'artist': str(tags.get('TPE1', '')).strip() or None,
                'album_artist': str(tags.get('TPE2', '')).strip() or None,
                'album': str(tags.get('TALB', '')).strip() or None,
            }
        elif ext in ('.m4a', '.m4p'):
            audio = MP4(fp)
            tags = audio.tags or {}
            return {
                'title': (tags.get('\xa9nam', [None])[0]),
                'artist': (tags.get('\xa9ART', [None])[0]),
                'album_artist': (tags.get('aART', [None])[0]),
                'album': (tags.get('\xa9alb', [None])[0]),
            }
        elif ext == '.flac':
            audio = FLAC(fp)
            return {
                'title': (audio.get('title', [None])[0]),
                'artist': (audio.get('artist', [None])[0]),
                'album_artist': (audio.get('albumartist', [None])[0]),
                'album': (audio.get('album', [None])[0]),
            }
    except Exception:
        return {}
    return {}


def write_meta(fp, changes):
    ext = fp.suffix.lower()
    try:
        if ext == '.mp3':
            audio = MP3(fp)
            if audio.tags is None:
                audio.add_tags()
            if 'title' in changes:
                audio.tags['TIT2'] = TIT2(encoding=3, text=[changes['title']])
            if 'artist' in changes:
                audio.tags['TPE1'] = TPE1(encoding=3, text=[changes['artist']])
            if 'album_artist' in changes:
                audio.tags['TPE2'] = TPE2(encoding=3, text=[changes['album_artist']])
            if 'album' in changes:
                audio.tags['TALB'] = TALB(encoding=3, text=[changes['album']])
            audio.save()
        elif ext in ('.m4a', '.m4p'):
            audio = MP4(fp)
            if audio.tags is None:
                audio.tags = {}
            if 'title' in changes:
                audio.tags['\xa9nam'] = [changes['title']]
            if 'artist' in changes:
                audio.tags['\xa9ART'] = [changes['artist']]
            if 'album_artist' in changes:
                audio.tags['aART'] = [changes['album_artist']]
            if 'album' in changes:
                audio.tags['\xa9alb'] = [changes['album']]
            audio.save()
        elif ext == '.flac':
            audio = FLAC(fp)
            if 'title' in changes:
                audio['title'] = changes['title']
            if 'artist' in changes:
                audio['artist'] = changes['artist']
            if 'album_artist' in changes:
                audio['albumartist'] = changes['album_artist']
            if 'album' in changes:
                audio['album'] = changes['album']
            audio.save()
        return True
    except Exception as e:
        print(f"  ERROR writing {fp}: {e}", flush=True)
        stats["errors"] += 1
        return False


def derive_album_artist(fp):
    parts = Path(fp).relative_to(MUSIC_ROOT).parts
    return parts[0] if len(parts) >= 2 else None


# --- Main ---

def main():
    parse_args()

    if not os.path.isdir(MUSIC_ROOT):
        print(f"ERROR: Music directory not found: {MUSIC_ROOT}")
        print("Set MUSIC_DIR env var or use --path /path/to/Music")
        sys.exit(1)

    mode = "DRY RUN" if DRY_RUN else "APPLYING"
    print(f"Music Cleanup - {mode}", flush=True)
    print(f"Library: {MUSIC_ROOT}", flush=True)
    print(f"{'=' * 70}", flush=True)

    meta_changes = []
    file_renames = []

    for root, dirs, files in os.walk(MUSIC_ROOT):
        dirs[:] = [d for d in dirs if not d.startswith('.')]
        for f in files:
            if not f.lower().endswith(('.mp3', '.m4a', '.m4p', '.flac', '.ogg')):
                continue
            fp = Path(root) / f
            meta = read_meta(fp)
            changes = {}

            # Fix title
            if meta.get('title'):
                new_title = clean_all(meta['title'])
                new_title = strip_artist_from_title(new_title, meta.get('artist', ''))
                if new_title != meta['title']:
                    changes['title'] = new_title

            # Fix artist featuring format
            if meta.get('artist'):
                new_artist = fix_featuring_text(meta['artist'])
                if new_artist != meta['artist']:
                    changes['artist'] = new_artist

            # Fix album
            if meta.get('album'):
                new_album = clean_all(meta['album'])
                new_album = re.sub(r'\s*\(\d{4}\)$', '', new_album)
                new_album = re.sub(r'^\d{4}\s*-\s*', '', new_album)
                if new_album != meta['album']:
                    changes['album'] = new_album

            # Populate album_artist if missing
            if not meta.get('album_artist'):
                derived = derive_album_artist(fp)
                if derived:
                    changes['album_artist'] = derived

            if changes:
                meta_changes.append((fp, changes))
                tag_summary = ", ".join(f"{k}: '{v[:60]}'" for k, v in changes.items())
                print(f"  META  {fp.relative_to(MUSIC_ROOT)}", flush=True)
                print(f"        {tag_summary}", flush=True)

            # File rename
            stem = fp.stem
            ext = fp.suffix
            new_stem = fix_double_dash_filename(stem)
            new_stem = clean_all(new_stem)
            new_stem = re.sub(r'^(\d+)\s*-\s*-', r'\1', new_stem)
            if new_stem != stem:
                new_path = fp.parent / (new_stem + ext)
                if not new_path.exists():
                    file_renames.append((fp, new_path))
                    print(f"  FILE  {fp.name}  ->  {new_path.name}", flush=True)

    # Directory renames (bottom-up)
    dir_renames = []
    for root, dirs, files in os.walk(MUSIC_ROOT, topdown=False):
        for d in dirs:
            if d.startswith('.'):
                continue
            cleaned = strip_year_from_folder(d)
            cleaned = clean_all(cleaned)
            if cleaned != d:
                old_path = os.path.join(root, d)
                new_path = os.path.join(root, cleaned)
                if not os.path.exists(new_path):
                    dir_renames.append((old_path, new_path))
                    print(f"  DIR   {os.path.relpath(old_path, MUSIC_ROOT)}  ->  {os.path.basename(new_path)}", flush=True)
                elif old_path != new_path:
                    print(f"  SKIP  {os.path.relpath(old_path, MUSIC_ROOT)}  ->  {os.path.basename(new_path)} (already exists)", flush=True)

    print(f"\n{'=' * 70}", flush=True)
    print(f"Metadata: {len(meta_changes)}, File renames: {len(file_renames)}, Dir renames: {len(dir_renames)}", flush=True)

    if DRY_RUN:
        print("Dry run. Use --apply to execute.", flush=True)
        return

    for fp, changes in meta_changes:
        if write_meta(fp, changes):
            stats["meta"] += 1

    for old, new in file_renames:
        try:
            old.rename(new)
            stats["file_renames"] += 1
        except Exception as e:
            print(f"  ERROR {old.name}: {e}", flush=True)
            stats["errors"] += 1

    for old, new in dir_renames:
        try:
            os.rename(old, new)
            stats["dir_renames"] += 1
        except Exception as e:
            print(f"  ERROR {old}: {e}", flush=True)
            stats["errors"] += 1

    print(f"\nDone: {stats['meta']} meta, {stats['file_renames']} files, {stats['dir_renames']} dirs, {stats['errors']} errors", flush=True)


if __name__ == "__main__":
    main()
