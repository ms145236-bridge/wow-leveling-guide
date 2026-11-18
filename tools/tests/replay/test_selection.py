"""Fast checks for representative replay coverage, without launching Lua."""
import copy
import json
import unittest

from check import Case, MODES, TESTS, itineraries, validate_representative


class ReplaySelectionTest(unittest.TestCase):
    def setUp(self):
        self.roster = json.loads((TESTS / "roster.json").read_text())
        self.full = list(itineraries(self.roster))
        self.selected = [Case(*row) for row in json.loads((TESTS / "representative.json").read_text())]

    def test_full_and_representative_are_legal(self):
        path_count = sum(
            len(classes) * (2 if race == "NightElf" else 1)
            for races in self.roster.values()
            for race, classes in races.items()
        )
        self.assertEqual(len(self.full), path_count * len(MODES))
        self.assertEqual(len(self.full), len(set(self.full)))
        validate_representative(self.selected, self.full)

    def test_rejects_duplicate_and_stale_combination(self):
        with self.assertRaisesRegex(ValueError, "duplicate"):
            validate_representative(self.selected + [self.selected[0]], self.full)
        illegal = Case("Alliance", "NightElf", "PALADIN", "default", "solo")
        with self.assertRaisesRegex(ValueError, "unsupported"):
            validate_representative(self.selected + [illegal], self.full)

    def test_detects_new_faction_class(self):
        expanded = copy.deepcopy(self.roster)
        expanded["Alliance"]["Human"].append("NEW_CLASS")
        with self.assertRaisesRegex(ValueError, "faction and class.*Alliance.*NEW_CLASS"):
            validate_representative(self.selected, list(itineraries(expanded)))

    def test_detects_new_race_and_keeps_skyborne_separate(self):
        expanded = copy.deepcopy(self.roster)
        expanded["Horde"]["NewRace"] = ["MAGE"]
        with self.assertRaisesRegex(ValueError, "native race and branch.*Horde.*NewRace"):
            validate_representative(self.selected, list(itineraries(expanded)))
        missing_alliance_skyborne = [
            case for case in self.selected
            if (case.faction, case.race) != ("Alliance", "Skyborne")
        ]
        with self.assertRaisesRegex(ValueError, "native race and branch.*Alliance.*Skyborne"):
            validate_representative(missing_alliance_skyborne, self.full)

    def test_detects_missing_night_elf_branch(self):
        no_coast = [
            case._replace(branch="default") if case.branch == "coast" else case
            for case in self.selected
        ]
        with self.assertRaisesRegex(ValueError, "native race and branch.*NightElf.*coast"):
            validate_representative(no_coast, self.full)

    def test_detects_missing_mode_in_one_faction(self):
        no_horde_party = [
            case._replace(mode="allparty") if (case.faction, case.mode) == ("Horde", "party") else case
            for case in self.selected
        ]
        with self.assertRaisesRegex(ValueError, "faction and mode.*Horde.*party"):
            validate_representative(no_horde_party, self.full)

    def test_detects_missing_named_solo_character(self):
        witness = Case("Alliance", "Human", "PRIEST", "default", "solo")
        other_mode = [case._replace(mode="party") if case == witness else case for case in self.selected]
        with self.assertRaisesRegex(ValueError, "solo witnesses.*Human.*PRIEST"):
            validate_representative(other_mode, self.full)


if __name__ == "__main__":
    unittest.main()
