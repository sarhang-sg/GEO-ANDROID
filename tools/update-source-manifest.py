#!/usr/bin/env python3
"""Regenerate the complete deterministic Android source manifest."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "SOURCE_MANIFEST.sha256"
EXCLUDED_DIRECTORIES = {
    ".dart_tool",
    ".git",
    ".gradle",
    ".idea",
    ".plugin_symlinks",
    ".vscode",
    "__pycache__",
    "build",
    "coverage",
    "node_modules",
}
EXCLUDED_NAMES = {
    ".flutter-plugins",
    ".flutter-plugins-dependencies",
    ".packages",
    ".DS_Store",
    "Thumbs.db",
    MANIFEST.name,
}
EXCLUDED_SUFFIXES = {
    ".aab",
    ".apk",
    ".bak",
    ".jks",
    ".keystore",
    ".p12",
    ".pfx",
    ".log",
    ".orig",
    ".pyc",
    ".pyo",
    ".swp",
    ".tmp",
    ".zip",
}
PRIVATE_FILE = re.compile(
    r"(?:^|/)(?:signing\.properties|key\.properties|local\.properties|\.env(?:\..*)?)$",
    re.IGNORECASE,
)


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        first = True
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            if first and chunk.startswith(b"version https://git-lfs.github.com/spec/v1\n"):
                raise SystemExit(
                    f"Unmaterialized Git LFS pointer: {path.relative_to(ROOT).as_posix()}. "
                    "Restore the verified LFS object before generating/checking the manifest."
                )
            first = False
            value.update(chunk)
    return value.hexdigest()


def included_files() -> list[Path]:
    files: list[Path] = []
    for path in ROOT.rglob("*"):
        relative = path.relative_to(ROOT)
        if any(part in EXCLUDED_DIRECTORIES for part in relative.parts):
            continue
        if path.is_symlink():
            raise SystemExit(f"Symbolic links are not accepted: {relative.as_posix()}")
        if not path.is_file():
            continue
        if path.name in EXCLUDED_NAMES or path.suffix.lower() in EXCLUDED_SUFFIXES:
            continue
        if relative.as_posix() == 'android/app/src/main/java/io/flutter/plugins/GeneratedPluginRegistrant.java':
            continue
        if PRIVATE_FILE.search(relative.as_posix()):
            # Flutter generates local.properties during ordinary validation.
            # Local SDK paths and signing settings are never source/archive input.
            continue
        if re.fullmatch(r"\..+\.[A-Za-z0-9]{6}(?:\.[A-Za-z0-9]{6})*", path.name):
            raise SystemExit(f"Partial transfer file must be resolved before manifest generation/check: {relative.as_posix()}")
        files.append(path)
    return sorted(files, key=lambda item: item.relative_to(ROOT).as_posix())


def expected_manifest(files: list[Path]) -> str:
    hashes = {path.relative_to(ROOT).as_posix(): digest(path) for path in files}
    core = ROOT / 'android/app/src/main/assets/nav_kurd_core'
    core_manifest = core / 'manifest.json'
    if core_manifest.is_file():
        pack = json.loads(core_manifest.read_text(encoding='utf-8'))
        catalogs = [row for row in pack.get('files', []) if row.get('path') == 'catalog.sqlite']
        if (len(catalogs) != 1 or type(catalogs[0].get('bytes')) is not int
                or catalogs[0]['bytes'] <= 0
                or not re.fullmatch(r'[0-9a-f]{64}', str(catalogs[0].get('sha256', '')))):
            raise SystemExit('The approved core manifest must declare exactly one valid catalog.')
        record = catalogs[0]
        catalog = core / 'catalog.sqlite'
        if (not catalog.is_file() or catalog.is_symlink()
                or catalog.stat().st_size != record['bytes']
                or hashes.get(catalog.relative_to(ROOT).as_posix()) != record['sha256']):
            raise SystemExit(
                'Catalog integrity mismatch: restore the complete catalog matching the approved '
                'core manifest. SOURCE_MANIFEST.sha256 was not rewritten.'
            )
    return "\n".join(
        f"{hashes[path.relative_to(ROOT).as_posix()]}  ./{path.relative_to(ROOT).as_posix()}"
        for path in files
    ) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--check",
        action="store_true",
        help="fail unless SOURCE_MANIFEST.sha256 exactly covers the current source tree",
    )
    args = parser.parse_args()

    files = included_files()
    if not files:
        raise SystemExit("No Android source files were found.")
    expected = expected_manifest(files)

    if args.check:
        if not MANIFEST.is_file():
            raise SystemExit(f"{MANIFEST.name} is missing.")
        actual = MANIFEST.read_text(encoding="utf-8")
        if actual != expected:
            def entries(text: str) -> dict[str, str]:
                return {row.split("  ./", 1)[1]: row.split("  ./", 1)[0]
                        for row in text.splitlines() if "  ./" in row}
            recorded, current = entries(actual), entries(expected)
            for label, paths in (
                ("Missing", recorded.keys() - current.keys()),
                ("Unexpected", current.keys() - recorded.keys()),
                ("Changed", {name for name in recorded.keys() & current.keys() if recorded[name] != current[name]}),
            ):
                if paths:
                    print(f"{label} ({len(paths)}): " + ", ".join(sorted(paths)[:12]))
            raise SystemExit(
                f"{MANIFEST.name} does not exactly match the current source tree. "
                "Run tools/update-source-manifest.py only from the approved release source."
            )
        print(f"Verified {MANIFEST.name}: {len(files)} files")
        return

    temporary = MANIFEST.with_suffix(".sha256.tmp")
    temporary.write_text(expected, encoding="utf-8")
    temporary.replace(MANIFEST)
    print(f"Updated {MANIFEST.name}: {len(files)} files")


if __name__ == "__main__":
    main()
