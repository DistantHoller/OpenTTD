#!/usr/bin/env python3
"""Create a deterministic flat test terrain, not an art asset. GPL-2.0-only."""
from pathlib import Path
import struct
import zlib

root = Path(__file__).resolve().parents[2]
def chunk(kind, data):
    return struct.pack(">I", len(data)) + kind + data + struct.pack(">I", zlib.crc32(kind + data))
pixels = b"".join(b"\0" + bytes([128])*128 for _ in range(128))
png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB",128,128,8,0,0,0,0)) + chunk(b"IDAT",zlib.compress(pixels)) + chunk(b"IEND",b"")
path = root / "build/qa/flat-heightmap.png"
path.parent.mkdir(parents=True, exist_ok=True)
path.write_bytes(png)
print(path)
