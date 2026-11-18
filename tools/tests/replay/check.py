"""Replay native origins and both night elf paths against generated addon data."""
import argparse
import csv
import json
import os
import subprocess
import tempfile
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path

TESTS = Path(__file__).resolve().parent
ROOT = TESTS.parents[2]
MODES = ("solo", "party", "allparty")


def itineraries():
    factions = json.loads((TESTS / "roster.json").read_text())
    for faction, races in factions.items():
        for race, classes in races.items():
            branches = ("default", "coast") if race == "NightElf" else ("default",)
            for class_name in classes:
                for branch in branches:
                    for mode in MODES:
                        yield faction, race, class_name, branch, mode


def replay(case, lua, work):
    faction, race, class_name, branch, mode = case
    events = work / ("-".join(case) + ".tsv")
    command = [lua, str(TESTS / "replay.lua"), race, "1", str(events), mode,
               "0", faction, class_name, branch]
    result = subprocess.run(command, cwd=ROOT, text=True, capture_output=True)
    if result.returncode:
        raise RuntimeError(f"{case}: {result.stderr}")
    stations = list(csv.reader(result.stdout.splitlines(), delimiter="\t"))
    with events.open() as stream:
        log = list(csv.reader(stream, delimiter="\t"))
    ids = {row[2] for row in stations}
    total_xp = sum(int(row[k]) for row in stations for k in (10, 11, 12))
    peak = max(int(row[14]) for row in stations)
    assert stations[-1][8] == "60" and total_xp == 4084700, case
    assert peak <= 40 and not any(row[3] == "full" for row in log), case
    assert branch != "coast" or ("02-10" in ids and "01-9" not in ids), case
    assert mode != "solo" or not any(s.startswith("05-") for s in ids), case
    turned = {row[4] for row in log if row[3] == "turned"}
    if faction == "Horde":
        assert {"2621", "2622", "2784"} <= turned, case
        assert not {"2521", "3501"} & turned, case  # No rare drops supplied.
    return (*case, sum(int(row[12]) for row in stations), len(turned), peak)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua", default=os.getenv("LUA", "lua5.1"))
    parser.add_argument("--output", type=Path, help="write the per-character CSV here")
    args = parser.parse_args()
    cases = list(itineraries())
    with tempfile.TemporaryDirectory() as directory:
        with ThreadPoolExecutor(max_workers=4) as pool:
            rows = list(pool.map(lambda case: replay(case, args.lua, Path(directory)), cases))
    if args.output:
        with args.output.open("w", encoding="utf-8-sig", newline="") as stream:
            writer = csv.writer(stream)
            writer.writerow(("陣營", "種族", "職業", "分支", "情境", "另補XP", "已交任務數", "日誌峰值"))
            writer.writerows(rows)
    print(f"Passed {len(rows)} replays across {len(rows) // len(MODES)} itineraries")


if __name__ == "__main__":
    main()
