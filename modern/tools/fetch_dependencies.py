#!/usr/bin/env python3
"""Fetch pinned sources for portable macOS dependencies. Standard library only."""
from pathlib import Path
import hashlib
import tarfile
import urllib.request

root = Path(__file__).resolve().parents[2]
vendor = root / "modern/vendor"
sources = vendor / "sources"
sources.mkdir(parents=True, exist_ok=True)
for name, url, digest, directory in [
    ("libpng-1.6.58.tar.gz", "https://github.com/pnggroup/libpng/archive/refs/tags/v1.6.58.tar.gz", "a9d4df463d36a6e5f9c29bd6f4967312d17e996c1854f3511f833924eb1993cf", "libpng-1.6.58"),
    ("lzo-2.10.tar.gz", "https://www.oberhumer.com/opensource/lzo/download/lzo-2.10.tar.gz", "c0f892943208266f9b6543b3ae308fab6284c5c90e627931446fb49b4221a072", "lzo-2.10"),
]:
    path = vendor / name
    if not path.exists():
        with urllib.request.urlopen(url, timeout=120) as response:
            path.write_bytes(response.read())
    if hashlib.sha256(path.read_bytes()).hexdigest() != digest:
        raise SystemExit(f"Checksum mismatch: {name}")
    if not (sources / directory).exists():
        with tarfile.open(path) as archive:
            archive.extractall(sources, filter="data")
print("Pinned dependency sources ready.")
