#!/usr/bin/env python3
"""Combine independently reproducible asset families. GPL-2.0-only."""
from pathlib import Path

directory = Path(__file__).resolve().parents[2] / "modern/assets/sprites"
entries = {}
for path in sorted(directory.glob("manifest-*.tsv")):
    for line in path.read_text().splitlines():
        fields = line.split()
        assert len(fields) == 5, (path, line)
        sprite = int(fields[0])
        assert sprite not in entries, (path, sprite)
        entries[sprite] = "\t".join(fields)
assert entries
(directory / "manifest.tsv").write_text("".join(entries[key] + "\n" for key in sorted(entries)))
print(f"Assembled {len(entries)} sprites from source manifests.")
