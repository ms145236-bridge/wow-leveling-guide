"""Replay honours explicit held-item entries (optional steps on): empty bag, wrong item and held item."""
import argparse
import csv
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]


def events(lua, faction, race, items):
    with tempfile.TemporaryDirectory() as work:
        path = Path(work) / "events.tsv"
        command = [lua, "tools/tests/replay/replay.lua", race, "1", str(path), "solo", "0", faction,
                   "WARRIOR", "default", "items:" + ",".join(map(str, items)), "optional"]
        subprocess.run(command, cwd=ROOT, check=True, capture_output=True, text=True)
        with path.open(encoding="utf-8") as stream:
            rows = list(csv.reader(stream, delimiter="\t"))
    return {(row[3], int(row[4])) for row in rows if len(row) > 4 and row[4]}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua", default=os.getenv("LUA", "lua5.1"))
    lua = parser.parse_args().lua
    empty = events(lua, "Alliance", "Human", [])
    assert ("accepted", 351) not in empty and ("conditional", 351) not in empty, "empty bag: no accept"
    wrong = events(lua, "Alliance", "Human", [8704])
    assert ("accepted", 351) not in wrong, "wrong item: OOX-17/TN beacon still missing"
    assert ("accepted", 485) in wrong and ("turned", 836) in wrong, "OOX-09/HL beacon held: escort accepted and turned in"
    held = events(lua, "Alliance", "Human", [8623, 12771])
    for event in (("accepted", 351), ("turned", 351), ("accepted", 648), ("worked", 648), ("turned", 648), ("accepted", 5083), ("turned", 5083)):
        assert event in held, f"held item: missing {event}"
    assert ("accepted", 3721) not in held, "pet quest still needs all three escorts"
    horde = events(lua, "Horde", "Scourge", [2839])
    assert ("accepted", 361) in horde and ("turned", 361) in horde, "Horde letter held: accepted and turned in"
    print("Replay held-item entries: empty, wrong, held, accepted and turned-in cases passed")


if __name__ == "__main__":
    main()
