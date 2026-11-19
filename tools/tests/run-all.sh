#!/usr/bin/env bash
# 發版（pack.yml）與 PR 檢查（pr-check.yml）共用的測試清單；新增測試只改這裡。
set -euo pipefail
cd "$(dirname "$0")/../.."
find addon/ShengLeveling -name '*.lua' -print0 | xargs -0 -n1 luac5.1 -p
lua5.1 tools/tests/map-order.lua
lua5.1 tools/tests/keep-quest.lua
lua5.1 tools/tests/mage-materials.lua
lua5.1 tools/tests/mage-captures.lua Alliance
lua5.1 tools/tests/mage-captures.lua Horde
lua5.1 tools/tests/mage-robe-alliance.lua
lua5.1 tools/tests/mage-silk-alliance.lua
lua5.1 tools/tests/stonewatch-objects.lua
lua5.1 tools/tests/loch-modan-parcel.lua
lua5.1 tools/tests/redridge-trophies.lua
lua5.1 tools/tests/ungoro-escort.lua
lua5.1 tools/tests/tooga-escort.lua
lua5.1 tools/tests/tooga-escort.lua legacy
lua5.1 tools/tests/tooga-horde.lua
lua5.1 tools/tests/hyjal-crate.lua
lua5.1 tools/tests/route-handoffs.lua
lua5.1 tools/tests/duskwood-comb.lua
lua5.1 tools/tests/merged-waypoints.lua
lua5.1 tools/tests/portable-map-pin.lua
lua5.1 tools/tests/thandol-chain.lua
lua5.1 tools/tests/deadmines.lua
lua5.1 tools/tests/brd-prison-visit.lua Alliance
lua5.1 tools/tests/brd-prison-visit.lua Horde
lua5.1 tools/tests/stockades.lua
lua5.1 tools/tests/alcaz-prison.lua
lua5.1 tools/tests/horde-dungeon-journal.lua
lua5.1 tools/tests/dungeon-outside-objectives.lua
lua5.1 tools/tests/zulfarrak-96775.lua
lua5.1 tools/tests/zulfarrak-alliance-handoffs.lua
lua5.1 tools/tests/wetlands-dungeon.lua
lua5.1 tools/tests/dungeon-prep-room.lua
lua5.1 tools/tests/dungeon-prep-pin.lua
lua5.1 tools/tests/mainline-prep-detail.lua
lua5.1 tools/tests/dungeon-intake-followup.lua Alliance
lua5.1 tools/tests/dungeon-intake-followup.lua Horde
lua5.1 tools/tests/wetlands-relic.lua
lua5.1 tools/tests/gnomeregan.lua
lua5.1 tools/tests/gnomeregan-punchcard.lua
lua5.1 tools/tests/gnomeregan-ring-return.lua
lua5.1 tools/tests/stratholme.lua
lua5.1 tools/tests/stratholme-alliance-followups.lua
lua5.1 tools/tests/stratholme-target.lua
lua5.1 tools/tests/post-turnin-detour.lua
lua5.1 tools/tests/scarlet-library.lua
lua5.1 tools/tests/auberdine-choice.lua
lua5.1 tools/tests/auberdine-corruption.lua
lua5.1 tools/tests/flint-second-visit.lua
lua5.1 tools/tests/blightcaller-survey.lua
lua5.1 tools/tests/field-marshal.lua
lua5.1 tools/tests/camping-any.lua
lua5.1 tools/tests/camping-auto.lua
lua5.1 tools/tests/macro-adopt.lua
lua5.1 tools/tests/carry-later.lua
lua5.1 tools/tests/fp-discover.lua
lua5.1 tools/tests/fp-step.lua
lua5.1 tools/tests/record-timing.lua
lua5.1 tools/tests/record-checks.lua
lua5.1 tools/tests/audit-1119.lua
lua5.1 tools/tests/class-pickups.lua
lua5.1 tools/tests/hunter-taming-catchup.lua
lua5.1 tools/tests/questiedb-guard.lua
lua5.1 tools/tests/replay/dungeon-entry-test.lua
python3 -B tools/tests/replay/test_selection.py
python3 -B tools/tests/replay/test_skips.py
python3 -B tools/tests/replay/test_punchcard.py
python3 tools/tests/replay/held_items.py
python3 tools/tests/replay/hyjal_crate.py
python3 tools/tests/replay/check.py
