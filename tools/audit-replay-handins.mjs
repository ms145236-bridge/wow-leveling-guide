import { execFileSync } from "node:child_process";
import { mkdirSync, readFileSync, writeFileSync } from "node:fs";
import { dirname, join, resolve } from "node:path";
import { fileURLToPath, pathToFileURL } from "node:url";
import { parseArgs } from "node:util";
import { openQuestieDB } from "./questiedb.mjs";

const root = dirname(dirname(fileURLToPath(import.meta.url)));
const groupNames = ["NPC", "物件", "物品", "聲望", "擊殺信用", "施法"];
const field = (table, index) => table instanceof Map ? table.get(index) : table?.[index - 1];
const values = table => table instanceof Map ? [...table.values()] : (Array.isArray(table) ? table : []);
const rows = text => text.trimEnd().split(/\r?\n/).filter(Boolean).map(line => line.split("\t"));

function loadObjectives(db, id) {
  const quest = db.quest(id);
  if (!quest) return { missing: true, materials: [], groups: [] };
  const raw = db.field("Quest", id, 10);
  const groups = groupNames.map((_, k) => values(field(raw, k + 1)));
  const materials = groups[2].map(tuple => field(tuple, 1));
  return {
    groups, materials,
    materialNames: materials.map(item => item + " " + (db.itemEn(item) ?? "")).join(" / "),
    source: quest.sourceItem,
    starts: quest.startItems,
    requiredStarts: quest.requiredSourceItems,
    text: quest.objEn.filter(Boolean).join(" "),
    extra: [9, 29].some(k => values(db.field("Quest", id, k)).length > 0),
  };
}

export function classify(objective, turn, previousPurchases, possibleHeld) {
  if (objective.missing) return "無資料庫記錄";
  const { groups, materials, source, starts, text, extra } = objective;
  const other = extra || groups.some((entries, i) => i !== 2 && entries.length > 0);
  if (materials.length && other) return "物品兼其他目標，逐項查";
  if (materials.length > 1) return "多種材料，逐物查";
  if (materials.length) {
    const item = materials[0];
    if (turn.length === 1 && turn[0].item === item) return "交件已有實物門檻，另核數量";
    if (source === item) return "接取配發同一物品，另核數量";
    if (previousPurchases.length) return "經過同物品採購站，未證實已買";
    if (possibleHeld.length) return "其他活躍任務已做同物品，未證實仍在袋";
    return "單種材料，核實來源與數量";
  }
  if (other) return "怪物、物件或特殊目標，查進度";
  if (starts.length) return "物品起任，查取得記錄";
  if (source) return "接取配發物品，核對交付對象";
  if (/\b(speak (to|with)|talk (to|with)|report (back )?to|return to|meet (up )?with)\b/i.test(text)
      && !/\b(bring|recover|collect|slay|destroy|defeat|kill|gather|rescue|escort|retrieve|purchase)\b/i.test(text)) {
    return "對話或回報文字，未見結構化目標";
  }
  return "需人工讀目標文字";
}

function routeSteps(lua, faction) {
  const output = execFileSync(lua, ["tools/audit-replay-steps.lua", faction], { cwd: root, encoding: "utf8" });
  const steps = new Map();
  for (const [station, index, action, q, item, count, ready, hold] of rows(output)) {
    const key = [station, action, q].join("/");
    if (!steps.has(key)) steps.set(key, []);
    steps.get(key).push({ index: +index, item: +item, count: +count, ready: +ready, hold: +hold });
  }
  return steps;
}

function summarizeGates(steps) {
  return steps.map(s => [s.item, s.count, s.ready, s.hold].join(",")).join("|");
}

// A new acceptance starts a fresh lifetime even when an earlier visit worked the same ID.
export function auditTrace(events, steps, lookup, remainingXP) {
  const active = new Map();
  const visited = new Set();
  const findings = [];
  for (const [station, lv, bar, event, rawID, name, , detail] of events) {
    visited.add(station);
    const id = Number(rawID);
    if (!id) continue;
    const state = active.get(id) ?? { station: "?", worked: false };
    if (event === "accepted") {
      active.set(id, { station, worked: false });
      continue;
    }
    if (event === "worked") {
      state.worked = true;
      active.set(id, state);
      continue;
    }
    if (event !== "turned") continue;
    active.delete(id);
    const nominal = Number(detail);
    if (state.worked || !(nominal > 0)) continue;
    const room = remainingXP.get(+lv);
    if (!Number.isFinite(room)) throw Error("Missing XP boundary for replay level " + lv);
    const xp = Math.min(nominal, Math.max(0, room - Number(bar)));
    const o = lookup(id);
    const turn = steps.get([station, "turnin", id].join("/")) ?? [];
    const pickup = steps.get([state.station, "accept", id].join("/")) ?? [];
    const purchases = [];
    const possibleHeld = [];
    for (const place of visited) {
      for (const buy of steps.get(place + "/buy/0") ?? []) {
        if (o.materials.includes(buy.item) && (place !== station || (turn.length === 1 && buy.index < turn[0].index))) {
          purchases.push(place + " " + buy.item + "×" + buy.count);
        }
      }
    }
    for (const [otherID, progress] of active) {
      if (!progress.worked) continue;
      for (const item of lookup(otherID).materials) {
        if (o.materials.includes(item)) possibleHeld.push(item + "@" + otherID);
      }
    }
    const kind = classify(o, turn, purchases, possibleHeld);
    findings.push({ id, name, accepted: state.station, station, lv, nominal, xp, kind, o,
      pickup: summarizeGates(pickup), turn: summarizeGates(turn),
      purchases: purchases.join("|"), possibleHeld: possibleHeld.join("|") });
  }
  return findings;
}

function writeTSV(path, header, data) {
  const clean = value => String(value ?? "").replace(/[\t\r\n]/g, " ");
  writeFileSync(path, "\uFEFF" + [header, ...data].map(row => row.map(clean).join("\t")).join("\n") + "\n");
}

function main() {
  const { values: opts, positionals } = parseArgs({
    options: { full: { type: "boolean" }, lua: { type: "string", default: process.env.LUA || "lua5.1" } },
    allowPositionals: true,
  });
  if (positionals.length !== 2) throw Error("Usage: node tools/audit-replay-handins.mjs EVENTS_DIR OUTPUT_DIR [--full] [--lua LUA]");
  const [eventsDir, outputDir] = positionals.map(p => resolve(p));
  const select = ["tools/tests/replay/check.py", "--list-cases"];
  if (opts.full) select.push("--full");
  const cases = rows(execFileSync("python3", select, { cwd: root, encoding: "utf8" }));
  const db = openQuestieDB();
  const cache = new Map();
  function lookup(id) {
    if (!cache.has(id)) cache.set(id, loadObjectives(db, id));
    return cache.get(id);
  }
  const xp = new Map([[60, 0]]);
  const xpTable = readFileSync(join(root, "route-alliance/xp-table.md"), "utf8");
  const levels = [...xpTable.matchAll(/^\| (\d+) \| (\d+) \|/gm)].reverse();
  for (const [, level, cost] of levels) {
    if (+level < 60) xp.set(+level, xp.get(+level + 1) + Number(cost));
  }
  const routes = new Map();
  const summary = new Map();
  const detailed = [];
  for (const entry of cases) {
    const [faction] = entry;
    if (!routes.has(faction)) routes.set(faction, routeSteps(opts.lua, faction));
    const character = entry.join("-");
    const text = readFileSync(join(eventsDir, character + ".tsv"), "utf8");
    for (const f of auditTrace(rows(text), routes.get(faction), lookup, xp)) {
      detailed.push([character, faction, f.id, f.name, f.accepted, f.station, f.lv, f.nominal,
        f.xp, f.kind, f.pickup, f.turn, f.purchases, f.possibleHeld]);
      const key = [faction, f.id, f.station, f.kind].join("/");
      if (!summary.has(key)) {
        const o = f.o;
        const targets = o.groups.map((g, i) => g.length ? groupNames[i] + " " + JSON.stringify(g,
          (_, value) => value instanceof Map ? Object.fromEntries(value) : value) : "").filter(Boolean);
        summary.set(key, { faction, f, paid: 0, capped: 0, maxXP: 0, targets: targets.join(" / ") });
      }
      const s = summary.get(key);
      if (f.xp) s.paid++; else s.capped++;
      s.maxXP = Math.max(s.maxXP, f.xp);
    }
  }
  mkdirSync(outputDir, { recursive: true });
  writeTSV(join(outputDir, "handin-events.tsv"),
    ["角色","陣營","任務","名稱","接取站","交件站","等級","名義XP","實得XP","分類","接取門檻","交件門檻","經過採購","同物品已做"], detailed);
  const groups = [...summary.values()].sort((a, b) => a.faction.localeCompare(b.faction) || a.f.id - b.f.id || a.f.station.localeCompare(b.f.station));
  writeTSV(join(outputDir, "handin-quests.tsv"),
    ["陣營","任務","名稱","交件站","分類","有實得次數","僅名義次數","最高實得XP","DB材料","接取配發物","道具起任","起任所需物","結構化目標","DB目標文字"],
    groups.map(({ faction, f, paid, capped, maxXP, targets }) => [faction, f.id, f.name, f.station, f.kind,
      paid, capped, maxXP, f.o.materialNames, f.o.source || "", f.o.starts, f.o.requiredStarts, targets, f.o.text]));
  console.log(`${cases.length} replays, ${detailed.length} hand-ins without a preceding worked event. Reports in ${outputDir}`);
}

if (process.argv[1] && pathToFileURL(resolve(process.argv[1])).href === import.meta.url) main();
