#!/usr/bin/env python3
"""Check closed offline data and bundled UI before building a release."""
import argparse
import hashlib
import json
import sqlite3
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
# This UI-only patch retains the verified V10 offline database unchanged.
DATA_VERSION = '10.0.0'
APP_VERSION = '10.4.4'


def verify_pack(folder, update_identity=False):
    manifest = json.loads((folder / 'manifest.json').read_text())
    declared = {'manifest.json'}
    for row in manifest['files']:
        name = row['path']
        if not name or name.startswith('/') or '\\' in name or any(p in {'', '.', '..'} for p in name.split('/')) or name in declared:
            raise SystemExit('Unsafe or duplicate local asset')
        declared.add(name)
        path = folder / name
        if path.is_symlink() or not path.is_file() or path.stat().st_size != row['bytes']:
            raise SystemExit('Missing or incomplete local asset: ' + name)
        with path.open('rb') as stream:
            if hashlib.file_digest(stream, 'sha256').hexdigest() != row['sha256']:
                raise SystemExit('Local asset digest mismatch: ' + name)
    actual = {p.relative_to(folder).as_posix() for p in folder.rglob('*') if p.is_file()}
    if actual != declared:
        raise SystemExit('Unmanifested local assets: ' + str(sorted(actual ^ declared)))
    # Dart and Kotlin sort complete paths, not Path.rglob directory traversal.
    rows = sorted(manifest['files'], key=lambda row: row['path'].encode('utf-16-be'))
    signature = ''.join(f'{row["path"]}\0{row["bytes"]}\0{row["sha256"]}\n' for row in rows)
    content_hash = hashlib.sha256(signature.encode('utf-8')).hexdigest()
    pack_id = None
    if 'packId' in manifest:
        pack_id = f'{manifest["versions"]["offlinePackVersion"]}-{content_hash[:16]}'
    if update_identity:
        manifest['files'] = rows
        manifest['contentHash'] = content_hash
        if pack_id is not None:
            manifest['packId'] = pack_id
        (folder / 'manifest.json').write_text(json.dumps(manifest, separators=(',', ':')) + '\n')
    elif (manifest.get('contentHash') != content_hash
          or pack_id is not None and manifest['packId'] != pack_id):
        raise SystemExit('Pack content identity does not match its canonical file inventory: ' + str(folder))
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--update-identities', action='store_true',
                        help='recalculate pack identity only after every declared file verifies')
    args = parser.parse_args()
    core = ROOT / 'android/app/src/main/assets/nav_kurd_core'
    pack = verify_pack(core, args.update_identities)
    ui = verify_pack(ROOT / 'assets/r16', args.update_identities)
    if pack['versions']['appVersion'] != DATA_VERSION or ui['appVersion'] != APP_VERSION:
        raise SystemExit('Local data / presentation version mismatch')
    with sqlite3.connect((core / 'catalog.sqlite').as_uri() + '?mode=ro&immutable=1', uri=True) as db:
        if db.execute('PRAGMA integrity_check').fetchall() != [('ok',)] or db.execute('PRAGMA foreign_key_check').fetchall():
            raise SystemExit('Offline SQLite integrity failure')
        for table, key in [('feature', 'features'), ('search_row', 'searchRows'), ('lexeme', 'lexemes')]:
            if db.execute('SELECT COUNT(*) FROM ' + table).fetchone()[0] != pack['records'][key]:
                raise SystemExit('Offline record count mismatch: ' + table)
        version = db.execute("SELECT value FROM metadata WHERE key='appVersion'").fetchone()
        if version is None or json.loads(version[0]) != DATA_VERSION:
            raise SystemExit('Offline database version mismatch')
    print('PASS local assets: canonical pack identities, complete manifests, SQLite integrity, language index and current presentation')


if __name__ == '__main__':
    main()
