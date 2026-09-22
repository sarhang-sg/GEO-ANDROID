#!/usr/bin/env python3
"""Verify required local data and presentation bytes inside real APK/AAB files."""

from __future__ import annotations

import argparse
import hashlib
import json
import re
import zipfile
from pathlib import Path, PurePosixPath

ROOT = Path(__file__).resolve().parents[1]
FORBIDDEN = re.compile(
    r"(?:^|/)(?:kernel_blob\.bin|staging|debug|\.git|node_modules)(?:/|$)"
    r"|(?:^|/)(?:[^/]*\.(?:jks|keystore|p12|pfx)|signing\.properties|key\.properties|\.env(?:\..*)?)$",
    re.IGNORECASE,
)


def file_hash(path: Path) -> str:
    with path.open("rb") as stream:
        return stream_hash(stream)


def stream_hash(stream) -> str:
    digest = hashlib.sha256()
    for data in iter(lambda: stream.read(1024 * 1024), b""):
        digest.update(data)
    return digest.hexdigest()


def expected_assets(root: Path) -> dict[str, tuple[int, str]]:
    expected: dict[str, tuple[int, str]] = {}
    for folder, packaged in (
        ("android/app/src/main/assets/nav_kurd_core", "assets/nav_kurd_core"),
        ("assets/r16", "assets/flutter_assets/assets/r16"),
    ):
        manifest = root / folder / "manifest.json"
        expected[f"{packaged}/manifest.json"] = (manifest.stat().st_size, file_hash(manifest))
        rows = json.loads(manifest.read_text(encoding="utf-8"))["files"]
        for row in rows:
            path = row["path"]
            if (not isinstance(path, str) or not path or path.startswith("/")
                    or "\\" in path or any(p in {"", ".", ".."} for p in path.split("/"))):
                raise SystemExit("Unsafe required asset path")
            key = f"{packaged}/{path}"
            if key in expected:
                raise SystemExit(f"Duplicate required asset: {key}")
            expected[key] = (int(row["bytes"]), row["sha256"])
    logo = root / "assets/images/nav-kurd-logo.png"
    expected["assets/flutter_assets/assets/images/nav-kurd-logo.png"] = (logo.stat().st_size, file_hash(logo))
    return expected


def verify_archive(path: Path, expected: dict[str, tuple[int, str]], bundle: bool) -> None:
    if not path.is_file() or path.stat().st_size <= 1024 * 1024:
        raise SystemExit(f"Release binary is absent or too small: {path.name}")
    prefix = "base/" if bundle else ""
    with zipfile.ZipFile(path) as archive:
        infos = archive.infolist()
        names = [info.filename for info in infos]
        if len(names) != len(set(names)):
            raise SystemExit(f"Duplicate ZIP entries: {path.name}")
        for name in names:
            if name.startswith("/") or ".." in PurePosixPath(name).parts or "\\" in name:
                raise SystemExit(f"Unsafe packaged path: {path.name}")
            if FORBIDDEN.search(name):
                raise SystemExit(f"Debug/staging/private material in {path.name}: {name}")
        actual_core = {n for n in names if n.startswith(prefix + "assets/nav_kurd_core/") and not n.endswith("/")}
        expected_core = {prefix + n for n in expected if n.startswith("assets/nav_kurd_core/")}
        if actual_core != expected_core:
            raise SystemExit(f"Core pack contains missing or unmanifested files: {path.name}")
        presentation = prefix + "assets/flutter_assets/assets/r16/"
        actual_presentation = {n for n in names if n.startswith(presentation) and not n.endswith("/")}
        expected_presentation = {prefix + n for n in expected if n.startswith("assets/flutter_assets/assets/r16/")}
        if actual_presentation != expected_presentation:
            raise SystemExit(f"Presentation contains missing or unmanifested files: {path.name}")
        for name, (size, digest) in expected.items():
            full = prefix + name
            try:
                info = archive.getinfo(full)
            except KeyError:
                raise SystemExit(f"Required release asset missing: {path.name}: {name}") from None
            if info.file_size != size:
                raise SystemExit(f"Required asset size mismatch: {path.name}: {name}")
            with archive.open(info) as stream:
                if stream_hash(stream) != digest:
                    raise SystemExit(f"Required asset digest mismatch: {path.name}: {name}")
            if not bundle and name.endswith(".pmtiles") and info.compress_type != zipfile.ZIP_STORED:
                raise SystemExit(f"Random-access PMTiles must be uncompressed in APK: {name}")
        if prefix + "lib/arm64-v8a/libapp.so" not in names:
            raise SystemExit(f"ARM64 release application library is missing: {path.name}")
    print(f"Verified {len(expected)} exact local assets and ARM64 release library: {path.name}")


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--apk", type=Path, required=True)
    parser.add_argument("--aab", type=Path, required=True)
    args = parser.parse_args()
    expected = expected_assets(ROOT)
    verify_archive(args.apk, expected, bundle=False)
    verify_archive(args.aab, expected, bundle=True)


if __name__ == "__main__":
    main()
