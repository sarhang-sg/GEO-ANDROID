#!/usr/bin/env python3
"""Verify every Android launcher PNG before Gradle/AAPT2 sees it."""

from __future__ import annotations

import struct
import zlib
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / "android/app/src/main/res"
LEGACY_SIZES = {
    "mdpi": 48,
    "hdpi": 72,
    "xhdpi": 96,
    "xxhdpi": 144,
    "xxxhdpi": 192,
}
FOREGROUND_SIZES = {
    "mdpi": 108,
    "hdpi": 162,
    "xhdpi": 216,
    "xxhdpi": 324,
    "xxxhdpi": 432,
}
PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def verify_png(path: Path, expected_size: int) -> None:
    payload = path.read_bytes()
    if not payload.startswith(PNG_SIGNATURE):
        raise ValueError("missing PNG signature")

    offset = len(PNG_SIGNATURE)
    chunks: list[tuple[bytes, bytes]] = []
    found_iend = False
    while offset < len(payload):
        if len(payload) - offset < 12:
            raise ValueError("truncated PNG chunk header")
        length = struct.unpack(">I", payload[offset : offset + 4])[0]
        chunk_type = payload[offset + 4 : offset + 8]
        chunk_end = offset + 12 + length
        if chunk_end > len(payload):
            raise ValueError(f"truncated {chunk_type.decode('ascii', 'replace')} chunk")
        data = payload[offset + 8 : offset + 8 + length]
        stored_crc = struct.unpack(">I", payload[offset + 8 + length : chunk_end])[0]
        actual_crc = zlib.crc32(chunk_type + data) & 0xFFFFFFFF
        if stored_crc != actual_crc:
            raise ValueError(f"invalid {chunk_type.decode('ascii', 'replace')} CRC")
        chunks.append((chunk_type, data))
        offset = chunk_end
        if chunk_type == b"IEND":
            found_iend = True
            break

    if not found_iend:
        raise ValueError("missing IEND chunk")
    if offset != len(payload):
        raise ValueError("unexpected bytes after IEND")
    if not chunks or chunks[0][0] != b"IHDR" or len(chunks[0][1]) != 13:
        raise ValueError("invalid IHDR chunk")

    width, height, bit_depth, color_type, compression, filtering, interlace = struct.unpack(
        ">IIBBBBB", chunks[0][1]
    )
    if (width, height) != (expected_size, expected_size):
        raise ValueError(f"expected {expected_size}x{expected_size}, found {width}x{height}")
    if bit_depth != 8 or color_type != 2:
        raise ValueError(f"AAPT2-safe opaque RGB 8-bit PNG required, found depth={bit_depth}, type={color_type}")
    if (compression, filtering, interlace) != (0, 0, 0):
        raise ValueError("non-standard or interlaced PNG")

    compressed = b"".join(data for chunk_type, data in chunks if chunk_type == b"IDAT")
    if not compressed:
        raise ValueError("missing IDAT data")
    decoded = zlib.decompress(compressed)
    bytes_per_pixel = 3 if color_type == 2 else 4
    expected_decoded = height * (1 + width * bytes_per_pixel)
    if len(decoded) != expected_decoded:
        raise ValueError(
            f"invalid decoded payload size: expected {expected_decoded}, found {len(decoded)}"
        )


def main() -> None:
    targets: list[tuple[Path, int]] = []
    for density, size in LEGACY_SIZES.items():
        directory = RES / f"mipmap-{density}"
        targets.extend(
            (directory / name, size)
            for name in ("ic_launcher.png", "ic_launcher_round.png")
        )
    for density, size in FOREGROUND_SIZES.items():
        targets.append((RES / f"mipmap-{density}" / "ic_launcher_foreground.png", size))

    failures: list[str] = []
    for path, size in targets:
        try:
            verify_png(path, size)
        except (OSError, ValueError, zlib.error) as exc:
            failures.append(f"{path.relative_to(ROOT)}: {exc}")

    if failures:
        raise SystemExit("Launcher PNG validation failed:\n" + "\n".join(failures))
    print(f"PASS launcher PNGs: {len(targets)} complete AAPT2-safe files.")


if __name__ == "__main__":
    main()
