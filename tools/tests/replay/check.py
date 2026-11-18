"""Replay native origins and both night elf paths against generated addon data."""
import argparse
import csv
import json
import os
import subprocess
import tempfile
from concurrent.futures import ThreadPoolExecutor
from contextlib import nullcontext
from pathlib import Path
from typing import NamedTuple

TESTS = Path(__file__).resolve().parent
ROOT = TESTS.parents[2]
MODES = ("solo", "party", "allparty")
NATIVE_STATIONS = {
    "Alliance": {"Human": "01-1", "Dwarf": "01-3", "Gnome": "01-3", "NightElf": "01-5", "Skyborne": "01-7"},
    "Horde": {"Orc": "01-1", "Troll": "01-1", "Tauren": "01-3", "Scourge": "01-5", "Skyborne": "01-7"},
}


class Case(NamedTuple):
    faction: str
    race: str
    class_name: str
    branch: str
    mode: str


SOLO_WITNESSES = {
    Case("Alliance", "Human", "PRIEST", "default", "solo"),
    Case("Horde", "Scourge", "PALADIN", "default", "solo"),
}


def itineraries(factions):
    for faction, races in factions.items():
        for race, classes in races.items():
            branches = ("default", "coast") if race == "NightElf" else ("default",)
            for class_name in classes:
                for branch in branches:
                    for mode in MODES:
                        yield Case(faction, race, class_name, branch, mode)


def coverage(cases):
    return {
        "native race and branch": {(case.faction, case.race, case.branch) for case in cases},
        "faction and class": {(case.faction, case.class_name) for case in cases},
        "faction and mode": {(case.faction, case.mode) for case in cases},
    }


def validate_representative(cases, full):
    selected = set(cases)
    if len(selected) != len(cases):
        raise ValueError("duplicate representative replay cases")
    invalid = selected - set(full)
    if invalid:
        raise ValueError(f"unsupported representative replay cases: {sorted(invalid)}")
    covered = coverage(cases)
    for dimension, expected in coverage(full).items():
        missing = expected - covered[dimension]
        if missing:
            raise ValueError(f"missing {dimension}: {sorted(missing)}")
    missing = SOLO_WITNESSES - selected
    if missing:
        raise ValueError(f"missing solo witnesses: {sorted(missing)}")


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
    visits = [row[2] for row in stations]
    total_xp = sum(int(row[k]) for row in stations for k in (10, 11, 12))
    peak = max(int(row[14]) for row in stations)
    assert stations[0][2] == NATIVE_STATIONS[faction][race], case
    assert stations[-1][8] == "60" and total_xp == 4084700, case
    assert peak <= 40 and not any(row[3] == "full" for row in log), case
    if race == "NightElf":
        main = [station for station in visits if not station.endswith("-xp") and not station.startswith("05-d")]
        after_darnassus = main[main.index("01-6") + 1]
        if branch == "coast":
            assert after_darnassus == "02-10" and "01-9" not in main, case
        else:
            assert after_darnassus == "01-9", case
    assert any(station.startswith("05-d") for station in visits) == (mode != "solo"), case
    turned = {row[4] for row in log if row[3] == "turned"}
    if faction == "Horde":
        assert {"2621", "2622", "2784"} <= turned, case
        assert not {"2521", "3501"} & turned, case  # No rare drops supplied.
    return (*case, sum(int(row[12]) for row in stations), len(turned), peak)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lua", default=os.getenv("LUA", "lua5.1"))
    parser.add_argument("--output", type=Path, help="write the per-character CSV here")
    parser.add_argument("--full", action="store_true", help="replay every supported combination and mode")
    parser.add_argument("--list-cases", action="store_true", help="print the selected cases without running Lua")
    parser.add_argument("--events-dir", type=Path, help="retain per-character event TSVs in this directory")
    args = parser.parse_args()
    full = list(itineraries(json.loads((TESTS / "roster.json").read_text())))
    cases = full
    if not args.full:
        cases = [Case(*row) for row in json.loads((TESTS / "representative.json").read_text())]
        validate_representative(cases, full)
    if args.list_cases:
        print("\n".join("\t".join(case) for case in cases))
        return
    if args.events_dir:
        args.events_dir.mkdir(parents=True, exist_ok=True)
    work = nullcontext(args.events_dir) if args.events_dir else tempfile.TemporaryDirectory()
    with work as directory:
        with ThreadPoolExecutor(max_workers=4) as pool:
            rows = list(pool.map(lambda case: replay(case, args.lua, Path(directory)), cases))
    if args.output:
        with args.output.open("w", encoding="utf-8-sig", newline="") as stream:
            writer = csv.writer(stream)
            writer.writerow(("陣營", "種族", "職業", "分支", "情境", "另補XP", "已交任務數", "日誌峰值"))
            writer.writerows(rows)
    itinerary_count = len({case[:4] for case in cases})
    profile = "full" if args.full else "representative"
    print(f"Passed {len(rows)} replays across {itinerary_count} itineraries ({profile})")


if __name__ == "__main__":
    main()
