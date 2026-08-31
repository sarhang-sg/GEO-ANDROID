#!/usr/bin/env python3
"""Create a deterministic, manifest-gated NAV KURD Android source archive."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import stat
import zipfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOURCE_MANIFEST = ROOT / "SOURCE_MANIFEST.sha256"
VERSION = "9.0.0"
ARCHIVE_ROOT = f"NAV-KURD-ANDROID-{VERSION}"
RELEASE_DATE = (2026, 8, 30, 0, 0, 0)
MANIFEST_LINE = re.compile(r"^([0-9a-f]{64})  \./(.+)$")
FORBIDDEN = re.compile(
    r"(?:^|/)(?:"
    r"[^/]*\.(?:jks|keystore|apk|aab)|"
    r"signing\.properties|key\.properties|local\.properties"
    r")$",
    re.IGNORECASE,
)


def digest(path: Path) -> str:
    value = hashlib.sha256()
    with path.open("rb") as stream:
        for chunk in iter(lambda: stream.read(1024 * 1024), b""):
            value.update(chunk)
    return value.hexdigest()


def load_verified_files() -> list[Path]:
    if not SOURCE_MANIFEST.is_file():
        raise SystemExit("SOURCE_MANIFEST.sha256 is missing.")

    files: list[Path] = []
    seen: set[str] = set()
    for number, raw_line in enumerate(
        SOURCE_MANIFEST.read_text(encoding="utf-8").splitlines(), start=1
    ):
        match = MANIFEST_LINE.fullmatch(raw_line)
        if match is None:
            raise SystemExit(f"Malformed source manifest line {number}.")
        expected, relative = match.groups()
        if relative in seen:
            raise SystemExit(f"Duplicate source manifest path: {relative}")
        if relative.startswith("/") or ".." in Path(relative).parts:
            raise SystemExit(f"Unsafe source manifest path: {relative}")
        if FORBIDDEN.search(relative):
            raise SystemExit(f"Private or generated artifact is forbidden: {relative}")

        path = ROOT / relative
        if not path.is_file():
            raise SystemExit(f"Manifest file is missing: {relative}")
        actual = digest(path)
        if actual != expected:
            raise SystemExit(f"Manifest hash mismatch: {relative}")
        seen.add(relative)
        files.append(path)

    if not files:
        raise SystemExit("The source manifest is empty.")
    return files


def archive_info(name: str, path: Path) -> zipfile.ZipInfo:
    info = zipfile.ZipInfo(name, RELEASE_DATE)
    mode = 0o755 if path.stat().st_mode & stat.S_IXUSR else 0o644
    info.external_attr = (mode & 0xFFFF) << 16
    info.compress_type = zipfile.ZIP_DEFLATED
    info.create_system = 3
    return info


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--output-dir", type=Path, required=True)
    parser.add_argument(
        "--name", default=f"NAV-KURD-v{VERSION}-ANDROID.zip"
    )
    args = parser.parse_args()
    if Path(args.name).name != args.name or not args.name.endswith(".zip"):
        raise SystemExit("--name must be a plain ZIP filename.")

    source_files = load_verified_files()
    packaged_files = sorted([SOURCE_MANIFEST, *source_files], key=lambda path: path.as_posix())
    args.output_dir.mkdir(parents=True, exist_ok=True)
    target = args.output_dir / args.name
    target.unlink(missing_ok=True)

    with zipfile.ZipFile(
        target,
        "w",
        compression=zipfile.ZIP_DEFLATED,
        compresslevel=9,
        allowZip64=True,
    ) as archive:
        for path in packaged_files:
            relative = path.relative_to(ROOT).as_posix()
            archive.writestr(
                archive_info(f"{ARCHIVE_ROOT}/{relative}", path), path.read_bytes()
            )

    archive_sha256 = digest(target)
    checksum = target.with_suffix(".zip.sha256")
    checksum.write_text(f"{archive_sha256}  {target.name}\n", encoding="utf-8")
    report = target.with_suffix(".zip.manifest.json")
    report.write_text(
        json.dumps(
            {
                "schema": "NAV KURD Android packaged source evidence v1",
                "version": VERSION,
                "zip": target.name,
                "bytes": target.stat().st_size,
                "sha256": archive_sha256,
                "fileCount": len(packaged_files),
                "uncompressedBytes": sum(path.stat().st_size for path in packaged_files),
                "sourceManifestEntries": len(source_files),
                "secretSafe": True,
                "containsBuiltApk": False,
            },
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    print(
        json.dumps(
            {
                "zip": str(target),
                "sha256": str(checksum),
                "manifest": str(report),
                "files": len(packaged_files),
            },
            indent=2,
        )
    )


if __name__ == "__main__":
    main()
