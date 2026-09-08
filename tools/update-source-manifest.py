#!/usr/bin/env python3
"""Regenerate the complete deterministic Android source manifest."""

from __future__ import annotations

import hashlib
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
    "build",
    "coverage",
    "node_modules",
}
EXCLUDED_NAMES = {
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
    ".log",
    ".orig",
    ".swp",
    ".tmp",
    ".zip",
}
PRIVATE_FILE = re.compile(
    r"(?:^|/)(?:signing\.properties|key\.properties|local\.properties|\.env)$",
    re.IGNORECASE,
)


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
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
        if PRIVATE_FILE.search(relative.as_posix()):
            raise SystemExit(f"Private file must not be packaged: {relative.as_posix()}")
        files.append(path)
    return sorted(files, key=lambda item: item.relative_to(ROOT).as_posix())


def main() -> None:
    files = included_files()
    if not files:
        raise SystemExit("No Android source files were found.")
    lines = [
        f"{digest(path)}  ./{path.relative_to(ROOT).as_posix()}"
        for path in files
    ]
    temporary = MANIFEST.with_suffix(".sha256.tmp")
    temporary.write_text("\n".join(lines) + "\n", encoding="utf-8")
    temporary.replace(MANIFEST)
    print(f"Updated {MANIFEST.name}: {len(files)} files")


if __name__ == "__main__":
    main()
