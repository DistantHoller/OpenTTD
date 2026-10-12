#!/usr/bin/env python3
"""Fetch pinned, checksum-verified upstream base sets. Standard library only."""
from pathlib import Path
import hashlib
import tarfile
import urllib.request
import zipfile

ROOT = Path(__file__).resolve().parents[2]
PACKS = [
    ("OpenGFX2_HighDef-0.8.1.tar", "https://github.com/OpenTTD/OpenGFX2/releases/download/0.8.1/OpenGFX2_HighDef-0.8.1.tar", "c1f5066e82b7754d29f7637457f5b77ac71f10198e3a38f7a75353ea62386e2d"),
    ("opensfx-1.0.3-all.zip", "https://cdn.openttd.org/opensfx-releases/1.0.3/opensfx-1.0.3-all.zip", "e0a218b7dd9438e701503b0f84c25a97c1c11b7c2f025323fb19d6db16ef3759"),
]

def main():
    vendor = ROOT / "modern/vendor"
    destination = ROOT / "modern/assets/baseset"
    vendor.mkdir(parents=True, exist_ok=True)
    destination.mkdir(parents=True, exist_ok=True)
    for name, url, digest in PACKS:
        path = vendor / name
        if not path.exists():
            partial = path.with_suffix(path.suffix + ".part")
            print(f"Downloading {name}", flush=True)
            with urllib.request.urlopen(url, timeout=120) as response, partial.open("wb") as output:
                while data := response.read(1024 * 1024):
                    output.write(data)
            partial.replace(path)
        actual = hashlib.sha256(path.read_bytes()).hexdigest()
        if actual != digest:
            raise SystemExit(f"Checksum mismatch for {name}: {actual}")
        if name.endswith(".zip"):
            with zipfile.ZipFile(path) as archive:
                for member in archive.infolist():
                    target = (destination / member.filename).resolve()
                    if not target.is_relative_to(destination.resolve()):
                        raise SystemExit("Unsafe archive path")
                archive.extractall(destination)
        else:
            with tarfile.open(path) as archive:
                archive.extractall(destination, filter="data")
    with tarfile.open(destination / "opensfx-1.0.3.tar") as archive:
        archive.extractall(destination, filter="data")
    print("Pinned base sets ready.")

if __name__ == "__main__":
    main()
