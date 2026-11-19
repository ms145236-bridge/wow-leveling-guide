"""Replay honours explicit held-item entries (optional steps on): empty bag, wrong item and held item."""
import argparse
import csv
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
sys.path.insert(0, str(Path(__file__).resolve().parent))
from check import mandatory_skips  # noqa: E402


def replay_rows(lua, faction, race, items, optional=True):
    with tempfile.TemporaryDirectory() as work:
        path = Path(work) / "events.tsv"
        command = [lua, "tools/tests/replay/replay.lua", race, "1", str(path), "solo", "0", faction,
                   "WARRIOR", "default", "items:" + ",".join(map(str, items))]
        command += ["optional"] if optional else ["", ""]
        subprocess.run(command, cwd=ROOT, check=True, capture_output=True, text=True)
        with path.open(encoding="utf-8") as stream:
            return list(csv.reader(stream, delimiter="\t"))


def events(lua, faction, race, items, optional=True):
    rows = replay_rows(lua, faction, race, items, optional)
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
    # Alliance 91741/96391 start from random drops (audit A-B9). Without the item neither the start nor the
    # Northshire chain and 96393 that depend on it are offered, and none of them is reported as a missed
    # mandatory step, with optional steps on or off. With the item (optional steps on) the whole chain runs.
    chain = {91741, 92124, 91743, 91745, 91752, 91758, 91772, 91775, 96391, 96393}
    for optional in (True, False):
        rows = replay_rows(lua, "Alliance", "Human", [], optional)
        taken = {int(row[4]) for row in rows if len(row) > 4 and row[4] and row[3] in ("accepted", "turned")}
        assert not taken & chain, f"no drop: chain offered {sorted(taken & chain)}"
        missed = {int(q) for _, _, q in mandatory_skips(rows)}
        assert not missed & chain, f"no drop: reported as missed {sorted(missed & chain)}"
    held = events(lua, "Alliance", "Human", [247834, 274268])
    for q in sorted(chain - {96393}):  # 96393 is Hall of Thanes work; this solo replay does not enter dungeons.
        assert ("accepted", q) in held and ("turned", q) in held, f"drop held: {q} not done"
    print("Replay held-item entries: empty, wrong, held, accepted and turned-in cases passed")


if __name__ == "__main__":
    main()
