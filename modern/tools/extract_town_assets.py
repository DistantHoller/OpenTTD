#!/usr/bin/env python3
"""Derive sprite/footprint/stage coverage from the pinned engine. GPL-2.0-only."""
from pathlib import Path
import json
import re

root = Path(__file__).resolve().parents[2]
source = (root / "src/table/town_land.h").read_text()
specs = {}
for body, number in re.findall(r"\bMS\((.*?)\),\s*//\s*([0-9A-F]{2})", source, re.S):
    name = re.search(r"STR_TOWN_BUILDING_NAME_(\w+)", body)
    if name:
        specs[int(number,16)] = (name.group(1), body)
selected = {key for key, (_,body) in specs.items() if "ClimateTemperate" in body}
for key in list(selected):
    body = specs[key][1]
    size = 4 if "Size2x2" in body else 2 if "Size1x2" in body or "Size2x1" in body else 1
    selected.update(range(key,key+size))
rows = []
table = source.split("_town_draw_tile_data[] = {",1)[1].split("\n};",1)[0]
for row in re.findall(r"\bM\((.*?)\)",table):
    columns = [value.strip() for value in row.split(",")]
    assert len(columns) == 10, columns
    rows.append(columns)
assert len(rows) == 110*16
entries = {}
grounds = set()
ground_kinds = {}
for house in sorted(selected):
    name = specs[house][0]
    for variant in range(4):
        for stage in range(4):
            row = rows[house*16+variant*4+stage]
            ground, building = row[0], row[2]
            if ground.startswith("0x"):
                grounds.add(int(ground,16))
                ground_kinds[str(int(ground,16))] = name
            elif ground == "SPR_CONCRETE_GROUND":
                grounds.add(1420)
                ground_kinds["1420"] = "CONCRETE"
            if not building.startswith("0x"):
                continue
            sprite = int(building,16)
            if sprite == 0:
                continue
            width,length,height = map(int,row[6:9])
            entry = entries.setdefault(sprite,dict(id=sprite,kind=name,stage=stage,width=length,length=width,height=height,houses=[]))
            # Shared original sprites must cover each of their original footprints.
            entry["width"] = max(entry["width"],length)
            entry["length"] = max(entry["length"],width)
            entry["height"] = max(entry["height"],height)
            entry["stage"] = max(entry["stage"],stage)
            if house not in entry["houses"]:
                entry["houses"].append(house)
result = dict(houses=sorted(selected),sprites=sorted(entries.values(),key=lambda value:value["id"]),grounds=sorted(grounds),ground_kinds=ground_kinds)
path = root / "modern/assets/town-coverage.json"
path.write_text(json.dumps(result,indent=2)+"\n")
print(f"Coverage: {len(selected)} temperate house tiles, {len(entries)} building sprites, {len(grounds)} courtyard sprites.")
