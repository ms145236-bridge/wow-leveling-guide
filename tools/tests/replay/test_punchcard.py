"""Optional Gnomeregan replay only completes Data Rescue with an observed card."""

import csv
import os
from pathlib import Path
import subprocess
import tempfile


def replay(item_argument, events):
    command = [
        os.environ.get("LUA", "lua5.1"), "tools/tests/replay/replay.lua",
        "Dwarf", "1", str(events), "party", "0", "Alliance", "PALADIN", "default",
        item_argument, "optional",
    ]
    subprocess.run(command, check=True, stdout=subprocess.DEVNULL)
    with events.open() as stream:
        rows = list(csv.reader(stream, delimiter="\t"))
    assert any(row[3] == "superseded" and row[4] == "2931" and row[7] == "2930" for row in rows)
    return [(row[3], row[7]) for row in rows if row[4] == "2930"]


with tempfile.TemporaryDirectory() as directory:
    events = Path(directory) / "events.tsv"
    missing_card = [("accepted", ""), ("missing-material", "9316")]
    assert replay("", events) == missing_card
    assert replay("items:9279,9280,9281,9282", events) == missing_card
    assert replay("items:9316", events) == [("accepted", ""), ("worked", "0"), ("turned", "3650")]

print("Data Rescue replay: only the observed prismatic punch card grants turn-in XP")
