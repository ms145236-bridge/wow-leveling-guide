#!/usr/bin/env bash
# 發版（pack.yml）與 PR 檢查（pr-check.yml）共用的測試清單；新增測試只改這裡。
set -euo pipefail
cd "$(dirname "$0")/../.."
find addon/ShengLeveling -name '*.lua' -print0 | xargs -0 -n1 luac5.1 -p
lua5.1 tools/tests/map-order.lua
lua5.1 tools/tests/route-handoffs.lua
lua5.1 tools/tests/deadmines.lua
lua5.1 tools/tests/stockades.lua
lua5.1 tools/tests/alcaz-prison.lua
lua5.1 tools/tests/wetlands-dungeon.lua
lua5.1 tools/tests/gnomeregan.lua
lua5.1 tools/tests/scarlet-library.lua
lua5.1 tools/tests/auberdine-choice.lua
lua5.1 tools/tests/field-marshal.lua
lua5.1 tools/tests/record-timing.lua
python3 -B tools/tests/replay/test_selection.py
python3 tools/tests/replay/check.py
