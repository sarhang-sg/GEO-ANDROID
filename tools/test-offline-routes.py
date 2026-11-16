"""Verify shipped graph bytes and calculate real routes without a network provider."""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from zipfile import ZipFile

ROOT = Path(__file__).resolve().parents[1]
manifest = json.loads((ROOT / "contracts/offline-routing.json").read_text())
jar = ROOT / "third_party/brouter/brouter-core-1.7.10.jar"
with tempfile.TemporaryDirectory() as temp:
    out = Path(temp)
    for package in sys.argv[1:]:
        prefix = "base/assets/" if package.endswith(".aab") else "assets/"
        with ZipFile(package) as archive:
            assert json.loads(archive.read(prefix + "road-graph/manifest.json")) == manifest
            for name, (size, sha) in manifest["files"].items():
                p = out / "graph" / name
                p.parent.mkdir(exist_ok=True)
                with archive.open(prefix + "road-graph/" + name) as source, p.open("wb") as target:
                    shutil.copyfileobj(source, target)
                assert p.stat().st_size == size and hashlib.sha256(p.read_bytes()).hexdigest() == sha, name
            for name in ("lookups.dat", "car-fast.brf", "hiking-mountain.brf", "trekking.brf"):
                p = out / "profiles" / name
                p.parent.mkdir(exist_ok=True)
                p.write_bytes(archive.read(prefix + "routing-profiles/" + name))
                assert p.read_bytes() == (ROOT / "android/app/src/main/assets/routing-profiles" / name).read_bytes()
    if not sys.argv[1:]:
        raise SystemExit("Supply an actual signed or debug APK/AAB")
    subprocess.run(["java", "-m", "jdk.compiler/com.sun.tools.javac.Main", "-cp", str(jar),
                    "-d", str(out), str(ROOT / "android/app/src/main/java/btools/router/NavKurdDirections.java"),
                    str(ROOT / "tools/offline-routing-check/OfflineRouteCheck.java")], check=True)
    subprocess.run(["java", "-cp", str(out) + ":" + str(jar), "OfflineRouteCheck",
                    str(out / "graph"), str(out / "profiles")], check=True, timeout=100)
