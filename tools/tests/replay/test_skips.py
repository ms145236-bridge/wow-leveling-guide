"""Mandatory-step skip rules in check.py, on hand-written replay logs (no Lua)."""
import unittest

from check import mandatory_skips


def row(station, kind, quest, detail="", opt=""):
    return [station, "30", "0", kind, str(quest), "", "", detail, opt]


class MandatorySkips(unittest.TestCase):
    def test_prereq_dropped_from_route(self):
        # 95424 has no step at all for this character: 95183 can never appear.
        log = [row("03-24", "prereq", 95183, "95424")]
        self.assertEqual(mandatory_skips(log), {("prereq", "03-24", "95183")})

    def test_prereq_turned_in_later(self):
        log = [row("05-d15", "prereq", 2842, "2841"), row("05-d15", "accepted", 2841), row("05-d15", "turned", 2841)]
        self.assertEqual(mandatory_skips(log), {("prereq", "05-d15", "2842")})

    def test_prereq_optional_or_other_branch(self):
        for kind in ("optional-off", "not-applicable"):
            log = [row("02-8", kind, 640, opt="opt"), row("02-8", "prereq", 641, "640")]
            self.assertEqual(mandatory_skips(log), set(), kind)

    def test_prereq_any_of_one_present(self):
        log = [row("02-8", "optional-off", 934, opt="opt"), row("02-8", "prereq", 935, "934/7383")]
        self.assertEqual(mandatory_skips(log), set())

    def test_accepted_never_turned(self):
        log = [row("02-14", "accepted", 1920)]
        self.assertEqual(mandatory_skips(log), {("unturned", "02-14", "1920")})

    def test_low_with_catch_up(self):
        log = [row("02-14", "low", 1801, "30"), row("03-17", "accepted", 1801), row("03-17", "turned", 1801)]
        self.assertEqual(mandatory_skips(log), set())
        self.assertEqual(mandatory_skips(log[:1]), {("low", "02-14", "1801")})

    def test_optional_and_dungeon_difficulty(self):
        log = [row("02-13", "low", 1150, "31", opt="opt"), row("05-d6", "difficulty", 1014, "26 elite")]
        self.assertEqual(mandatory_skips(log), set())
        self.assertEqual(mandatory_skips([row("02-13", "difficulty", 1150, "31")]), {("difficulty", "02-13", "1150")})


if __name__ == "__main__":
    unittest.main()
