#!/usr/bin/env python3
"""Build a complete sound bank with original 48 kHz interface/construction sounds.

Unchanged slots retain OpenSFX recordings and their embedded attribution.
This script and its synthesized replacements: SPDX-License-Identifier: GPL-2.0-only.
"""
from pathlib import Path
import array
import hashlib
import io
import math
import random
import shutil
import struct
import sys
import wave

ROOT = Path(__file__).resolve().parents[2]
RATE = 48000

def synth(kind, duration):
    rng = random.Random(20261012)
    samples = []
    last_noise = 0.0
    for i in range(int(duration * RATE)):
        t = i / RATE
        n = rng.uniform(-1, 1)
        high = n - last_noise
        last_noise = n
        if kind == "click":
            v = (math.sin(2 * math.pi * 580 * t) * .7 + high * .08) * math.exp(-t * 75)
        elif kind in ("delivery", "news"):
            v = 0
            for start, freq in [(0, 1046.5), (.09, 1568 if kind == "delivery" else 1318.5)]:
                u = t - start
                if u >= 0:
                    v += (math.sin(2*math.pi*freq*u) + .18*math.sin(2*math.pi*freq*2.01*u)) * math.exp(-u*15) * min(1,u*800)
        elif kind in ("rail", "bridge"):
            v = 0
            for start in (0, .085, .16):
                u = t - start
                if u >= 0:
                    for freq, amount in [(420, .4), (917, .25), (1730, .15), (2671, .08)]:
                        v += amount * math.sin(2*math.pi*freq*u) * math.exp(-u*25)
                    v += high*.12*math.exp(-u*80)
        elif kind == "water":
            v = n * math.exp(-t * 12) * .35 + math.sin(2*math.pi*(260*t + 180*t*t))*.2*math.exp(-t*18)
        else:
            v = (math.sin(2*math.pi*210*t)*.5 + high*.22) * math.exp(-t*35)
        v *= min(1.0, t*3000, max(0, (duration-t)*3000))
        samples.append(v)
    peak = max(abs(v) for v in samples) or 1
    target = .18 if kind in ("click", "delivery", "news") else .32
    pcm = array.array("h", (int(v/peak*target*32767) for v in samples))
    if sys.byteorder != "little":
        pcm.byteswap()
    out = io.BytesIO()
    with wave.open(out, "wb") as wav:
        wav.setnchannels(1); wav.setsampwidth(2); wav.setframerate(RATE)
        wav.writeframes(pcm.tobytes())
    return out.getvalue()

def main():
    source = ROOT / "modern/assets/baseset/opensfx-1.0.3"
    dest = ROOT / "modern/assets/baseset/modern-temperate"
    dest.mkdir(parents=True, exist_ok=True)
    data = (source / "opensfx.cat").read_bytes()
    header = struct.unpack_from("<I", data)[0]
    assert header & 0x80000000
    count = (header & 0x7fffffff) // 8
    assert count == 73
    replacements = {2:("water",.4), 20:("delivery",.4), 21:("click",.09), 22:("news",.35), 31:("build",.18), 32:("rail",.4), 39:("bridge",.5)}
    payloads = []
    lengths = []
    previews = ROOT / "modern/assets/audio"
    previews.mkdir(parents=True, exist_ok=True)
    for slot in range(count):
        offset, length = struct.unpack_from("<II", data, slot*8)
        offset &= 0x7fffffff
        name_len = data[offset]
        name = data[offset+1:offset+1+name_len]
        wav = data[offset+1+name_len:offset+1+name_len+length]
        if slot in replacements:
            kind, duration = replacements[slot]
            wav = synth(kind, duration)
            (previews / (kind + ".wav")).write_bytes(wav)
            name = f"Modern {kind}. Original synthesis 2026. GPLv2.\0".encode()
        assert len(name) <= 255 and wav[:4] == b"RIFF"
        payloads.append(bytes([len(name)]) + name + wav)
        lengths.append(len(wav))
    offset = count * 8
    records = []
    for i, payload in enumerate(payloads):
        records.append(struct.pack("<II", offset | (0x80000000 if i == 0 else 0), lengths[i]))
        offset += len(payload)
    bank = b"".join(records + payloads)
    (dest / "modern-temperate.cat").write_bytes(bank)
    digest = hashlib.md5(bank).hexdigest()
    (dest / "modern-temperate.obs").write_text(f"""[metadata]
name = Modern Temperate
shortname = MTMP
version = 10001
description = Rich OpenSFX recordings with gentle 48 kHz interface and construction effects. See credits.
[files]
samples = modern-temperate.cat
[md5s]
modern-temperate.cat = {digest}
[origin]
default = Bundled with OpenTTD Modern. Build source: modern/tools/build_soundset.py
""")
    for filename in ("license.txt", "readme.txt", "changelog.txt"):
        shutil.copy2(source / filename, dest / filename)
    (dest / "MODIFICATIONS.txt").write_text("Based on OpenSFX 1.0.3. Original slots 2, 20, 21, 22, 31, 32, 39 replaced with original 48 kHz synthesized sounds. All other recordings retain the OpenSFX embedded attribution and licensing. Replacement source is modern/tools/build_soundset.py (GPLv2).\n")
    print("Modern Temperate: 73 valid WAV slots; 7 original replacements.")

if __name__ == "__main__":
    main()
