"""Hydrate the exact four routable OpenStreetMap segments used by the Android build."""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import shutil
import tempfile
import time
from urllib.request import Request, urlopen


ROOT = Path(__file__).resolve().parents[1]
MANIFEST = json.loads((ROOT / "contracts/offline-routing.json").read_text())
RELEASES = "https://github.com/sarhang-sg/GEO-ANDROID/releases/download/"


def matches(path, size, digest):
    if not path.is_file() or path.stat().st_size != size:
        return False
    sha = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(256 * 1024), b""):
            sha.update(chunk)
    return sha.hexdigest() == digest


def hydrate(directory, base, item):
    name, (size, digest) = item
    target = directory / name
    if matches(target, size, digest):
        return
    for attempt in range(3):
        temp = None
        try:
            request = Request(base + name, headers={"User-Agent": "NAV-KURD-road-graph/11"})
            with tempfile.NamedTemporaryFile(dir=directory, delete=False) as out:
                temp = Path(out.name)
                with urlopen(request, timeout=55) as source:
                    shutil.copyfileobj(source, out, length=256 * 1024)
            if not matches(temp, size, digest):
                raise ValueError(f"Incorrect size or SHA-256 for {name}")
            os.replace(temp, target)
            return
        except OSError:
            if attempt == 2:
                raise
            time.sleep(2 ** (attempt + 1))
        finally:
            if temp is not None:
                temp.unlink(missing_ok=True)


def main():
    args = argparse.ArgumentParser(description=__doc__)
    args.add_argument("--out", type=Path, required=True)
    args.add_argument("--upstream", action="store_true", help="Create a new graph snapshot from BRouter")
    opts = args.parse_args()
    opts.out.mkdir(parents=True, exist_ok=True)
    base = MANIFEST["source"] if opts.upstream else RELEASES + MANIFEST["tag"] + "/"
    with concurrent.futures.ThreadPoolExecutor(max_workers=4) as pool:
        list(pool.map(lambda item: hydrate(opts.out, base, item), MANIFEST["files"].items()))
    shutil.copyfile(ROOT / "contracts/offline-routing.json", opts.out / "manifest.json")
    print(f"Verified {len(MANIFEST['files'])} routing segments for {MANIFEST['tag']}")


if __name__ == "__main__":
    main()
