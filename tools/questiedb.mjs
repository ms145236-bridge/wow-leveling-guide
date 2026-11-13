// 讀 QuestieDB baked 資料（QuestieDB_Forever.toc 的 metadata：Base64 → (zlib) → CBOR）。
// 只讀不寫。對照 QuestieDB/src/read/baked.lua、src/l10n/overlay.lua。
import { readFileSync } from "node:fs";
import { inflateSync } from "node:zlib";

const ADDONS = process.env.WOW_ADDONS || "C:/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns"; // 可用 WOW_ADDONS 指到別的安裝
const TOC = `${ADDONS}/QuestieDB/QuestieDB_Forever.toc`;
const AREA_MAP = `${ADDONS}/QuestieDB/support/Forever/Zones/areaIdToUiMapId.lua`;

function cbor(buf) {
  let i = 0;
  const len = (info) => {
    if (info < 24) return info;
    if (info === 24) return buf[i++];
    if (info === 25) { const v = buf.readUInt16BE(i); i += 2; return v; }
    if (info === 26) { const v = buf.readUInt32BE(i); i += 4; return v; }
    if (info === 27) { const v = Number(buf.readBigUInt64BE(i)); i += 8; return v; }
    if (info === 31) return -1;
    throw new Error("cbor: bad length " + info);
  };
  const half = (h) => {
    const e = (h >> 10) & 31, f = h & 1023, s = h & 32768 ? -1 : 1;
    if (e === 0) return s * 2 ** -14 * (f / 1024);
    if (e === 31) return f ? NaN : s * Infinity;
    return s * 2 ** (e - 15) * (1 + f / 1024);
  };
  const item = () => {
    const b = buf[i++], major = b >> 5, info = b & 31;
    if (major === 7) {
      if (info === 20) return false;
      if (info === 21) return true;
      if (info === 22 || info === 23) return null;
      if (info === 25) { const v = half(buf.readUInt16BE(i)); i += 2; return v; }
      if (info === 26) { const v = buf.readFloatBE(i); i += 4; return v; }
      if (info === 27) { const v = buf.readDoubleBE(i); i += 8; return v; }
      throw new Error("cbor: simple " + info);
    }
    const n = len(info);
    if (major === 0) return n;
    if (major === 1) return -1 - n;
    if (major === 2 || major === 3) {
      if (n < 0) { const parts = []; while (buf[i] !== 0xff) parts.push(item()); i++; return parts.join(""); }
      const s = buf.subarray(i, i + n); i += n;
      return s.toString("utf8");
    }
    if (major === 4) {
      const a = [];
      if (n < 0) { while (buf[i] !== 0xff) a.push(item()); i++; } else for (let k = 0; k < n; k++) a.push(item());
      return a;
    }
    if (major === 5) {
      const m = new Map();
      const pair = () => { const k = item(); m.set(k, item()); };
      if (n < 0) { while (buf[i] !== 0xff) pair(); i++; } else for (let k = 0; k < n; k++) pair();
      return m;
    }
    if (major === 6) return item(); // tag：直接取內容
    throw new Error("cbor: major " + major);
  };
  return item();
}

// Lua 式表：CBOR map 的整數鍵 1..n → 陣列（索引 0 = 第 1 個）；其他維持 Map
const get = (t, k) => (t instanceof Map ? t.get(k) : Array.isArray(t) ? t[k - 1] : undefined);
const list = (t) => (t instanceof Map ? [...t.values()] : Array.isArray(t) ? t : []);

export function openQuestieDB() {
  const meta = new Map();
  for (const line of readFileSync(TOC, "utf8").split(/\r?\n/)) {
    if (!line.startsWith("## X-")) continue;
    const c = line.indexOf(": ");
    if (c > 0) meta.set(line.slice(3, c), line.slice(c + 2));
  }
  const stored = (key) => {
    const v = meta.get(key);
    const m = v && v.match(/^~(\d+)~$/);
    if (!m) return v;
    let s = "";
    for (let k = 1; k <= +m[1]; k++) s += meta.get(`${key}-${k}`);
    return s;
  };
  const b64 = (s) => Buffer.from(s, "base64");
  const ids = (type) => cbor(inflateSync(b64(stored(`X-${type}-IDS`))));
  const l10n = (type, locale) => {
    const s = stored(`X-l10n-${locale}-${type}`);
    return s ? cbor(inflateSync(b64(s))) : null;
  };

  const areaToUi = new Map();
  for (const m of readFileSync(AREA_MAP, "utf8").matchAll(/\[(\d+)\]\s*=\s*(\d+)/g)) areaToUi.set(+m[1], +m[2]);

  const cache = { Quest: new Map(), Npc: new Map(), Object: new Map(), Item: new Map() };
  const names = {};
  const loadType = (type) => {
    if (names[type]) return names[type];
    const idList = list(ids(type));
    const pos = new Map(idList.map((id, k) => [id, k]));
    const cols = { zhTW: l10n(type, "zhTW"), zhCN: l10n(type, "zhCN") };
    names[type] = { idList, pos, cols };
    return names[type];
  };
  const localName = (type, id, locale) => {
    const t = loadType(type);
    const col = get(t.cols[locale], 1);
    const p = t.pos.get(id);
    return p === undefined || !col ? undefined : get(col, p + 1) ?? undefined;
  };
  const row = (type, id) => {
    if (cache[type].has(id)) return cache[type].get(id);
    const s = stored(`X-${type}-${id}-S`);
    const r = s ? cbor(b64(s)) : null;
    cache[type].set(id, r);
    return r;
  };
  const field = (type, id, f) => {
    const r = row(type, id);
    const v = get(r, f);
    if (v !== undefined) return v;
    const s = stored(`X-${type}-${id}-${f}`);
    return s ? cbor(b64(s)) : undefined;
  };

  const quest = (id) => {
    if (!row("Quest", id)) return null;
    const starts = field("Quest", id, 2), ends = field("Quest", id, 3);
    return {
      id,
      en: field("Quest", id, 1),
      zhTW: localName("Quest", id, "zhTW"),
      zhCN: localName("Quest", id, "zhCN"),
      obj: (() => { const t = loadType("Quest"); const c = get(t.cols.zhTW, 2); const p = t.pos.get(id); const v = c && p !== undefined ? get(c, p + 1) : undefined; return list(v ?? field("Quest", id, 8)); })(),
      reqLevel: field("Quest", id, 4) || 0,
      level: field("Quest", id, 5) || 0,
      races: field("Quest", id, 6) || 0,
      classes: field("Quest", id, 7) || 0,
      startNpcs: list(get(starts, 1)), startObjects: list(get(starts, 2)), startItems: list(get(starts, 3)),
      endNpcs: list(get(ends, 1)), endObjects: list(get(ends, 2)),
      preGroup: list(field("Quest", id, 12)), preSingle: list(field("Quest", id, 13)),
      exclusiveTo: list(field("Quest", id, 16)),
      sourceItem: field("Quest", id, 11) || 0,
      requiredSourceItems: list(field("Quest", id, 21)),
      objEn: list(field("Quest", id, 8)).filter((x) => typeof x === "string"), // enUS 目標文字（英文介面用）
      zoneOrSort: field("Quest", id, 17) || 0,
      next: field("Quest", id, 22) || 0,
    };
  };
  // spawns：{ [areaId] = {{x,y},...} } → [{ map(uiMapID), x, y }]
  const spawnsOf = (type, id) => {
    const sp = field(type, id, type === "Npc" ? 7 : 4);
    if (!(sp instanceof Map) && !Array.isArray(sp)) return [];
    const out = [];
    const entries = sp instanceof Map ? [...sp.entries()] : sp.map((v, k) => [k + 1, v]);
    for (const [area, pts] of entries) {
      const map = areaToUi.get(+area);
      for (const p of list(pts)) {
        const x = get(p, 1), y = get(p, 2);
        if (map && typeof x === "number" && x >= 0) out.push({ map, x, y });
      }
    }
    return out;
  };
  const npc = (id) => row("Npc", id) && {
    id, en: field("Npc", id, 1), zhTW: localName("Npc", id, "zhTW"), zhCN: localName("Npc", id, "zhCN"),
    spawns: spawnsOf("Npc", id),
  };
  const object = (id) => row("Object", id) && {
    id, en: field("Object", id, 1), zhTW: localName("Object", id, "zhTW"), spawns: spawnsOf("Object", id),
  };

  // 名稱 → 任務 ID 索引（enUS、zhTW、zhCN）
  let nameIndex;
  const norm = (s) => String(s || "").replace(/[\s「」『』"'’‘“”·・：:，,。.!！?？（）()\-]/g, "").toLowerCase();
  const questsByName = (name) => {
    if (!nameIndex) {
      nameIndex = new Map();
      const t = loadType("Quest");
      const add = (n, id) => { const k = norm(n); if (!k) return; if (!nameIndex.has(k)) nameIndex.set(k, []); nameIndex.get(k).push(id); };
      for (const [k, col] of [["zhTW", get(t.cols.zhTW, 1)], ["zhCN", get(t.cols.zhCN, 1)]]) {
        if (col) t.idList.forEach((id, p) => { const n = get(col, p + 1); if (n) add(n, id); });
      }
      for (const id of t.idList) add(field("Quest", id, 1), id);
    }
    return [...new Set(nameIndex.get(norm(name)) || [])];
  };

  // 任務要打的怪：[{ lvl, elite, kind: "kill" | "drop" }]（依 QuestieDB objectives 的順序：先怪物、後物品）
  const mobLevel = (id) => {
    const lo = field("Npc", id, 4), hi = field("Npc", id, 5);
    if (typeof lo !== "number") return null;
    const zh = localName("Npc", id, "zhTW");
    return { lvl: (lo + (typeof hi === "number" ? hi : lo)) / 2, elite: [1, 2].includes(field("Npc", id, 6)), name: zh || field("Npc", id, 1), en: field("Npc", id, 1), zhMissing: !zh };
  };
  const questMobs = (id) => {
    const obj = field("Quest", id, 10);
    const out = [];
    for (const c of list(get(obj, 1))) {
      const m = mobLevel(get(c, 1));
      out.push(m ? { ...m, kind: "kill", names: [m.name], namesEn: [m.en], zhMissing: m.zhMissing } : null);
    }
    // 物件目標（第 2 群）：遊戲內目標順序是 怪、物件、物品，留位置才對得上
    for (const o of list(get(obj, 2))) {
      const name = localName("Object", get(o, 1), "zhTW") || field("Object", get(o, 1), 1);
      out.push(name ? { kind: "object", objects: [name], objectsEn: [field("Object", get(o, 1), 1)].filter(Boolean) } : null);
    }
    for (const it of list(get(obj, 3))) {
      const drops = list(field("Item", get(it, 1), 2)).map(mobLevel).filter(Boolean);
      if (drops.length) {
        out.push({ lvl: drops.reduce((a, d) => a + d.lvl, 0) / drops.length, elite: drops.every((d) => d.elite), kind: "drop", names: drops.slice(0, 3).map((d) => d.name), namesEn: drops.slice(0, 3).map((d) => d.en), zhMissing: drops.slice(0, 3).some((d) => d.zhMissing) });
      } else {
        // 不是怪物掉的：看是不是地上的物件（箱子、植物…）
        const oids = list(field("Item", get(it, 1), 3));
        const objs = oids.map((o) => localName("Object", o, "zhTW") || field("Object", o, 1)).filter(Boolean);
        const objsEn = oids.map((o) => field("Object", o, 1)).filter(Boolean);
        out.push(objs.length ? { kind: "object", objects: [...new Set(objs)].slice(0, 3), objectsEn: [...new Set(objsEn)].slice(0, 3) } : null);
      }
    }
    return out;
  };

  // 繁中名 → 英文名（NPC、物品；英文介面用）。同名多筆取第一個有英文名的
  const enIndex = {};
  const enByZh = (type, zh) => {
    if (!enIndex[type]) {
      enIndex[type] = new Map();
      const t = loadType(type);
      for (const loc of ["zhTW", "zhCN"]) {
        const col = get(t.cols[loc], 1);
        if (col) t.idList.forEach((id, p) => { const n = get(col, p + 1); if (n && !enIndex[type].has(norm(n))) enIndex[type].set(norm(n), id); });
      }
    }
    const id = enIndex[type].get(norm(zh));
    return id === undefined ? undefined : field(type, id, 1);
  };
  const itemEn = (id) => field("Item", id, 1);
  return { quest, npc, object, questsByName, questMobs, allQuestIds: () => loadType("Quest").idList, norm, enByZh, itemEn };
}

// 一群點取最密集一群的中心（同地圖、距離 5 以內算一群）
export function clusterCenter(points) {
  if (!points.length) return null;
  let best = null;
  for (const p of points) {
    const near = points.filter((q) => q.map === p.map && Math.hypot(q.x - p.x, q.y - p.y) <= 5);
    if (!best || near.length > best.length) best = near;
  }
  const n = best.length;
  return { map: best[0].map, x: +(best.reduce((s, q) => s + q.x, 0) / n).toFixed(1), y: +(best.reduce((s, q) => s + q.y, 0) / n).toFixed(1) };
}

// 命令列：node questiedb.mjs <名稱或ID>...
if (process.argv[1] && process.argv[1].endsWith("questiedb.mjs")) {
  const db = openQuestieDB();
  for (const a of process.argv.slice(2)) {
    const idsFound = /^\d+$/.test(a) ? [+a] : db.questsByName(a);
    for (const id of idsFound) {
      const q = db.quest(id);
      if (!q) { console.log(a, "無資料"); continue; }
      const s = q.startNpcs[0] && db.npc(q.startNpcs[0]);
      const e = q.endNpcs[0] && db.npc(q.endNpcs[0]);
      console.log(JSON.stringify({ id, en: q.en, zhTW: q.zhTW, obj: q.obj, lvl: q.level, min: q.reqLevel, races: q.races, zone: q.zoneOrSort,
        pre: [...q.preGroup, ...q.preSingle], start: s && `${s.zhTW || s.en} ${JSON.stringify(clusterCenter(s.spawns))}`,
        end: e && `${e.zhTW || e.en} ${JSON.stringify(clusterCenter(e.spawns))}` }));
    }
  }
}
