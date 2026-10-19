#!/usr/bin/env python3
"""Import universe/ from a trusted ZIP, preserving service configuration and rollback."""
import argparse
import datetime
import json
import os
from pathlib import Path, PurePosixPath
import shutil
import stat
import subprocess
import tempfile
import zipfile


def extract_world(source, destination):
    """Reject traversal/symlinks/duplicates and cap extraction to 20 GiB."""
    with zipfile.ZipFile(source) as archive:
        seen, total = set(), 0
        for entry in archive.infolist():
            path = PurePosixPath(entry.filename)
            if path.is_absolute() or '..' in path.parts or '\\' in entry.filename or ':' in entry.filename:
                raise ValueError('Unsafe archive path')
            if stat.S_ISLNK(entry.external_attr >> 16):
                raise ValueError('Archive symlinks are unsupported')
            if not entry.filename.startswith('universe/'):
                continue
            if str(path) in seen:
                raise ValueError('Duplicate archive path')
            seen.add(str(path))
            total += entry.file_size
            if total > 20 * 1024**3:
                raise ValueError('World exceeds 20 GiB extraction limit')
            archive.extract(entry, destination)
    world = destination / 'universe/worlds/default/config.json'
    json.loads(world.read_text())
    if not list((world.parent / 'chunks').glob('*.region.bin')):
        raise ValueError('No default-world region files found; empty or different layouts need manual import')


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('--replace', action='store_true', help='Confirm replacement; old world is retained')
    args = parser.parse_args()
    if os.geteuid() != 0 or not args.replace:
        parser.error('Run as root with --replace after reading the README')
    root = Path('/srv/hytale/game/Server')
    stamp = datetime.datetime.now(datetime.timezone.utc).strftime('%Y%m%dT%H%M%SZ')
    backup = Path(tempfile.mkdtemp(prefix=f'before-import-{stamp}-', dir='/srv/hytale/backups'))
    stage = Path(tempfile.mkdtemp(prefix='import-', dir='/srv/hytale'))
    extract_world(args.archive, stage)  # Complete validation before any downtime.
    subprocess.run(['chown', '-R', 'hytale:hytale', str(stage / 'universe')], check=True)
    subprocess.run(['systemctl', 'stop', 'hytale'], check=True)
    try:
        if (root / 'universe').exists():
            (root / 'universe').rename(backup / 'universe')
        try:
            (stage / 'universe').rename(root / 'universe')
        except Exception:
            if (backup / 'universe').exists():
                (backup / 'universe').rename(root / 'universe')
            raise
    finally:
        subprocess.run(['systemctl', 'start', 'hytale'], check=True)
    print(f'Previous universe retained at {backup}; inspect service logs before joining.')
    print('World-specific mod state was NOT imported; review and migrate it separately if needed.')


if __name__ == '__main__':
    main()
