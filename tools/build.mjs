// 離線建置：route/*.md → addon/MetroGuide/Data/Route.lua + tools/unresolved.md
// 用法：node tools/build.mjs
// 缺任務 ID／座標時查 QuestieDB（zhTW、zhCN、enUS 名稱）。有「找不到／多個候選」時以結束碼 1 結束（輸出仍會寫出）。
import { readFileSync, writeFileSync, readdirSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { openQuestieDB, clusterCenter } from "./questiedb.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const ROUTE = process.env.ROUTE_DIR || join(ROOT, "route"); // 測試時可指到別的資料夾
const OUT = process.env.OUT_LUA || join(ROOT, "addon", "MetroGuide", "Data", "Route.lua");
const REPORT = process.env.OUT_REPORT || join(ROOT, "tools", "unresolved.md");

const HORDE = 8589934770n; // QuestieDB 的部落種族遮罩（含永恆新種族位元）
const CLASS = { 戰士: "WARRIOR", 獵人: "HUNTER", 薩滿: "SHAMAN", 薩滿祭司: "SHAMAN", 法師: "MAGE", 術士: "WARLOCK", 盜賊: "ROGUE", 德魯伊: "DRUID", 牧師: "PRIEST", 聖騎士: "PALADIN" };
const RACE = { 獸人: "Orc", 食人妖: "Troll", 牛頭人: "Tauren", 不死族: "Scourge", 亡靈: "Scourge", 被遺忘者: "Scourge", 血精靈: "BloodElf" };
const ZONE_MAP = { 杜洛塔: 1411, 莫高雷: 1412, 貧瘠之地: 1413, 提里斯法林地: 1420, 銀松森林: 1421, 石爪山脈: 1442, 梣谷: 1440, 灰谷: 1440, 千針石林: 1441, 希爾斯布萊德丘陵: 1424, 奧特蘭克山脈: 1416, 阿拉希高地: 1417, 塵泥沼澤: 1445, 荊棘谷: 1434, 淒涼之地: 1443, 菲拉斯: 1444, 塔納利斯: 1446, 辛特蘭: 1425, 悲傷沼澤: 1435, 荒蕪之地: 1418, 灼熱峽谷: 1427, 艾薩拉: 1447, 奧格瑪: 1454, 幽暗城: 1458, 雷霆崖: 1456 };
const VERB = { 接: "accept", 做: "do", 交: "turnin", 到: "goto", 鳥: "fp", 爐: "hearth", 飛: "fly", 船: "boat", 練: "level", 註: "note", 交通: "travel" };
// 行尾標籤：這些不顯示；其餘（可跳過、有隊伍再做…）顯示在步驟第 3 行
const HIDDEN_TAG = /^(QuestieDB|補充|影片|有前置|僅|非|說明|\d+\s*級起|接取等級|建議等級|可共享|不可共享|共享|前置[：:])/;
// 副本前置的標記：【接取等級 N】【建議等級 M】【可共享】／【不可共享】／【共享?】【前置：任務名 ID】
const dungeonTags = (tags) => {
  const out = {};
  for (const t of tags) {
    let m;
    if ((m = t.match(/^接取等級\s*(\d+)/))) out.pickLv = +m[1];
    else if ((m = t.match(/^建議等級\s*(\d+)/))) out.recLv = +m[1];
    else if (t === "可共享") out.share = 1;
    else if (t === "不可共享") out.share = 0;
    else if (/^共享[?？]$/.test(t)) out.share = 2;
    else if ((m = t.match(/^前置[：:]\s*(.+)$/))) out.preText = m[1].trim();
  }
  return out;
};

const db = openQuestieDB();
// 任務經驗（QuestieDB 的 QuestXP 表：[id] = {等級, 經驗}）
const XP = new Map();
for (const m of readFileSync("C:/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns/QuestieDB/support/Forever/QuestXP/xpDB-classic.lua", "utf8").matchAll(/\[(\d+)\] = \{(\d+), (\d+)\}/g)) XP.set(+m[1], +m[3]);
const classBlocks = [];
// 名稱整理：去掉引號類符號、<副標>、「物件／物品」前綴、前後空白，全形空白換半形
const cleanName = (n) => String(n || "").replace(/<[^>]*>/g, "").replace(/[『』「」《》“”"]/g, "").replace(/^(物件|物品)\s*/, "").replace(/　/g, " ").trim();
const nameIssues = []; // 名稱不一致（建置報告）
const dungeons = []; // 副本站：插在指定的站後面，引擎當成可選站
// 副本區域（QuestieDB support/Forever/Zones）：areaId → { name, alts }；instanceID → areaId
const ZONES = "C:/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns/QuestieDB/support/Forever/Zones/";
const DUNGEON_AREA = new Map();
for (const m of readFileSync(ZONES + "dungeons.lua", "utf8").matchAll(/\[(\d+)\]\s*=\s*\{"([^"]+)",(nil|\{[\d,]*\})/g)) {
  DUNGEON_AREA.set(+m[1], { name: m[2], alts: m[3] === "nil" ? [] : m[3].replace(/[{}]/g, "").split(",").filter(Boolean).map(Number) });
}
const CONST_NAME = (n) => n.toUpperCase().replace(/'/g, "").replace(/[^A-Z0-9]+/g, "_");
const INSTANCE_AREA = new Map();
for (const [, id, numericArea, namedArea] of readFileSync(ZONES + "instanceIdToAreaId.lua", "utf8").matchAll(/\[(\d+)\]\s*=\s*(?:(\d+)|ZoneDB\.zoneIDs\.([A-Z0-9_]+))/g)) {
  const area = numericArea ? +numericArea : [...DUNGEON_AREA.entries()].find(([, d]) => CONST_NAME(d.name) === namedArea)?.[0];
  if (DUNGEON_AREA.has(area)) INSTANCE_AREA.set(+id, area);
}
// 打怪經驗用：每個目標 { 怪物平均等級, 數量, 1＝殺／2＝掉落物, 1＝精英 }。
// 數量從目標文字依序抓「N個／只／根…」；抓到的比目標少時，其餘當 1（多半是指名的首領），完全沒數字用 6。
// 每個目標的怪物名稱（和 mob 同順序；選取目標／標記用）
const targetsOf = (q) => {
  const per = db.questMobs(q.id).map((m) => (m && m.names ? [...new Set(m.names.filter(Boolean).map(cleanName))] : []));
  for (const m of db.questMobs(q.id)) if (m && m.names && m.zhMissing) nameIssues.push(`- 任務 ${q.id}：目標怪 QuestieDB 沒有繁中名（${m.names.join("、")}）`);
  return per.some((n) => n.length) ? per : undefined;
};
const mobsOf = (q) => {
  const mobs = db.questMobs(q.id);
  if (!mobs.length) return undefined;
  const nums = [...q.obj.join(" ").matchAll(/(\d+)\s*[個只隻根張份塊件頭名條把顆片枚]/g)].map((m) => +m[1]);
  return mobs.map((m, k) => m
    ? [Math.round(m.lvl * 10) / 10, nums.length ? (nums[k] ?? 1) : 6, m.kind === "drop" ? 2 : 1, m.elite ? 1 : 0]
    : [0, 0, 1, 0]);
};
const issues = { hard: [], warn: [] };
const hard = (where, text) => issues.hard.push(`- ${where}：${text}`);
const warn = (where, text) => issues.warn.push(`- ${where}：${text}`);

// 「入室偷竊（Prison Break In）」→ { zh, en }
const splitName = (s) => {
  const m = s.trim().match(/^(.*?)\s*[（(]([^（）()]*)[）)]\s*$/);
  return m ? { zh: m[1].trim(), en: m[2].trim() } : { zh: s.trim(), en: "" };
};
const parseCoord = (s) => {
  const m = String(s || "").replace(/約/g, "").match(/(?:(\d{3,5})\s*[｜:：\s]\s*)?(\d{1,2}(?:\.\d+)?)\s*[,，]\s*(\d{1,2}(?:\.\d+)?)/);
  return m ? { map: m[1] ? +m[1] : undefined, x: +m[2], y: +m[3] } : null;
};
// 【僅獸人／食人妖】【非術士】→ when
const parseWhen = (tags) => {
  const when = {};
  const put = (key, v) => { (when[key] ||= []).includes(v) || when[key].push(v); };
  for (const tag of tags) {
    const m = tag.match(/^(僅|非)(.+)$/);
    const lv = tag.match(/^(\d+)\s*級起$/);
    if (lv) when.lvMin = +lv[1];
    if (!m) continue;
    for (const raw of m[2].split(/[／\/、,，]/).map((s) => s.trim()).filter(Boolean)) {
      if (raw === "部落") continue;
      const neg = m[1] === "非";
      if (CLASS[raw]) put(neg ? "notClass" : "class", CLASS[raw]);
      else put(neg ? "notRace" : "race", RACE[raw] || raw);
    }
  }
  return Object.keys(when).length ? when : undefined;
};
const horde = (q) => !q.races || (BigInt(q.races) & HORDE) !== 0n;
const near = (spawns, map) => clusterCenter(spawns.filter((p) => p.map === map)) || clusterCenter(spawns);

// ── 讀檔 ─────────────────────────────────────────────────────────────────────
const files = readdirSync(ROUTE).filter((f) => f.endsWith(".md")).sort((a, b) => (a.startsWith("_") - b.startsWith("_")) || a.localeCompare(b));
let stations = [];
for (const file of files) {
  const test = file.startsWith("_");
  const prefix = test ? "t" + (file.match(/\d+/)?.[0] ?? "") : file.match(/^\d+/)?.[0] ?? file.replace(/\.md$/, "");
  let st = null;
  readFileSync(join(ROUTE, file), "utf8").split(/\r?\n/).forEach((line, li) => {
    const where = `${file}:${li + 1}`;
    const h = line.match(/^##\s*第(\d+)站｜(.+?)[（(]\s*(\d+)\s*[–\-~－到]\s*(\d+)\s*[）)](?:｜影片\s*([\d:]+))?/);
    if (h) {
      st = { id: `${prefix}-${h[1]}`, name: h[2].trim(), lv: [+h[3], +h[4]], video: h[5], test, steps: [], tips: [], file, where };
      stations.push(st);
      return;
    }
    // 副本：## 副本｜名稱（建議等級 a–b）｜插入於 0X-第N站之後
    const dg = line.match(/^##\s*副本｜(.+?)[（(]\s*建議等級\s*(\d+)\s*[–\-~－到]\s*(\d+)\s*[）)]\s*｜\s*插入於\s*(\d+)\s*-\s*第(\d+)站之後/);
    if (dg) {
      st = { id: prefix + "-d" + (dungeons.length + 1), dungeon: true, after: dg[4] + "-" + dg[5], name: dg[1].replace(/\s*[（(][^（）()一-鿿]+[）)]/g, "").trim(), en: (dg[1].match(/[（(]([^（）()一-鿿]+)[）)]/) || [])[1], lv: [+dg[2], +dg[3]], steps: [], tips: [], file, where, phase: "pre" };
      dungeons.push(st);
      return;
    }
    // 職業任務：### 職業（可加種族）｜N 級｜第M站，底下照一般步驟寫；放進第M站，只給該職業、N 級起
    const ch = line.match(/^###\s*(.+?)｜\s*(\d+)\s*級\s*｜\s*第(\d+)站/);
    if (ch) {
      const when = { lvMin: +ch[2] };
      for (const [zh, tok] of Object.entries(CLASS)) if (ch[1].includes(zh) && !(when.class ||= []).includes(tok)) when.class.push(tok);
      for (const [zh, tok] of Object.entries(RACE)) if (ch[1].includes(zh) && !(when.race ||= []).includes(tok)) when.race.push(tok);
      if (/天裔/.test(ch[1])) (when.race ||= []).push("天裔");
      if (when.race && !when.race.length) delete when.race;
      if (!when.class?.length) warn(where, "職業任務標題找不到職業：" + ch[1]);
      st = { classBlock: true, target: `${prefix}-${ch[3]}`, when, steps: [], tips: [], where };
      classBlocks.push(st);
      return;
    }
    if (/^###\s/.test(line) && st && st.classBlock) { st = null; return; }
    if (/^##\s/.test(line)) { st = null; return; }
    if (!st) return;
    const bold = line.match(/^\s*\*\*(.+?)\*\*\s*$/);
    if (bold && st.steps.length) { st.steps.push({ t: "note", text: bold[1].trim(), where }); return; }
    // 說明｜…：接在上一步，滑過步驟時顯示（護送、稀有掉落、要組隊、限時、物品要在某處使用…）
    // 不帶「-」的「說明｜」接在上一步；「- 說明｜」是整站的說明（放進 tips）
    const desc = line.match(/^\s*說明｜(.*)$/);
    if (desc) { const last = st.steps[st.steps.length - 1]; if (last) last.desc = desc[1].trim(); return; }
    if (st.dungeon) {
      const ent = line.match(/^\s*-\s*入口[：:｜]\s*(.+)$/);
      if (ent) {
        const c = parseCoord(ent[1]);
        const zone = Object.keys(ZONE_MAP).find((z) => ent[1].includes(z));
        st.entrance = { text: ent[1].replace(/【[^】]*】/g, "").replace(/(^|\s)\d{3,5}\s+(?=約?\s*\d)/, "$1").replace(/\s+/g, " ").trim(), map: c?.map || (zone && ZONE_MAP[zone]), x: c?.x, y: c?.y };
        return;
      }
      // 前置接取路線：一行文字；其中「0X-第N站」或「第N站」當建議提早接的站
      const pk = line.match(/^\s*-\s*前置接取路線[｜：:]\s*(.+)$/);
      if (pk) {
        st.pickup = pk[1].replace(/【[^】]*】/g, "").trim();
        const at = pk[1].match(/(?:(\d+)\s*-\s*)?第(\d+)站/);
        if (at) st.pickAt = (at[1] || st.after.split("-")[0]) + "-" + at[2];
        return;
      }
      const iid = line.match(/^\s*-\s*副本\s*ID[｜：:]\s*(\d+)/);
      if (iid) { st.instance = +iid[1]; return; }
      const ph = line.match(/^\s*-?\s*(進本前要接|副本內|出本後交)/);
      if (ph) { st.phase = { 進本前要接: "pre", 副本內: "in", 出本後交: "post" }[ph[1]]; return; }
    }
    const meta = line.match(/^\s*-\s*(限定|二選一|地圖\s*ID|交通|取捨|提醒|未完|說明)｜(.*)$/);
    if (meta) {
      const [, key, val] = meta;
      const v = val.trim();
      if (key === "限定" && v !== "無") st.when = parseWhen([v]);
      else if (key === "二選一" && v !== "無") st.alt = v;
      else if (key.startsWith("地圖")) st.map = +v || undefined;
      else if (key === "未完") warn(`${st.id} ${st.name}`, `未完：${v}`);
      else if (key !== "限定" && key !== "二選一") st.tips.push({ k: key, text: v.replace(/【[^】]*】/g, "").trim() });
      return;
    }
    const sm = line.match(/^\s*(?:\d+\s*[.、)]\s*|[-*]\s*)?(交通|接|做|交|到|鳥|爐|飛|船|練|註)｜(.*)$/);
    if (!sm) return;
    const tags = [...sm[2].matchAll(/【([^】]*)】/g)].map((m) => m[1]);
    const body = sm[2].replace(/【[^】]*】/g, "").trim();
    const keep = /★/.test(body);
    const f = body.replace(/★/g, "").split("｜").map((s) => s.trim());
    const step = { verb: sm[1], t: VERB[sm[1]], where, when: parseWhen(tags), keep, video: tags.includes("影片") || undefined,
      tag: tags.filter((t) => !HIDDEN_TAG.test(t)).join("・") || undefined, opt: tags.includes("可跳過") || undefined,
      desc: tags.filter((t) => /^說明[：:]/.test(t)).map((t) => t.replace(/^說明[：:]\s*/, "")).join("；") || undefined };
    if (step.t === "accept" || step.t === "turnin" || step.t === "do") {
      Object.assign(step, splitName(f[0]));
      if (/^[?？]?$/.test(step.zh)) step.zh = ""; // 中文名未知：用 QuestieDB 的 zhTW，再不行用英文名
      const hasId = /^(\d+|\?|？|)$/.test(f[1] ?? "");
      const rest = hasId ? f.slice(2) : f.slice(1);
      step.id = hasId && /^\d+$/.test(f[1]) ? +f[1] : undefined;
      if (step.t === "do") {
        step.hint = rest[0];
        step.coord = parseCoord(rest[1]);
        step.more = String(rest[1] || "").split("／").slice(1).map(parseCoord).filter(Boolean); // 其他怪點
      }
      else { step.npc = rest[0] && !/^[?？]$/.test(rest[0]) ? rest[0] : undefined; step.coord = parseCoord(rest[1]); }
    } else if (step.t === "goto") { step.text = f[0]; step.coord = parseCoord(f[1]); }
    else if (step.t === "fp") { step.node = f[0]; step.coord = parseCoord(f[1]); }
    else if (step.t === "hearth") step.bind = f[0];
    else if (step.t === "fly") step.to = f[0];
    else if (step.t === "boat") { step.to = f[0]; step.from = f[1]; }
    else if (step.t === "level") step.lv = +f[0];
    else if (step.t === "note") step.text = f[0];
    else if (step.t === "travel") { step.text = f.join("｜"); step.coord = parseCoord(step.text); }
    if (st.dungeon) Object.assign(step, { ph: st.phase }, dungeonTags(tags));
    st.steps.push(step);
  });
}

const CLASS_BIT = { 1: "WARRIOR", 2: "PALADIN", 3: "HUNTER", 4: "ROGUE", 5: "PRIEST", 7: "SHAMAN", 8: "MAGE", 9: "WARLOCK", 11: "DRUID" };
const classWhen = (mask) => {
  if (!mask) return undefined;
  const cls = Object.entries(CLASS_BIT).filter(([id]) => Math.floor(mask / 2 ** (+id - 1)) % 2 === 1).map(([, t]) => t);
  return cls.length && cls.length < Object.keys(CLASS_BIT).length ? { class: cls } : undefined;
};

// 副本站：接 → 前往入口 → 副本內 → 出本後交，插在指定站的後面
for (const d of dungeons) {
  const at = stations.findIndex((x) => x.id === d.after);
  if (at < 0) { hard(d.where, "副本指定的站不存在：" + d.after); continue; }
  if (!d.entrance?.map) warn(d.where, "副本「" + d.name + "」沒有入口座標或地圖");
  d.map = d.entrance?.map;
  // 副本區域：指定的 instanceID，否則看任務的 zoneOrSort
  let area = d.instance && INSTANCE_AREA.get(d.instance);
  if (!area) {
    const count = new Map();
    for (const x of d.steps) {
      const q = x.id && db.quest(x.id);
      if (!q) continue;
      for (const [aid, info] of DUNGEON_AREA) if (q.zoneOrSort === aid || info.alts.includes(q.zoneOrSort)) count.set(aid, (count.get(aid) || 0) + 1);
    }
    area = [...count.entries()].sort((a, b) => b[1] - a[1])[0]?.[0];
  }
  const instances = [...INSTANCE_AREA.entries()].filter(([, a]) => a === area).map(([i]) => i);
  if (d.instance && !instances.includes(d.instance)) instances.push(d.instance);
  if (instances.length) d.inst = instances;
  if (area) {
    const info = DUNGEON_AREA.get(area);
    // 這個副本區域的所有部落任務（在副本裡只顯示日誌中屬於這裡的任務）
    const zones = new Set([area, ...info.alts]);
    d.dq = db.allQuestIds().filter((id) => { const q = db.quest(id); return q && zones.has(q.zoneOrSort) && horde(q); });
  }
  if (!d.inst) warn(d.where, "副本「" + d.name + "」缺副本 ID（可加「- 副本ID｜N」）");
  // 沒寫地圖的座標：前置／交任務通常在插入點那站的區域，用那站的地圖（不是副本入口的地圖）
  for (const x of d.steps) if (x.coord && !x.coord.map) x.coord.map = stations[at].map;
  if (!d.pickAt) d.pickAt = d.after;
  const pick = (ph) => d.steps.filter((x) => (x.ph || "pre") === ph);
  const go = d.entrance ? [{ t: "travel", text: "前往 " + d.name + " 入口", coord: d.entrance.x ? { map: d.entrance.map, x: d.entrance.x, y: d.entrance.y } : undefined, where: d.where }] : [];
  for (const x of d.steps) {
    const m = x.t === "goto" && /確認/.test(x.text || "") && (x.text || "").match(/(?<![\d.])(\d{3,6})(?![\d.,])/);
    if (m && db.quest(+m[1])) {
      const q = db.quest(+m[1]);
      const where = (x.text.match(/依(.+?)段/) || x.text.match(/詳見(.+?)[。；，]/) || [])[1];
      Object.assign(x, { t: "need", id: +m[1], zh: q.zhTW || q.en, text: "前置：" + (q.zhTW || q.en) + (where ? "（在" + where.replace(/[。；，]$/, "") + (/段$/.test(where) ? "" : "段") + "接）" : ""), coord: undefined });
    }
  }
  d.steps = [...pick("pre"), ...go, ...pick("in"), ...pick("post")];
  // 前置鏈：每個「進本前要接」任務的前置（QuestieDB，遞迴），路線上沒列的補成 接／做／交，排在它前面
  const listed = new Set();
  for (const y of d.steps) if (y.id) listed.add(y.id); // 只看這個副本自己列的（主線上有的也照補，副本流程才完整）
  const added = [];
  const chainSteps = (qid, seen) => {
    const q = db.quest(qid);
    if (!q) return [];
    const pres = [...q.preGroup];
    const single = q.preSingle.map((p) => db.quest(p)).find((p) => p && horde(p));
    if (single && !q.preSingle.some((p) => listed.has(p))) pres.push(single.id);
    let out = [];
    for (const p of pres) {
      if (seen.has(p) || listed.has(p)) continue;
      const pq = db.quest(p);
      if (!pq || !horde(pq)) continue;
      seen.add(p);
      out = out.concat(chainSteps(p, seen));
      const when = classWhen(pq.classes);
      const base = { id: p, zh: pq.zhTW || pq.en, en: pq.en, ph: "pre", tag: "副本前置鏈", chainOf: qid, where: d.where, when };
      out.push({ ...base, t: "accept", verb: "接" });
      if (db.questMobs(p).length) out.push({ ...base, t: "do", verb: "做", hint: pq.obj.filter(Boolean).join(" ") });
      out.push({ ...base, t: "turnin", verb: "交" });
      listed.add(p);
      added.push(p);
    }
    return out;
  };
  const withChain = [];
  for (const x of d.steps) {
    if (x.ph === "pre" && x.t === "accept" && x.id) withChain.push(...chainSteps(x.id, new Set()));
    withChain.push(x);
  }
  d.steps = withChain;
  d.chainAdded = added;
  stations.splice(at + 1, 0, d);
}

// 職業任務併進指定的站：排在站尾的交通步驟前面
for (const blk of classBlocks) {
  const target = stations.find((s) => s.id === blk.target);
  if (!target) { hard(blk.where, "職業任務指定的站不存在：" + blk.target); continue; }
  for (const step of blk.steps) step.when = { ...blk.when, ...(step.when || {}) };
  let at = target.steps.length;
  while (at > 0 && ["travel", "note"].includes(target.steps[at - 1].t)) at--;
  target.steps.splice(at, 0, ...blk.steps);
}

// 測試站：和正式站等級重疊就略過
const real = stations.filter((s) => !s.test);
stations = stations.filter((s) => !s.test || !real.some((r) => r.lv[0] < s.lv[1] && s.lv[0] < r.lv[1]));
for (const s of stations.filter((s) => !s.steps.length)) warn(`${s.id} ${s.name}`, "沒有步驟，未放進插件");
stations = stations.filter((s) => s.steps.length);

// ── 解析任務 ID 與座標 ───────────────────────────────────────────────────────
const quests = new Map(); // id → 輸出欄位
const used = new Set(); // `${t}:${id}`
const lastByName = new Map(); // 名稱 → 最近接的任務 ID
for (const st of stations) {
  st.map ||= ZONE_MAP[st.name.split(/[・·]/)[0]];
  for (const step of st.steps) {
    if (!["accept", "do", "turnin"].includes(step.t)) {
      if (step.coord) step.coord.map ||= st.map;
      continue;
    }
    for (const p of step.more || []) p.map ||= st.map;
    const at = `${step.where} ${step.verb}｜${step.zh}`;
    let id = step.id;
    if (id) {
      const q = db.quest(id);
      if (!q) warn(at, `ID ${id} 不在 QuestieDB（永恆專屬？）`);
      else if (![q.zhTW, q.zhCN, q.en].some((n) => db.norm(n) === db.norm(step.zh) || (step.en && db.norm(n) === db.norm(step.en))))
        warn(at, `ID ${id} 的名稱是「${q.zhTW || q.en}」`);
    } else {
      const byName = (step.zh && lastByName.get(db.norm(step.zh))) || (step.en && lastByName.get(db.norm(step.en)));
      if (step.t !== "accept" && byName && !used.has(`${step.t}:${byName}`)) id = byName;
      else {
        let cands = [...new Set([...db.questsByName(step.zh), ...(step.en ? db.questsByName(step.en) : [])])]
          .map((cid) => db.quest(cid)).filter((q) => q && horde(q) && !used.has(`${step.t}:${q.id}`));
        const narrow = (fn) => { const n = cands.filter(fn); if (n.length) cands = n; };
        narrow((q) => q.level >= st.lv[0] - 5 && q.level <= st.lv[1] + 5);
        if (step.npc) {
          const npcIds = (q) => (step.t === "accept" ? q.startNpcs : q.endNpcs);
          narrow((q) => npcIds(q).some((n) => { const r = db.npc(n); return r && [r.zhTW, r.zhCN, r.en].some((x) => db.norm(x) === db.norm(step.npc)); }));
        }
        const inRoute = (q) => [...q.preGroup, ...q.preSingle].some((p) => quests.has(p));
        narrow((q) => inRoute(q) || ![...q.preGroup, ...q.preSingle].some((p) => cands.some((c) => c.id === p)));
        cands.sort((a, b) => a.level - b.level || a.id - b.id);
        if (!cands.length) { hard(at, "QuestieDB 找不到這個任務"); continue; }
        id = cands[0].id;
        if (cands.length > 1) hard(at, `多個候選 ${cands.map((c) => c.id).join(", ")}，暫用 ${id}（可在檔案中直接寫 ID）`);
        else warn(at, `補上 ID ${id}`);
      }
    }
    step.id = id;
    used.add(`${step.t}:${id}`);
    if (step.t === "accept") { if (step.zh) lastByName.set(db.norm(step.zh), id); if (step.en) lastByName.set(db.norm(step.en), id); }
    const q = db.quest(id);
    if (!quests.has(id)) {
      quests.set(id, q
        ? { races: q.races && BigInt(q.races) !== HORDE ? q.races : undefined, xp: XP.get(id), mob: mobsOf(q), tgo: targetsOf(q),
            d: q.obj.filter(Boolean).join("\n") || undefined,
            n: step.zh || q.zhTW || step.en || q.en, lvl: q.level, min: q.reqLevel, pg: q.preGroup, ps: q.preSingle, ex: q.exclusiveTo, next: q.next, st: st.id }
        : { n: step.zh || step.en, st: st.id });
    }
    if (step.keep) quests.get(id).keep = true;
    if (step.t === "do" || !q) { if (step.coord) step.coord.map ||= st.map; continue; }
    // 接/交：NPC 名與座標
    const npcIds = step.t === "accept" ? q.startNpcs : q.endNpcs;
    const objIds = step.t === "accept" ? q.startObjects : q.endObjects;
    const npcs = npcIds.map((n) => db.npc(n)).filter(Boolean);
    const namedNpc = step.npc && npcs.find((npc) => [npc.zhTW, npc.en].some((name) => name && db.norm(cleanName(name)) === db.norm(cleanName(step.npc))));
    const giver = namedNpc || npcs[0] || objIds.map((o) => db.object(o)).find(Boolean);
    if (!step.npc && giver) step.npc = giver.zhTW || giver.en;
    const isNpc = npcs.length > 0;
    if (isNpc && giver) {
      const dbName = giver.zhTW ? cleanName(giver.zhTW) : null;
      if (dbName) {
        step.tgt = dbName;
        if (step.npc && cleanName(step.npc) === dbName) step.npc = dbName; // 只差裝飾（引號等）→ 用遊戲名
        else if (step.npc && cleanName(step.npc) !== dbName) nameIssues.push(`- ${at}：路線寫「${step.npc}」，QuestieDB 是「${dbName}」`);
      } else {
        step.tgt = cleanName(!step.npc || /^[?？]/.test(step.npc) ? giver.en : step.npc);
        nameIssues.push(`- ${at}：QuestieDB 沒有繁中名（${giver.en}），用「${step.tgt}」`);
      }
    }
    const dbAt = giver && near(giver.spawns, step.coord?.map || st.map);
    if (step.coord) {
      step.coord.map ||= st.map;
      if (dbAt && dbAt.map === step.coord.map && Math.hypot(dbAt.x - step.coord.x, dbAt.y - step.coord.y) > 8)
        warn(at, `座標 ${step.coord.x},${step.coord.y} 與 QuestieDB（${dbAt.x},${dbAt.y}）差距大`);
    } else if (dbAt) step.coord = dbAt;
    else if (step.t !== "do") warn(at, "缺座標（QuestieDB 也沒有）");
  }
  const noCoord = st.steps.filter((s) => s.t === "do" && !s.coord).length;
  if (noCoord) warn(`${st.id} ${st.name}`, `${noCoord} 個「做」步驟沒有座標（不會出現箭頭）`);
  if (!st.map) hard(`${st.id} ${st.name}`, "沒有地圖 ID");
}

// 副本前置鏈報告
const chainReport = [];
for (const d of dungeons) {
  const n = d.steps.filter((x) => x.tag === "副本前置鏈").length;
  const noCoord = d.steps.filter((x) => x.tag === "副本前置鏈" && x.t !== "do" && !x.coord).map((x) => `${x.verb}｜${x.zh}（${x.id}）`);
  chainReport.push(`- ${d.name}：補了 ${n} 步（${(d.chainAdded || []).length} 個任務）${noCoord.length ? "；缺座標：" + noCoord.join("、") : ""}`);
}

// chain：後面站的任務以它為前置／後續
const order = new Map(stations.map((s, i) => [s.id, i]));
for (const [id, q] of quests) {
  const fol = [...quests.entries()].filter(([oid, o]) => oid !== id && ([...(o.pg || []), ...(o.ps || [])].includes(id) || q.next === oid)).map(([oid]) => oid);
  q.fol = fol.length ? fol : undefined;
  q.chain = [...quests.entries()].some(([oid, o]) => oid !== id && order.get(o.st) > order.get(q.st) && ([...(o.pg || []), ...(o.ps || [])].includes(id) || q.next === oid)) || undefined;
}

// 遊戲 zhTW 字型缺的字：・（U+30FB）→ 空白，彎引號 → ASCII
const idStats = new Map(); // 檔案 → 換掉的裸 ID 數
let idFile = "";
const MAP_IDS = new Set(Object.values(ZONE_MAP).concat([1458, 1454, 1456, 2521, 2548]));
const replaceIds = (text) => text.replace(/(?<![\d.\w])(\d{3,6})(?![\d.,]|\s*[個隻只根張份塊件頭名條把顆片枚級%]|\s+\d+[.,]\d)/g, (all, num, at, whole) => {
  const id = +num;
  if (MAP_IDS.has(id)) return all;
  const q = db.quest(id);
  if (!q) return all;
  const name = q.zhTW || q.en;
  idStats.set(idFile, (idStats.get(idFile) || 0) + 1);
  const before = whole.slice(0, at).replace(/[\s（(「]+$/, "");
  const after = whole.slice(at + num.length).replace(/^[\s（(「]+/, "");
  const sample = idFile + "：…" + whole.slice(Math.max(0, at - 12), at + num.length + 4) + "… → " + name;
  if (idSamples.length < 40 && !idSamples.includes(sample)) idSamples.push(sample);
  return before.endsWith(name) || after.startsWith(name) ? "" : name; // 名字已寫在 ID 前或後 → 只拿掉 ID
}).replace(/(?<![\d.])(\d{4})\s+(?=約?\s*\d{1,2}(?:\.\d+)?\s*[,，])/g, (all, num) => (MAP_IDS.has(+num) ? "" : all)) // 座標前的地圖 ID 不顯示
  .replace(/\s+([）)，。；])/g, "$1").replace(/（\s*）|\(\s*\)/g, "").replace(/\s+$/, "");
const idSamples = [];
const safeText = (s) => s.replace(/\s*・\s*/g, " ").replace(/[’‘]/g, "'").replace(/[“”]/g, '"').replace(/[―–]/g, "-");

// ── 輸出 Lua ────────────────────────────────────────────────────────────────
const lua = (v, ind = "") => {
  if (v === undefined || v === null) return "nil";
  if (typeof v === "boolean" || typeof v === "number") return String(v);
  if (typeof v === "string") return JSON.stringify(safeText(replaceIds(v)));
  if (Array.isArray(v)) return "{" + v.map((x) => lua(x, ind)).join(", ") + "}";
  const entries = Object.entries(v).filter(([, x]) => x !== undefined && !(Array.isArray(x) && !x.length));
  return "{" + entries.map(([k, x]) => `${/^[A-Za-z_]\w*$/.test(k) ? k : `[${JSON.stringify(k)}]`}=${lua(x, ind)}`).join(", ") + "}";
};
// 步驟條件：和站相同的種族限定拿掉（起點路線可給別族走，種族任務另由 races 遮罩過濾）
const stepWhen = (w, sw) => {
  if (!w) return undefined;
  const out = { ...w };
  if (sw?.race && JSON.stringify(out.race) === JSON.stringify(sw.race)) delete out.race;
  for (const k of Object.keys(out)) if (sw && JSON.stringify(out[k]) === JSON.stringify(sw[k]) && k !== "race") delete out[k];
  return Object.keys(out).length ? out : undefined;
};
const stepOut = (s, st) => ({
  t: s.t, q: s.t === "need" || s.t === "accept" || s.t === "do" || s.t === "turnin" ? s.id : undefined, ph: s.ph, pickLv: s.pickLv, recLv: s.recLv, share: s.share, preText: s.preText, opt: s.opt, desc: s.desc, tag: s.tag, npc: s.npc, tgt: s.tgt, hint: s.hint, text: s.text, node: s.node, bind: s.bind, to: s.to, from: s.from, lv: s.lv,
  map: s.coord?.map, x: s.coord?.x, y: s.coord?.y, more: s.more?.length ? s.more.map((p) => [p.map, p.x, p.y]) : undefined, when: stepWhen(s.when, st.when), video: s.video,
});
let out = `-- 由 tools/build.mjs 產生，勿手改。來源：route/*.md\nlocal _, MG = ...\nMG.Route = {\n  built = ${JSON.stringify(new Date().toISOString().slice(0, 16).replace("T", " "))},\n  stations = {\n`;
for (const s of stations) {
  idFile = s.file;
  const start = s.when?.race && s.lv[0] <= 12 ? s.when.race.join("/") : undefined;
  out += `    { id=${lua(s.id)}, start=${lua(start)}, name=${lua(s.name)}, map=${lua(s.map)}, lv=${lua(s.lv)}, video=${lua(s.video)}, test=${lua(s.test || undefined)}, alt=${lua(s.alt)}, when=${lua(s.when)}, tips=${lua(s.tips)}, dungeon=${lua(s.dungeon)}, after=${lua(s.after)}, entrance=${lua(s.entrance?.text)}, pickup=${lua(s.pickup)}, pickAt=${lua(s.pickAt)}, inst=${lua(s.inst)}, dq=${lua(s.dq)},\n      steps = {\n`;
  for (const step of s.steps) if (step.t !== "accept" && step.t !== "do" && step.t !== "turnin" || step.id) out += `        ${lua(stepOut(step, s))},\n`;
  out += `      } },\n`;
}
idFile = "任務表";
out += `  },\n  quests = {\n`;
for (const [id, q] of [...quests.entries()].sort((a, b) => a[0] - b[0])) {
  const { st, next, ...rest } = q;
  out += `    [${id}] = ${lua(rest)},\n`;
}
out += `  },\n}\n`;
writeFileSync(OUT, out);

const report = `# 建置報告（${new Date().toISOString().slice(0, 16).replace("T", " ")}）\n\n來源：${files.join("、")}\n站數：${stations.length}　任務數：${quests.size}\n\n## 需要處理（${issues.hard.length}）\n\n${issues.hard.join("\n") || "無"}\n\n## 提醒（${issues.warn.length}）\n\n${issues.warn.join("\n") || "無"}\n\n## 副本前置鏈\n\n${chainReport.join("\n") || "無"}\n\n## 裸任務 ID 換成任務名（前 40 例）\n\n${idSamples.map((x) => "- " + x).join("\n") || "無"}\n\n## 名稱不一致（${nameIssues.length}）\n\n${nameIssues.join("\n") || "無"}\n`;
writeFileSync(REPORT, report);
console.log(`站 ${stations.length}、任務 ${quests.size}、需要處理 ${issues.hard.length}、提醒 ${issues.warn.length}、名稱不一致 ${nameIssues.length}`);
console.log("裸任務 ID 換成任務名：" + ([...idStats.entries()].map(([k, v]) => k + " " + v).join("、") || "0"));
console.log(`→ ${OUT}\n→ ${REPORT}`);
process.exitCode = issues.hard.length ? 1 : 0;
