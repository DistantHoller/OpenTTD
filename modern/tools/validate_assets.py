#!/usr/bin/env python3
"""Validate exported PNGs, anchors and company-paint masks without editing images."""
from pathlib import Path
import struct
import zlib
import json

root = Path(__file__).resolve().parents[2]
directory = root / "modern/assets/sprites"

def paeth(a, b, c):
    p = a + b - c
    distances = [abs(p-a), abs(p-b), abs(p-c)]
    return (a,b,c)[distances.index(min(distances))]

def rgba(path):
    data = path.read_bytes()
    assert data[:8] == b"\x89PNG\r\n\x1a\n", path
    offset, payload = 8, b""
    width = height = 0
    while offset < len(data):
        size = struct.unpack_from(">I",data,offset)[0]
        kind = data[offset+4:offset+8]
        chunk = data[offset+8:offset+8+size]
        assert struct.unpack_from(">I",data,offset+8+size)[0] == zlib.crc32(kind+chunk), path
        if kind == b"IHDR":
            width,height,depth,colour,compression,filtering,interlace = struct.unpack(">IIBBBBB",chunk)
            assert (depth,colour,compression,filtering,interlace) == (8,6,0,0,0), path
        elif kind == b"IDAT":
            payload += chunk
        offset += size + 12
    stride = width * 4
    raw = zlib.decompress(payload)
    assert len(raw) == (stride+1)*height, path
    previous = bytearray(stride)
    output = bytearray()
    for y in range(height):
        start = y*(stride+1)
        mode = raw[start]
        assert mode <= 4
        row = bytearray(raw[start+1:start+1+stride])
        for i in range(stride):
            a = row[i-4] if i >= 4 else 0
            b = previous[i]
            c = previous[i-4] if i >= 4 else 0
            predictor = (0,a,b,(a+b)//2,paeth(a,b,c))[mode]
            row[i] = (row[i]+predictor) & 255
        output += row
        previous = row
    return width,height,output

seen = set()
company_sprites = 0
for line in (directory / "manifest.tsv").read_text().splitlines():
    sprite,x,y,company,filename = line.split()
    sprite,x,y,company = map(int,(sprite,x,y,company))
    assert sprite not in seen
    seen.add(sprite)
    assert -1024 <= x <= 1024 and -1024 <= y <= 1024
    width,height,pixels = rgba(directory / filename)
    assert 0 < width <= 1024 and 0 < height <= 1024
    assert width % 4 == height % 4 == 0
    assert any(pixels[i+3] for i in range(0,len(pixels),4)), filename
    if company:
        assert any(pixels[i+3] and pixels[i+2] > 60 and pixels[i+2] > pixels[i]*2 and pixels[i+2] > pixels[i+1]*1.5 for i in range(0,len(pixels),4)), filename
        company_sprites += 1
coverage = json.loads((root / "modern/assets/town-coverage.json").read_text())
town_ids = {entry["id"] for entry in coverage["sprites"]} | set(coverage["grounds"])
assert seen == set(range(0x628,0x628+19*7)) | set(range(0xB7D,0xB7D+8)) | set(range(0xAAD,0xAAD+4)) | set(range(3924,4023)) | set(range(1069,1087)) | {1005,1006,1011,1012} | set(range(4126,4297)) | set(range(1313,1351)) | {1406,1407} | town_ids
assert 0 not in seen
assert company_sprites == 22
print(f"Validated {len(seen)} nonempty RGBA sprites, 4x dimensions, unique IDs, anchors and {company_sprites} company-paint masks.")
