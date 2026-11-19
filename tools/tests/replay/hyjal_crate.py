"""Check the XP and dependent quests when the issued Hyjal crate cannot be delivered."""
import csv
import os
import subprocess
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
LUA = os.getenv("LUA", "lua5.1")
DELIVERY = "92009"
FOLLOWUPS = {"92011", "92328"}


def witness(work, scenario):
    events_file = work / (scenario + ".tsv")
    wrapper = work / "scenario.lua"
    wrapper.write_text(
        f'arg[23] = "{scenario}"\nassert(loadfile("tools/tests/replay/replay.lua"))()\n',
        encoding="utf-8",
    )
    run = subprocess.run(
        [LUA, str(wrapper), "Human", "1", str(events_file), "solo", "0",
         "Alliance", "PRIEST", "default"],
        cwd=ROOT,
        check=True,
        capture_output=True,
        text=True,
    )
    with events_file.open(encoding="utf-8") as stream:
        events = list(csv.reader(stream, delimiter="\t"))
    stations = list(csv.reader(run.stdout.splitlines(), delimiter="\t"))
    assert ("accepted", DELIVERY) in {(row[3], row[4]) for row in events}
    turned = {row[4]: int(row[7]) for row in events if row[3] == "turned"}
    grind = sum(int(row[12]) for row in stations)
    return turned, grind


def main():
    with tempfile.TemporaryDirectory() as work:
        work = Path(work)
        healthy, healthy_grind = witness(work, "crate-intact")
        assert healthy[DELIVERY] == 5800 and FOLLOWUPS <= healthy.keys()
        for scenario in ("crate-lost", "crate-failed"):
            turned, grind = witness(work, scenario)
            assert healthy.keys() - turned.keys() == FOLLOWUPS | {DELIVERY}, scenario
            assert turned.keys() <= healthy.keys(), scenario
            assert grind - healthy_grind == sum(healthy[q] for q in FOLLOWUPS | {DELIVERY}), scenario
    print("Hyjal crate replay: lost or failed shipments grant no delivery or follow-up XP")


if __name__ == "__main__":
    main()
