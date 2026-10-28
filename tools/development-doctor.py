#!/usr/bin/env python3
"""Read-only, fast local-data checks before starting Flutter in VS Code."""
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]


def inspect(root):
    problems = []
    core = root / 'android/app/src/main/assets/nav_kurd_core'
    catalog = core / 'catalog.sqlite'
    try:
        with catalog.open('rb') as stream:
            complete = stream.read(16) == b'SQLite format 3\0'
    except OSError:
        complete = False
    if not complete:
        problems.append('Offline catalog is missing or is a Git LFS pointer. Run: git lfs install; git lfs pull')
    for folder in (core, root / 'assets/r16'):
        try:
            manifest = json.loads((folder / 'manifest.json').read_text())
            for row in manifest['files']:
                name = row['path']
                if not isinstance(name, str) or not name or '\\' in name or name.startswith('/') or any(part in {'', '.', '..'} for part in name.split('/')):
                    raise ValueError('unsafe path')
                path = folder / name
                if path.is_symlink() or not path.is_file() or path.stat().st_size != row['bytes']:
                    problems.append('Missing or incomplete asset: ' + str(path.relative_to(root)))
        except (OSError, ValueError, KeyError, TypeError):
            problems.append('Missing or invalid asset manifest: ' + str(folder.relative_to(root)))
    for name in ('pubspec.lock', 'packages/flutter_inappwebview_android/pubspec.yaml'):
        if not (root / name).is_file():
            problems.append('Required source file is missing: ' + name)
    return problems


if __name__ == '__main__':
    problems = inspect(ROOT)
    if problems:
        print('\n'.join(problems[:12]))
        print('No files were changed. Restore the repository data before launching Flutter.')
        raise SystemExit(1)
    print('PASS: local catalog, presentation file sizes and locked source files are present.')
    print('Use the Flutter version pinned in README.md and select an Android device in VS Code.')
    print('Full release integrity check: python3 tools/verify-local-data.py')
