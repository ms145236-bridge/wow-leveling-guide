// TUGs Guidelime（永恆版）聯盟檔 → route-alliance/*.md 骨架
// 用法：node tools/import-tugs.mjs <TUGs Alliance 資料夾>
// 只取任務順序、ID、職業／種族限制與可跳過旗標；步驟文字全部由 QuestieDB 資料重寫（TUGs 原文不搬）。
// 不認得的自由文字列到 <輸出>/_import-notes.txt 供人工檢查（預設輸出 route-alliance/）。
import { readFileSync, writeFileSync, readdirSync, mkdirSync, copyFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { openQuestieDB, clusterCenter } from "./questiedb.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
const SRC = process.argv[2];
if (!SRC) throw new Error("用法：node tools/import-tugs.mjs <TUGs Alliance 資料夾>");
const OUT = process.env.OUT_DIR || join(ROOT, "route-alliance");
const NOTES_OUT = process.env.NOTES_OUT || join(OUT, "_import-notes.txt");
const ZONES = "C:/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns/QuestieDB/support/Forever/Zones/";
const db = openQuestieDB();

// ── 地圖 ─────────────────────────────────────────────────────────────────────
const ZH = { 1414: "卡林多", 1415: "東部王國", 1459: "奧特蘭克山谷", 1460: "戰歌峽谷", 1461: "阿拉希盆地", 1411: "杜洛塔", 1412: "莫高雷", 1413: "貧瘠之地", 1416: "奧特蘭克山脈", 1417: "阿拉希高地", 1418: "荒蕪之地", 1419: "詛咒之地", 1420: "提里斯法林地",
  1421: "銀松森林", 1422: "西瘟疫之地", 1423: "東瘟疫之地", 1424: "希爾斯布萊德丘陵", 1425: "辛特蘭", 1426: "丹莫洛", 1427: "灼熱峽谷", 1428: "燃燒平原", 1429: "艾爾文森林",
  1430: "逆風小徑", 1431: "暮色森林", 1432: "洛克莫丹", 1433: "赤脊山", 1434: "荊棘谷", 1435: "悲傷沼澤", 1436: "西部荒野", 1437: "濕地", 1438: "泰達希爾", 1439: "黑海岸",
  1440: "梣谷", 1441: "千針石林", 1442: "石爪山脈", 1443: "淒涼之地", 1444: "菲拉斯", 1445: "塵泥沼澤", 1446: "塔納利斯", 1447: "艾薩拉", 1448: "費伍德森林", 1449: "安戈洛環形山",
  1450: "月光林地", 1451: "希利蘇斯", 1452: "冬泉谷", 1453: "暴風城", 1454: "奧格瑪", 1455: "鐵爐堡", 1456: "雷霆崖", 1457: "達納蘇斯", 1458: "幽暗城", 2521: "微風島", 2548: "大河林地" };
const EN_MAP = { "Elwynn Forest": 1429, "Dun Morogh": 1426, Teldrassil: 1438, Darkshore: 1439, "Loch Modan": 1432, Westfall: 1436, "Redridge Mountains": 1433, Redridge: 1433,
  Duskwood: 1431, Wetlands: 1437, Ashenvale: 1440, "Stormwind City": 1453, Stormwind: 1453, Ironforge: 1455, IF: 1455, Darnassus: 1457, "The Barrens": 1413, "Stranglethorn Vale": 1434,
  "Arathi Highlands": 1417, "Dustwallow Marsh": 1445, "Duskwallow Marsh": 1445, Badlands: 1418, Tanaris: 1446, Feralas: 1444, "The Hinterlands": 1425, "Searing Gorge": 1427,
  "Un'Goro Crater": 1449, "Un'Goro": 1449, Felwood: 1448, "Burning Steppes": 1428, "Western Plaguelands": 1422, "Eastern Plaguelands": 1423, Winterspring: 1452,
  "Hillsbrad Foothills": 1424, "Alterac Mountains": 1416, Desolace: 1443, "Stonetalon Mountains": 1442, "Thousand Needles": 1441, "Swamp of Sorrows": 1435, "Blasted Lands": 1419,
  Azshara: 1447, Moonglade: 1450, Silithus: 1451, "Zephras Isle": 2521, "Rut'Theran": 1438, "Rut'theran Village": 1438, "Ruth'Theran": 1438, Auberdine: 1439, Astranaar: 1440,
  Darkshire: 1431, "Sentinel Hill": 1436, Ratchet: 1413, Theramore: 1445, Menethil: 1437, Southshore: 1424, "Booty bay": 1434, "Booty Bay": 1434 };
// 各區聯盟飛行點／碼頭（台服）
const FP = { 1453: "暴風城", 1455: "鐵爐堡", 1432: "塞爾薩瑪", 1436: "哨兵嶺", 1433: "湖畔鎮", 1431: "夜色鎮", 1437: "米奈希爾港", 1439: "奧伯丁", 1438: "魯瑟蘭村",
  1440: "阿斯特蘭納", 1442: "石爪峰", 1413: "棘齒城", 1434: "藏寶海灣", 1417: "避難谷地", 1424: "南海鎮", 1445: "塞拉摩", 1446: "加基森", 1444: "羽月要塞", 1425: "鷹巢山",
  1427: "瑟銀哨塔", 1449: "馬紹爾營地", 1448: "刺枝林地", 1428: "摩根的崗哨", 1422: "寒風營地", 1423: "聖光之願禮拜堂", 1452: "永望鎮", 1447: "塔倫迪斯營地", 1419: "守望堡",
  1443: "尼耶爾前哨站", 1450: "月光林地", 1451: "塞納里奧城堡", 1457: "達納蘇斯", 2521: "微風島" };
const BIND = { 1453: "暴風城", 1455: "鐵爐堡", 1426: "卡拉諾斯", 1429: "閃金鎮", 1432: "塞爾薩瑪", 1438: "多蘭納爾", 1439: "奧伯丁", 1440: "阿斯特蘭納", 1434: "藏寶海灣",
  1445: "塞拉摩", 1444: "羽月要塞", 1425: "鷹巢山", 2521: "微風島", 1431: "夜色鎮", 1433: "湖畔鎮", 1437: "米奈希爾港", 1446: "加基森", 1452: "永望鎮" };
const DEST = { Auberdine: "奧伯丁", Darkshore: "奧伯丁", Wetlands: "米奈希爾港", "Menethil Harbor": "米奈希爾港", "Stormwind City": "暴風城", Stormwind: "暴風城", Darnassus: "魯瑟蘭村",
  "Rut'theran": "魯瑟蘭村", Ratchet: "棘齒城", "Booty bay": "藏寶海灣", "Booty Bay": "藏寶海灣", Theramore: "塞拉摩", Southshore: "南海鎮", Dalaran: "達拉然" };
const DEST_MAP = { 奧伯丁: 1439, 米奈希爾港: 1437, 暴風城: 1453, 魯瑟蘭村: 1438, 棘齒城: 1413, 藏寶海灣: 1434, 塞拉摩: 1445, 南海鎮: 1424 };
const CLASS = { Warrior: "戰士", Paladin: "聖騎士", Hunter: "獵人", Rogue: "盜賊", Priest: "牧師", Shaman: "薩滿", Mage: "法師", Warlock: "術士", Druid: "德魯伊" };
const RACE = { Human: "人類", Dwarf: "矮人", Gnome: "地精", Nightelf: "夜精靈", NightElf: "夜精靈" };
const CLASS_BIT = { 1: "戰士", 2: "聖騎士", 3: "獵人", 4: "盜賊", 5: "牧師", 7: "薩滿", 8: "法師", 9: "術士", 11: "德魯伊" };

const areaToUi = new Map([...readFileSync(ZONES + "areaIdToUiMapId.lua", "utf8").matchAll(/\[(\d+)\]\s*=\s*(\d+)/g)].map((m) => [+m[1], +m[2]]));
const uiToArea = new Map([...readFileSync(ZONES + "uiMapIdToAreaId.lua", "utf8").matchAll(/\[(\d+)\]\s*=\s*(\d+)/g)].map((m) => [+m[1], +m[2]]));
// 副本區域：areaId → { name, alts, entrance }
const DUNGEON = new Map();
for (const m of readFileSync(ZONES + "dungeons.lua", "utf8").matchAll(/^\s*\[(\d+)\]\s*=\s*\{"([^"]+)",(nil|\{[\d,]*\}),(\d+),\{\{(\d+),\s*([\d.]+),\s*([\d.]+)\}/gm)) {
  const alts = m[3] === "nil" ? [] : m[3].replace(/[{}]/g, "").split(",").filter(Boolean).map(Number);
  DUNGEON.set(+m[1], { name: m[2], alts, entrance: { map: areaToUi.get(+m[5]), x: +m[6], y: +m[7] } });
}
const INSTANCES = new Map();
const CONST = (n) => n.toUpperCase().replace(/'/g, "").replace(/[^A-Z0-9]+/g, "_");
for (const [, id, num, named] of readFileSync(ZONES + "instanceIdToAreaId.lua", "utf8").matchAll(/\[(\d+)\]\s*=\s*(?:(\d+)|ZoneDB\.zoneIDs\.([A-Z0-9_]+))/g)) {
  const area = num ? +num : [...DUNGEON.entries()].find(([, d]) => CONST(d.name) === named)?.[0];
  if (area && !INSTANCES.has(area)) INSTANCES.set(area, +id);
}
if (!INSTANCES.has(1176)) INSTANCES.set(1176, 209);
const DUNGEON_OF = new Map();
for (const [area, d] of DUNGEON) for (const a of [area, ...d.alts]) if (!DUNGEON_OF.has(a)) DUNGEON_OF.set(a, area);
const DUNGEON_ZH = { 16919: "領主大廳", 16611: "羅德隆廢墟", 1581: "死亡礦坑", 717: "暴風城監獄", 719: "黑暗深淵", 721: "諾莫瑞根", 1337: "奧達曼", 1584: "黑石深淵", 1583: "黑石塔",
  16544: "達拉然城", 16732: "挖掘場：溼地", 796: "血色修道院", 1176: "祖爾法拉克", 2100: "瑪拉頓", 1477: "阿塔哈卡神廟", 2017: "斯坦索姆", 2057: "通靈學院", 2557: "厄運之槌",
  718: "哀嚎洞穴", 209: "影牙城堡", 491: "剃刀沼澤", 722: "剃刀高地", 2677: "黑翼之巢", 2717: "熔火之心", 3456: "納克薩瑪斯", 2159: "奧妮克希亞的巢穴",
  3429: "安其拉廢墟", 3428: "安其拉神廟", 2257: "礦道地鐵", 1977: "祖爾格拉布" };
// 部落副本檔的建議等級（英文名對得上就沿用）
const HORDE_LV = new Map();
for (const m of readFileSync(join(ROOT, "route", "05-副本.md"), "utf8").matchAll(/^##\s*副本｜.+?[（(]([^（）()]+)[）)][（(]建議等級\s*(\d+)\s*[–-]\s*(\d+)/gm)) HORDE_LV.set(db.norm(m[1]), [+m[2], +m[3]]);

// 建置程式裡的遊戲名對照（NPC 名、任務名以遊戲內為準）
const buildSrc = readFileSync(join(ROOT, "tools", "build.mjs"), "utf8");
const objLit = (name) => { const a = buildSrc.indexOf(`const ${name} = {`) + `const ${name} = `.length; const b = buildSrc.indexOf("\n};", a); return Function("return " + buildSrc.slice(a, b + 2))(); };
const GAME_NAME = objLit("GAME_NAME"), QUEST_NAME = objLit("QUEST_NAME");
const gameName = (n) => { const c = String(n || "").replace(/<[^>]*>/g, "").replace(/[『』「」《》“”"]/g, "").trim(); return GAME_NAME[c] || n; };
// TUGs 寫錯的任務 ID → QuestieDB 的正確 ID（依前後任務與地點判斷）
const ID_FIX = { 281143: 96137, 6221: 8461, 6241: 8464 };
const fixedIds = new Set();
// ── 小工具 ───────────────────────────────────────────────────────────────────
const unknownNotes = [];
const missingQuests = new Set();
const clean = (s) => String(s ?? "").replace(/｜/g, "／").replace(/\s+/g, " ").trim();
const qName = (id) => { const q = db.quest(id); return q ? `${clean(QUEST_NAME[id] || q.zhTW) || "?"}（${clean(q.en)}）` : `?（Quest ${id}）`; };
const npcZh = (en) => { const id = db.idByEn("Npc", en); const n = id && db.npc(id); return (n && n.zhTW) || en; };
const itemZh = (id) => db.l10nName("Item", id, "zhTW") || db.itemEn(id) || String(id);
const itemZhEn = (en) => { const id = db.idByEn("Item", en); return id ? itemZh(id) : en; };
const fmt = (n) => (+n).toFixed(2);
const dist = (a, b) => (a && b && a.map === b.map ? Math.hypot(a.x - b.x, a.y - b.y) : Infinity);
const inDungeonMap = (m) => m < 1000;
// 最靠近游標的出生點；游標地圖沒有就取最大群
const pick = (spawns, cur) => {
  const pts = spawns.filter((p) => !inDungeonMap(p.map));
  if (!pts.length) return null;
  const same = cur && pts.filter((p) => p.map === cur.map);
  if (same && same.length) return same.reduce((a, b) => (dist(a, cur) <= dist(b, cur) ? a : b));
  return clusterCenter(pts);
};
const giverSpawns = (q, turnin) => {
  const npcs = (turnin ? q.endNpcs : q.startNpcs).map((n) => db.npc(n)).filter(Boolean);
  const objs = (turnin ? q.endObjects : q.startObjects).map((o) => db.object(o)).filter(Boolean);
  return { npcs, objs, spawns: [...npcs.flatMap((n) => n.spawns), ...objs.flatMap((o) => o.spawns)] };
};
// 「做」的目標點：每個目標怪／物件各取一群
const targetPoints = (id, cur) => {
  const groups = db.questMobs(id).filter(Boolean).map((m) => m.kind === "object"
    ? (m.objectsEn || []).flatMap((en) => { const o = db.idByEn("Object", en); return (o && db.object(o)?.spawns) || []; })
    : (m.namesEn || []).flatMap((en) => { const n = db.idByEn("Npc", en); return (n && db.npc(n)?.spawns) || []; }));
  const all = groups.flat();
  if (!all.length) return { pts: [], dungeonOnly: false, hasTargets: groups.length > 0 };
  const open = all.filter((p) => !inDungeonMap(p.map));
  if (!open.length) return { pts: [], dungeonOnly: true, dungeonMap: all[0].map, hasTargets: true };
  const maps = new Map();
  for (const p of open) maps.set(p.map, (maps.get(p.map) || 0) + 1);
  const map = cur && maps.has(cur.map) ? cur.map : [...maps.entries()].sort((a, b) => b[1] - a[1])[0][0];
  const pts = groups.map((g) => clusterCenter(g.filter((p) => p.map === map))).filter(Boolean);
  return { pts: [...new Map(pts.map((p) => [`${fmt(p.x)},${fmt(p.y)}`, p])).values()].slice(0, 4), dungeonOnly: false, hasTargets: true };
};
const parseG = (line, fallbackMap) => {
  const m = line.match(/\[G\s*([\d.]+)\s*,\s*([\d.]+)(?:\s*,\s*[\d.]+)?\s*,?\s*([^\]]*)\]/);
  if (!m) return null;
  const zone = m[3].trim();
  const map = zone ? EN_MAP[zone] : fallbackMap;
  return map ? { map, x: +m[1], y: +m[2] } : null;
};
const tagsOf = (line) => {
  const a = [...line.matchAll(/\[A ([^\]]*)\]/g)].pop();
  if (!a) return { cls: [], race: [] };
  const parts = a[1].split(",").map((s) => s.trim()).filter(Boolean);
  return { cls: parts.map((p) => CLASS[p]).filter(Boolean), race: parts.map((p) => RACE[p.replace(/\s+/g, "")]).filter(Boolean) };
};

// ── 自由文字：自己寫的中文說明（TUGs 原文不搬） ──────────────────────────────
// desc：接到下一個步驟的【說明】；prev：接到上一步；step：產生一步；opt：下一步標可跳過
const NOTES = [
  [/Give him the Thunder Ale/, { desc: () => `樓下有矮人守著酒桶，把${itemZh(2686)}交給他；他不在就直接和酒桶互動。` }],
  [/Buy a Bronzetube at/, { buy: { item: 4371, n: 1, desc: "限量商品，有貨且還沒有才買。" } }],
  [/^Do a full run of Uldaman/, { desc: "奧達曼一路打到格瑞姆洛克。" }],
  [/^(Do the 3 quests on the side now|\[A Paladin\]You just got a QuestItem)/, null],
  [/^Kill 8 boars now/, { desc: "先打 8 隻，其餘邊做後面的任務邊補。" }],
  [/SKINNING( card|-questreward| reward)/i, { desc: "獎勵選剝皮卡，就算不打算練剝皮也先選，之後可放棄專業。" }],
  [/^Die (on purpose|and rezz)/, { step: { v: "註", text: "故意死亡，在靈魂醫者復活，省下跑回去的時間。", opt: true } }],
  [/^Die on the Campfire/, { step: { v: "到", text: "在附近營火故意燒死，到靈魂醫者復活，省跑路。", opt: true, g: true } }],
  [/Cirrusfly Queen/, { desc: "朝女王跳過去時使用天裔種族技能。" }],
  [/Windstone Clusters/, { desc: () => `接下來幾個任務沿途收集${itemZhEn("Windstone Cluster")}，值得稍微繞路。` }],
  [/Sapta-Potion/, { desc: "到任務地點再使用薩普塔。" }],
  [/^Go South of Ameth 'Aran/, { desc: () => `往南多打${npcZh("Rabid Thistle Bear")}，再到 38, 60 一帶找，打到 6–10 隻先停。` }],
  [/Fill the water tube at the nearby moonwell/, { desc: "到附近的月井把水管裝滿。" }],
  [/proper camera angle/, { desc: "調整視角可從外面直接拾取。" }],
  [/Linen Cloth, just buy it from the auction house/, { desc: "亞麻布不到 10 塊就去拍賣場買，通常很便宜。" }],
  [/^(Start looking for|Look for a group|Search for people|Start looking)/, null],
  [/Take the [Tt]ram to Ironforge/, { step: { v: "交通", text: "到暴風城矮人區搭礦道地鐵到鐵爐堡。", map: 1455 } }],
  [/Take the [Tt]ram to Stormwind/, { step: { v: "交通", text: "在鐵爐堡搭礦道地鐵到暴風城。", map: 1453 } }],
  [/endboss FEARS/, { desc: "尾王約 35% 血會恐懼，先清小怪，再把王拉回前一個房間打。" }],
  [/Use the lever right next to the Quest/, { prev: "接任務處旁有拉桿，拉下開門就能直線跑出去。" }],
  [/^Start killing all Moonstalkers/, { desc: () => `接下來沿路見到${npcZh("Moonstalker Runt")}和${npcZh("Rabid Thistle Bear")}就打。` }],
  [/Empty Cleansing Bowl/, { desc: () => `到月井把${itemZhEn("Empty Cleansing Bowl")}裝滿。` }],
  [/WANTED MURKDEEP/, { desc: "靠近營火才會觸發事件，現在打或晚點路線再經過時打都行。" }],
  [/Moonstalker Sires/, { desc: () => `往下一個任務途中，看到${npcZh("Moonstalker Sire")}就打（幼崽和族母會一起拉）。` }],
  [/phial from Onu/, { desc: () => `走到 39.2, 86.9，使用${npcZh("Onu")}給的小瓶放在地上。` }],
  [/ESCORT ?QUEST|Escort quest inv/i, { desc: "護送任務：組隊時等大家進度一致再接，並關掉自動接交。" }],
  [/Book: The Powers Below/, { desc: () => `坑裡的怪低機率掉${itemZhEn("Book: The Powers Below")}，有掉才接。`, opt: true }],
  [/Remtravel run ahead/, { desc: () => `讓${npcZh("Prospector Remtravel")}先跑，只打先攻擊他的怪。` }],
  [/multiple waves with 2-3Murlocs/, { desc: "會來好幾波魚人，每波 2–3 隻；每波最後一隻拉離營火再殺，吃喝完再拉下一波，或找隊伍。", g: true }],
  [/The first 2 quests are in the cave/, { desc: "前兩件在副本門前的礦洞裡完成。" }],
  [/The endboss drops a QuestItem/, { desc: "尾王掉落開任務的物品，拾取後右鍵接。" }],
  [/^Kill as many Mongrels/, { desc: () => `在 10.8, 63.7 一帶多打${npcZh("Redridge Mongrel")}。` }],
  [/do Ruuzel/, { desc: () => `${npcZh("Ruuzel")}有隊伍再打；法師、術士、獵人可試單刷。`, opt: true }],
  [/kill spiders for some Gooey Spider legs/, { desc: () => `穿過暮色森林時順手打蜘蛛收${itemZhEn("Gooey Spider Leg")}。` }],
  [/Look To The Stars questline/, { desc: "觀星任務線要有青銅管才能開始；沒有就先做別的部分，之後去拍賣場買。" }],
  [/KEEP YOUR Gooey Spider Legs/, { desc: () => `${itemZhEn("Gooey Spider Leg")}留著別賣，後面要交。` }],
  [/Go upstairs and loot the Box/, { desc: "上樓拾取箱子。" }],
  [/If you do NOT have the stockade quests/, { desc: () => `身上已經有「${db.quest(377)?.zhTW || "Crime and Punishment"}」和「${db.quest(386)?.zhTW || "What Comes Around..."}」就跳過接下來兩趟飛行。` }],
  [/Wanted: Lieutenant Fangore,Blackrock Bounty/, { desc: "下面三件精英任務單人很難，找不到隊伍就全部跳過。" }],
  [/Go through the cave into Stonetalon/, { step: { v: "交通", text: "穿過山洞進石爪山脈。", map: 1442 } }],
  [/^Continue questing: Fly to Auberdine and take the boat to Wetlands/, { steps: [{ v: "飛", to: "奧伯丁", map: 1439 }, { v: "船", to: "米奈希爾港", from: "奧伯丁", map: 1437 }] }],
  [/^Fly to Auberdine and take the boat to Wetlands/, { steps: [{ v: "飛", to: "奧伯丁", map: 1439 }, { v: "船", to: "米奈希爾港", from: "奧伯丁", map: 1437 }] }],
  [/Kill Young Crocolisks/, { desc: () => `之後沿路打${npcZh("Young Wetlands Crocolisk")}收皮。` }],
  [/interact with a corpse downstairs/, { desc: "下樓與屍體互動，附近有 1–3 隻精英；用寵物、冰霜新星或恐懼甩開，互動完照原路跑上來，別戀戰。" }],
  [/Jump off the Bridge/, { step: { v: "到", text: "從橋上跳下，到矮人旁拾取信件。", g: true } }],
  [/^If you('re| are) in a group, (do|accept) the follow/, { desc: "後續是精英任務，有隊伍才做。" }],
  [/If you have 60 silk already/, { desc: "已有 60 塊絲綢布才交。", opt: true }],
  [/Go through the cave at\[G53/, { desc: "從山洞進去拿書，容易多拉怪，稀有怪在時更難。" }],
  [/Grind till youre 36 and 3\/4/, { step: { v: "練", lv: 36, desc: "練到 36 級約四分之三。" } }],
  [/Forsaken Courier/, { desc: () => `留意巡邏的${npcZh("Forsaken Courier")}。` }],
  [/Buy 3 Soothing Spices/, { buy: { item: 3713, n: 3 } }],
  [/BUY: 5 Silver Bars/, { buy: { item: 2842, n: 5, npc: "拍賣場" } }],
  [/Kill all Vultures & wolves/, { desc: "之後見到禿鷲和狼都打，任務要用。" }],
  [/Boss Tho'grun/, { desc: () => `留意巡邏的${npcZh("Boss Tho'grun")}。` }],
  [/hard for melees/, { desc: "近戰較難，必要時晚點再做。" }],
  [/Shattered Necklace/, { desc: () => `還沒拿到${itemZhEn("Shattered Necklace")}就進本打穴居人到掉為止，再出來。` }],
  [/Kill Noboru the Cudgel/, { desc: () => `打${npcZh("Noboru the Cudgel")}拿到灰色的棍棒，右鍵開任務。`, opt: true }],
  [/Bottle Quest/, { desc: "沿海灘留意瓶子，撿到可開任務。" }],
  [/Buy all missing pages of Stranglethorn/, { desc: "缺的荊棘谷書頁去拍賣場補：1、4、6、8、10、11、14、16、18、20、21、24、25、26、27。" }],
  [/Cortellos Riddle \(can spawn/, { desc: "三艘船的下層可能刷出科泰羅的謎語，拿到就右鍵接。" }],
  [/Rizzle Brassbolts leaves/, { desc: () => `等${npcZh("Rizzle Brassbolts")}離開建築物再動手。` }],
  [/Fiery Blaze Enchantments/, { desc: "沿途通常會掉熾熱火焰附魔；沒掉就放棄。" }],
  [/Margol the Rager/, { step: { v: "到", text: () => `擊殺${npcZh("Margol the Rager")}，經驗很多。`, opt: true, g: true } }],
  [/^Die in the lava/, { step: { v: "註", text: "跳進岩漿故意死亡：有個任務只能在靈魂狀態接。" } }],
  [/^Get your corpse back/, { step: { v: "註", text: "跑回屍體復活。" } }],
  [/Grind in Black Rock Depths till level 52/, { step: { v: "練", lv: 52, desc: "在黑石深淵練。", opt: true } }],
  [/LVL 50 YET\? Accept Ragnar/, { desc: "50 級才能接。" }],
  [/Carefully Folded Note/, { desc: "之前拿到的折好的紙條現在右鍵開任務。" }],
  [/Get 7 Crystals each/, { desc: "收集紅、藍、綠、黃水晶各 7 個，並從迅猛龍身上拿殘破的日誌。" }],
  [/Grind till level 49 and 50%/, { step: { v: "練", lv: 49, desc: "在 67.7, 30.7 一帶打植物，練到 49 級一半。" } }],
  [/The following quest can be hard/, { desc: "這件較難，可留到回安戈洛時再做。", opt: true }],
  [/^Finish all kill\/collect quests/, { step: { v: "註", text: "把手上的擊殺、收集任務做完。" } }],
  [/trick-jump in the back/, { desc: "後面可以跳上去抄捷徑。" }],
  [/really annoying escort/, { desc: "護送很麻煩，可跳過。", opt: true }],
  [/Use the Stave in your Inventory/, { desc: "使用背包裡的法杖。" }],
  [/Pristine Yeti Hide/, { desc: () => `打雪人時有掉${itemZhEn("Pristine Yeti Hide")}就右鍵接。` }],
  [/Videre Elixir/, { step: { v: "到", text: "喝下維德雷藥劑後保持死亡狀態，以靈魂找任務 NPC。", g: true } }],
  [/^Ressurrect/, { step: { v: "註", text: "回屍體復活。" } }],
  [/If youre in a group do the next step/, { desc: "有隊伍才做。", opt: true }],
  [/If youre not 60 by now/, { step: { v: "註", text: "還沒到 60 級就把冬泉谷任務做完，或打一趟黑石深淵；還不夠再刷斯坦索姆或通靈學院。" } }],
  [/Kill all spiders whilst continuing/, { desc: () => `沿路打蜘蛛，之後要 7 個${itemZhEn("Small Spider Leg")}。` }],
  [/(Tame|Get) a pet you like/, { step: { v: "註", text: "獵人：馴服喜歡的寵物，推薦野豬（衝鋒開怪快）。", cls: ["獵人"] } }],
  [/Teleport to Ruth'theran/, { step: { v: "交通", text: "走進達納蘇斯的傳送門到魯瑟蘭村。", map: 1438 } }],
  [/THIS IS OPTIONAL, IF YOU JUST CARE/, { optOn: true }],
  [/THE OPTIONAL AREA IS DONE/, { optOff: true }],
  [/Zeppelin-Boat" to Dalaran/, { step: { v: "船", to: "達拉然", from: "微風島" } }],
  [/Go through the tunnel, afterwards kill EVERY boar/, { desc: "穿過隧道後，往旅店的路上每隻野豬都打。" }],
  [/Stocking Jetsteam is your NR 1/, { desc: () => `優先完成「${db.quest(317)?.zhTW || "Stocking Jetsteam"}」，沿路見到熊和野豬就打。` }],
  [/Kill boars to get: \[CI2886/, { desc: () => `打野豬收${itemZh(2886)} ×6。` }],
  [/you do NOT need to kill the yeti/, { desc: "不必殺雪人：等牠離開洞穴（最多約 5 分鐘），進去開箱就跑。" }],
  [/Chunk of Boar Meat/, { desc: () => `沿路打野豬，收 4 塊${itemZhEn("Chunk of Boar Meat")}。` }],
  [/crossing the Kobold mine 4 times/, { desc: "接下來會經過狗頭人礦坑 4 次，每次順手打 2–3 隻收任務物品。" }],
  [/^Learn Enchanting/, { step: { v: "註", text: "學附魔：艾爾文森林有一個任務要用，做完可放棄。", opt: true } }],
  [/Fence hopping/, { desc: "多數職業可用跳柵欄反覆拉打的方式單刷，但很難，打不過就跳過。" }],
  [/The axe is the only part where you have to kill/, { desc: "只有斧頭要打兩隻怪：先打不是採集者的那隻（採集者會喝藥水），不行就重置。" }],
  [/elite murloc Croaky/, { desc: "精英魚人掉頭顱開任務，打得過才做。", opt: true }],
  [/die to the spiders and rezz up in Redridge/, { step: { v: "到", text: "被蜘蛛打死後在赤脊山復活，省下跑路時間。", opt: true, g: true } }],
  [/exploring experience/, { step: { v: "到", text: "探索地點拿經驗。", opt: true, g: true } }],
  [/Slowly fall to the ledge/, { desc: "慢慢往下跳到前方平台，再落到地面。" }],
  [/Run to \[G/, { step: { v: "到", text: "沿路跑到這個點。", g: true } }],
  [/^Learn (Skinning|First Aid|cooking) at \[TAR(\d+)\]/i, { learn: true }],
  [/^(You got a Questitem|\[O\]You got a Questitem|You got a questitem in)/, null],
  [/(chicken|Chicken) (beacon )?quest/, null],
];
const VENDOR_HINT = { 6529: "釣魚用品商", 6530: "釣魚用品商", 2686: "旅店老闆", 2894: "旅店老闆" };
const PROF = { skinning: "剝皮", "first aid": "急救", cooking: "烹飪" };

// ── 解析單一 TUGs 檔 → 步驟清單 ───────────────────────────────────────────
const parseFile = (file, cursor) => {
  const raw = readFileSync(join(SRC, file), "utf8");
  const body = (raw.match(/\[\[([\s\S]*)\]\]/) || [, raw])[1];
  const steps = [];
  let pendDesc = [], pendOpt = false, optBlock = false, cur = cursor;
  if (START[file] && START[file].bind !== undefined) bind = START[file].bind; // 會合站：各族綁點不同
  const vendors = [];
  const push = (s) => {
    if (pendDesc.length && (s.v === "接" || s.v === "做" || s.v === "交" || s.v === "買" || s.v === "到")) { s.desc = [...(s.desc || []), ...pendDesc]; pendDesc = []; }
    if (pendOpt && /^[接做交]$/.test(s.v)) { s.opt = true; pendOpt = false; }
    if (optBlock && /^[接做交]$/.test(s.v)) s.opt = true;
    steps.push(s);
    if (s.map && s.x !== undefined) cur = { map: s.map, x: s.x, y: s.y };
    else if (s.map) cur = { map: s.map, x: 50, y: 50, fake: true };
  };
  const lines = body.split(/\r?\n/);
  lines.forEach((line0, li) => {
    const line = line0.trim();
    if (!line || /^\[(N|NX|GA|D)[\s\d]/.test(line) || /^\[D /.test(line) || /Thanks for using|totally free/.test(line)) return;
    const where = `${file}:${li + 1}`;
    const { cls, race } = tagsOf(line);
    const g = parseG(line, cur?.map);
    const lineOpt = /\[O\]|Optional/.test(line) || /^If you have 60 silk/.test(line);
    const elite = /Elite\/Hard Optional/.test(line);
    const whenever = /^\(Whenever you can\)/.test(line);
    const base = { where, cls, race };
    // 筆記規則
    const rule = NOTES.find(([re]) => re.test(line));
    const act = rule && rule[1];
    const val = (v) => (typeof v === "function" ? v() : v);
    const qTokens = [...line.matchAll(/\[Q([ATC])(\d+)(?:,\d+)?\s*-?\s*\]/g)].map((m) => ({ k: m[1], id: ID_FIX[+m[2]] || +m[2] }));
    for (const m of line.matchAll(/\[Q[ATC](\d+)/g)) if (ID_FIX[+m[1]]) fixedIds.add(ID_FIX[+m[1]]);
    if (act && !qTokens.length) {
      if (act.optOn) { optBlock = true; return; }
      if (act.optOff) { optBlock = false; return; }
      if (act.desc) pendDesc.push(val(act.desc));
      if (act.opt) pendOpt = true;
      if (act.prev && steps.length) steps[steps.length - 1].desc = [...(steps[steps.length - 1].desc || []), val(act.prev)];
      for (const s of act.steps || (act.step ? [act.step] : [])) {
        const st = { ...base, ...s, text: val(s.text), desc: s.desc ? [s.desc] : undefined, cls: s.cls || cls };
        if (s.g && g) Object.assign(st, g);
        if (st.v === "到" && st.map === undefined && !g) return;
        push(st);
      }
      if (act.buy) {
        push({ ...base, v: "買", item: act.buy.item, n: act.buy.n, npc: act.buy.npc || (g ? "" : "拍賣場"), ...(g || {}), desc: act.buy.desc ? [act.buy.desc] : undefined });
      }
      if (act.learn) {
        const m = line.match(/^Learn (Skinning|First Aid|cooking) at \[TAR(\d+)\]/i);
        const n = db.npc(+m[2]);
        const at = n && pick(n.spawns, cur);
        push({ ...base, v: "到", text: `向${n?.zhTW || n?.en || "訓練師"}學${PROF[m[1].toLowerCase()]}。`, opt: true, ...(at || {}) });
      }
      return;
    }
    if (act === null && !qTokens.length) return;
    // 爐石／綁爐石／飛行點／飛行／船
    if (/Use your \[H\] Hearthstone/.test(line)) { push({ ...base, v: "爐", bind: bind || "爐石綁定處" }); if (bind && bindMap.get(bind)) cur = { map: bindMap.get(bind), x: 50, y: 50, fake: true }; return; }
    const set = line.match(/Set your \[[HS]\] to ([A-Za-z' ]+?) at/);
    if (set) {
      const map = EN_MAP[set[1].trim()] || g?.map;
      bind = BIND[map] || ZH[map] || set[1];
      bindMap.set(bind, map);
      push({ ...base, v: "交通", text: `在${bind}旅店綁爐石${g ? `（${g.map !== map ? g.map + " " : ""}${fmt(g.x)}, ${fmt(g.y)}）` : ""}。`, ...(g || { map }) });
      return;
    }
    if (/\[P\] flightpath at/.test(line) && g) { push({ ...base, v: "鳥", node: FP[g.map] || ZH[g.map], ...g }); return; }
    const fly = line.match(/Fly to (?:\[F ([^\]]+)\]|([A-Za-z' ]+))/);
    if (fly) {
      const name = (fly[1] || fly[2]).trim();
      const map = EN_MAP[name];
      push({ ...base, v: "飛", to: DEST[name] || FP[map] || name, map });
      return;
    }
    const boat = line.match(/Take the (?:boat|ship|Boat|boath)(?: route)? to ([A-Za-z' ]+?)(?:\s*\(|[.\[]|$)/);
    if (boat) {
      const to = DEST[boat[1].trim()] || boat[1].trim();
      push({ ...base, v: "船", to, from: FP[cur?.map] || "", map: DEST_MAP[to] });
      return;
    }
    const xp = line.match(/\[XP(\d+)/);
    if (xp && !qTokens.length) { push({ ...base, v: "練", lv: +xp[1], ...(g || {}) }); return; }
    const buy = line.match(/Buy: \[CI(\d+),(\d+)[^\]]*\]/i);
    if (buy) {
      const tar = line.match(/\[TAR(\d+)\]/);
      const from = line.match(/\]\s*from ([A-Za-z' ]+)$/);
      const n = tar ? db.npc(+tar[1]) : from ? db.npc(db.idByEn("Npc", from[1].trim())) : null;
      const at = g || (n && pick(n.spawns, cur));
      const s = { ...base, v: "買", item: +buy[1], n: +buy[2], npc: n ? n.zhTW || n.en : VENDOR_HINT[+buy[1]] || "拍賣場", ...(at || {}) };
      if (/if it is in stock|limited supply/.test(line)) s.desc = ["限量商品，有貨才買。"];
      if (/Skinning Knife|Gladius|Wooden Mallet|Walking Stick|Blunderbuss|Recurve Bow|Heavy Spiked Mace/.test(line)) s.opt = true;
      push(s);
      return;
    }
    const vendor = line.match(/^Vendor at \[TAR(\d+)\]/);
    if (vendor) { vendors.push(+vendor[1]); return; }
    if (!qTokens.length) {
      if (!/^(Learn your Level|\[A [^\]]*\]\s*\[T\]|\[A [^\]]*\]\s*Feed|Use: \[SP|\[SK |Get Skinning|Get to level 20|Repair your gear|Now get \[CI|Do the dungeon|This will be added|will be added|This part\(|Here for example|Either use Hearthstone|I suggest to do RoL|Depending on|You do BFD now|We will turn|Grind|Farm|After done|Turnin all STV|In grp|Inventory time|If youre not doing brd|Run back to the Blackrock|Buy a Mithril|Start Cortellos|Plenty of stuff|If the Hearthstone|If you dont intent|Now do Uldaman|Go further into Uldaman|Take the Gni|In the same Room|Run into the room|In the Room with|Kill Grimlok|This Part is different|Finish the 3|There are two ghosts|You can reach|Jump into the water|\[A Hunter\] Run up|Although the next guide|If you want to, you can do Hogger|I recommend getting a boar|Buy at the auction house now|Use your \[H\] Hearthstone)/.test(line))
        unknownNotes.push(`${where}  ${line}`);
      return;
    }
    // 任務步驟
    if (act && act.desc) pendDesc.push(val(act.desc));
    if (act && act.opt) pendOpt = true;
    const seen = new Set();
    for (const t of qTokens) {
      const key = t.k + t.id;
      if (seen.has(key)) continue;
      seen.add(key);
      const q = db.quest(t.id);
      if (!q) missingQuests.add(t.id);
      const s = { ...base, v: t.k === "A" ? "接" : t.k === "T" ? "交" : "做", id: t.id, opt: lineOpt || undefined, elite, whenever, g };
      if (/Questitem|QuestItem/.test(line) && t.k === "A") s.fromItem = true;
      steps.push(s); // 座標稍後補（要用游標）
      // 先佔位，座標在 resolve 時補
      resolveQuestStep(s, cur);
      if (s.map && s.x !== undefined) cur = { map: s.map, x: s.x, y: s.y };
      if (pendDesc.length) { s.desc = [...(s.desc || []), ...pendDesc]; pendDesc = []; }
      if (pendOpt) { s.opt = true; pendOpt = false; }
      if (optBlock) s.opt = true;
    }
  });
  return { steps, cursor: cur, vendors };
};
const bindMap = new Map();
let bind = null;

// 接／交／做：NPC、座標、目標文字
function resolveQuestStep(s, cur) {
  const q = db.quest(s.id);
  if (!q) { s.npc = "?"; if (s.g) Object.assign(s, s.g); return; }
  if (s.v === "做") {
    s.obj = clean(q.obj.filter((x) => typeof x === "string").join(" ")) || "完成任務目標。";
    const tp = targetPoints(s.id, s.g || cur);
    s.hasTargets = tp.hasTargets;
    if (tp.dungeonOnly) { s.dungeonMap = tp.dungeonMap; s.inDungeon = true; }
    if (s.g) { Object.assign(s, s.g); s.more = tp.pts.filter((p) => p.map === s.g.map && dist(p, s.g) > 3); }
    else if (tp.pts.length) { Object.assign(s, tp.pts[0]); s.more = tp.pts.slice(1); }
    return;
  }
  const turnin = s.v === "交";
  const { npcs, objs, spawns } = giverSpawns(q, turnin);
  if (npcs.length) s.npc = gameName(npcs[0].zhTW) || npcs[0].en;
  else if (objs.length) s.npc = "物件 " + (objs[0].zhTW || objs[0].en);
  else if (!turnin && q.startItems.length) { s.npc = "物品 " + itemZh(q.startItems[0]); s.item = q.startItems[0]; if (!s.g && cur && !cur.fake) s.g = { map: cur.map, x: cur.x, y: cur.y }; }
  else s.npc = "?";
  if (spawns.length && spawns.every((p) => inDungeonMap(p.map))) s.inDungeon = true;
  // TUGs 有寫座標時用來挑最近的出生點；QuestieDB 在那張圖沒有點才用 TUGs 座標
  const at = (s.g && pick(spawns.filter((p) => p.map === s.g.map), s.g)) || s.g || pick(spawns, cur);
  if (at) {
    Object.assign(s, { map: at.map, x: at.x, y: at.y });
    if (npcs.length > 1) { // 同名多個 NPC：取最近那個的名字
      const near = npcs.map((n) => ({ n, d: Math.min(...n.spawns.map((p) => dist(p, at))) })).sort((a, b) => a.d - b.d)[0];
      if (near) s.npc = gameName(near.n.zhTW) || near.n.en;
    }
  }
  if (s.item && !s.desc) s.desc = [`右鍵背包裡的${itemZh(s.item)}接任務。`];
}

// ── 站別設定 ─────────────────────────────────────────────────────────────────
const START = {
  "1-6 Northshire.lua": { name: "北郡山谷", only: "僅人類", bind: "北郡修道院", travel: "人類出生地。別族要來，從閃金鎮沿大路往北進北郡山谷，找修道院前的維里副隊長。" },
  "6-9 Elwynn Forest.lua": { name: "艾爾文森林・閃金鎮", only: "僅人類" },
  "1-6 Coldridge Valley.lua": { name: "寒脊山谷", only: "僅矮人／地精", bind: "寒脊山谷", travel: "矮人與地精出生地。別族要來，從卡拉諾斯往西南穿過山洞隧道進谷。" },
  "6-9 Dun Morogh.lua": { name: "丹莫洛・卡拉諾斯", only: "僅矮人／地精" },
  "1-6 Shadowglen.lua": { name: "幽影谷", only: "僅夜精靈", bind: "幽影谷", travel: "夜精靈出生地。別族要來，從奧伯丁搭船到魯瑟蘭村，走傳送門進達納蘇斯，再沿路往東經多蘭納爾到幽影谷。" },
  "6-11 Teldrassil.lua": { name: "泰達希爾・多蘭納爾", only: "僅夜精靈" },
  "1-6 Skyborne.lua": { name: "微風島・出生地", only: "僅天裔精靈", bind: "微風島", travel: "天裔精靈出生地，聯盟與部落共用島上的起始任務，離島時才分陣營。" },
  "6-12 Skyborne.lua": { name: "微風島・聯盟線", only: "僅天裔精靈" },
  "9-11 Dun Morogh&Loch Modan.lua": { name: "丹莫洛與洛克莫丹", bind: "", only: "僅人類／矮人／地精／夜精靈", travel: "人類從暴風城搭礦道地鐵到鐵爐堡；夜精靈搭船到暴風城再轉地鐵。天裔精靈不走這站，直接從微風島搭船到黑海岸。" },
};
const PURE_DUNGEON = new Set(["15-16 Halls of Thanes.lua", "25-26 Stockades.lua", "28-29 Blackfathom Depths.lua", "33-34 Gnomeregan.lua"]);
const ORDER = ["1-6 Northshire.lua", "6-9 Elwynn Forest.lua", "1-6 Coldridge Valley.lua", "6-9 Dun Morogh.lua", "1-6 Shadowglen.lua", "6-11 Teldrassil.lua", "1-6 Skyborne.lua", "6-12 Skyborne.lua",
  "9-11 Dun Morogh&Loch Modan.lua", "11-14 Darkshore.lua", "14-15 Westfall.lua", "15-16 Halls of Thanes.lua", "16-18 Loch Modan.lua", "18-20 Darkshore.lua", "20-22 Ruins of Lordaeron&Deadmines.lua",
  "22-23 Redridge Mountains.lua", "23-24 Ashenvale.lua", "24-25 Duskwood.lua", "25-26 Stockades.lua", "26-27 Redridge Mountains.lua", "27-28 Ashenvale.lua", "28-29 Blackfathom Depths.lua",
  "29-30 Wetlands.lua", "30-31 Duskwood.lua", "31-32 Wetlands.lua", "32-33 Excavation Site.lua", "32-33 Stranglethorn Vale.lua", "33-34 Gnomeregan.lua", "34-35 Ashenvale.lua",
  "36-37Arathi.lua", "38-39Dustwallow Marsh,STV.lua", "40-43Badlands,Uldaman.lua", "41-44 Riverglades.lua", "41-44Tanaris,STV.lua", "44-45Feralas.lua", "45-47Tanaris,Hinterlands.lua",
  "47-49Searing Gorge.lua", "49-51Un'Goro.lua", "52-53Felwood.lua", "55-56BS,WPL.lua", "56-60WPL,EPL,BS.lua"];
const present = new Set(readdirSync(SRC).filter((f) => f.endsWith(".lua")));
for (const f of present) if (!ORDER.includes(f)) throw new Error("未排序的 TUGs 檔：" + f);
const fileNo = (lo) => (lo < 11 ? "01" : lo < 30 ? "02" : lo < 45 ? "03" : "04");

const isQ = (s) => s.v === "接" || s.v === "做" || s.v === "交";
const CITY = new Set([1453, 1455, 1457]);
const TRAVEL = new Set(["飛", "船", "爐", "交通"]);
const dungeonOfQuest = (id) => { const q = db.quest(id); return q && DUNGEON_OF.get(q.zoneOrSort); };
const mode = (arr) => { const c = new Map(); for (const x of arr) if (x) c.set(x, (c.get(x) || 0) + 1); return [...c.entries()].sort((a, b) => b[1] - a[1])[0]?.[0]; };

const stations = []; // { file, name, lv, only, map, steps, vendors, travel }
const dungeonMap = new Map();
const dungeons = []; // { area, steps, after (station index), file }
const placeholders = [];
let cursor = null;
for (const file of ORDER.filter((f) => present.has(f))) {
  const lvm = file.match(/^(\d+)-(\d+)/);
  const lv = [+lvm[1], +lvm[2]];
  const { steps, cursor: next, vendors } = parseFile(file, START[file] ? null : cursor);
  cursor = next;
  if (!steps.some(isQ)) { placeholders.push(file); continue; }
  // 副本任務：區域是副本，或「做」的目標只在副本裡
  const dq = new Map();
  for (const s of steps.filter(isQ)) {
    let area = dungeonOfQuest(s.id);
    if (!area && s.inDungeon && s.v === "做" && s.dungeonMap) area = DUNGEON_OF.get(uiToArea.get(s.dungeonMap));
    if (area && !dq.has(s.id)) dq.set(s.id, area);
  }
  const pure = PURE_DUNGEON.has(file);
  const pureArea = pure ? mode([...dq.values()]) : undefined;
  // 純副本檔的路程步驟跟著下一個任務步驟走
  const owner = steps.map((s, k) => {
    if (isQ(s)) return dq.get(s.id) || null;
    if (!pure) return null;
    const nx = steps.slice(k + 1).find(isQ) || [...steps.slice(0, k)].reverse().find(isQ);
    return nx ? dq.get(nx.id) || null : null;
  });
  const openSteps = steps.filter((s, k) => !owner[k]);
  // 純副本檔剩下很少的城鎮任務：併進副本段出本後交
  const openQ = openSteps.filter(isQ).length;
  const keepOpen = !pure || openQ >= 3;
  // 開放世界步驟分站：遇到飛／船／爐換區且新區任務夠多才切
  const segs = [];
  if (keepOpen && openSteps.length) {
    const legs = [];
    let leg = [];
    for (const s of openSteps) { if (TRAVEL.has(s.v) && leg.length) { legs.push(leg); leg = []; } leg.push(s); }
    if (leg.length) legs.push(leg);
    const legMap = (l) => mode(l.filter(isQ).map((s) => s.map));
    const split = !START[file] && !pure;
    for (const l of legs) {
      const m = legMap(l), nq = l.filter(isQ).length;
      const last = segs[segs.length - 1];
      if (!last || !split || !m || m === last.map || nq < 6 || CITY.has(m)) { if (last) { last.steps.push(...l); last.map ||= m; } else segs.push({ steps: [...l], map: m }); }
      else segs.push({ steps: [...l], map: m });
    }
    for (let k = segs.length - 1; k > 0; k--) if (segs[k].steps.filter(isQ).length < 12 || segs[k].map === segs[k - 1].map) { segs[k - 1].steps.push(...segs[k].steps); segs.splice(k, 1); }
    if (segs.length > 1 && segs[0].steps.filter(isQ).length < 10) { segs[1].steps.unshift(...segs[0].steps); segs.shift(); }
  }
  const total = segs.reduce((n, sg) => n + sg.steps.filter(isQ).length, 0) || 1;
  let acc = 0;
  const firstIdx = stations.length;
  segs.forEach((sg) => {
    const nq = sg.steps.filter(isQ).length;
    const a = Math.floor(lv[0] + (lv[1] - lv[0]) * acc / total);
    acc += nq;
    const b = Math.max(a, Math.round(lv[0] + (lv[1] - lv[0]) * acc / total));
    const map = mode(sg.steps.filter((s) => s.v === "接" || s.v === "交").map((s) => s.map)) || sg.map || mode(sg.steps.map((s) => s.map));
    const st = START[file];
    stations.push({ file, no: fileNo(lv[0]), name: st && segs.length === 1 ? st.name : null, zone: map, lv: [a, b], only: st?.only, travel: st?.travel, map, steps: sg.steps, vendors });
  });
  // 副本段
  // 副本步驟：同一個副本跨檔合併；每步記下「當時在哪一站之後」
  steps.forEach((s, k) => {
    const area = owner[k] || (!keepOpen && pureArea) || null;
    if (!area) return;
    const before = new Set(steps.slice(0, k).filter((x, j) => !owner[j]));
    let after = firstIdx - 1;
    if (!pure) stations.slice(firstIdx).forEach((st, j) => { if (st.steps.some((x) => before.has(x))) after = firstIdx + j; });
    s.after = Math.max(after, 0);
    if (!dungeonMap.has(area)) { dungeonMap.set(area, { area, steps: [] }); dungeons.push(dungeonMap.get(area)); }
    dungeonMap.get(area).steps.push(s);
  });
}
for (const d of dungeons) {
  const key = d.steps.find((s) => s.v === "做") || d.steps.find((s) => s.v === "交") || d.steps[d.steps.length - 1];
  d.after = key.after;
  const acc = d.steps.filter((s) => s.v === "接").map((s) => s.after);
  d.pickAt = acc.length ? Math.min(...acc) : d.after;
}

// ── 站名與第幾次 ─────────────────────────────────────────────────────────────
for (const st of stations) if (!st.name) st.name = ZH[st.map] || "未知區域";
const counts = new Map();
for (const st of stations) counts.set(st.name, (counts.get(st.name) || 0) + 1);
const nth = ["第一次", "第二次", "第三次", "第四次", "第五次", "第六次"];
const seenName = new Map();
for (const st of stations) {
  if (counts.get(st.name) > 1) { const k = seenName.get(st.name) || 0; seenName.set(st.name, k + 1); st.name = `${st.name}・${nth[k] || "第" + (k + 1) + "次"}`; }
}
stations.forEach((st, k) => { st.num = k + 1; st.id = `${st.no}-第${st.num}站`; });
// 同站重複的同一步（同動作同任務）只留第一個
for (const st of [...stations, ...dungeons]) { const seen = new Set(); st.steps = st.steps.filter((x) => { if (!isQ(x)) return true; const k = x.v + x.id; if (seen.has(k)) return false; seen.add(k); return true; }); }

// ── 路線檢查：純對話不放「做」、專程繞路標可跳過、買東西補任務 ID ─────────
const routeQuests = new Set();
for (const s of [...stations.flatMap((x) => x.steps), ...dungeons.flatMap((d) => d.steps)]) if (s.id) routeQuests.add(s.id);
const followUps = new Map(); // 任務 → 路線上以它為前置的任務
for (const id of routeQuests) { const q = db.quest(id); if (!q) continue; for (const p of [...q.preGroup, ...q.preSingle]) { if (!followUps.has(p)) followUps.set(p, []); followUps.get(p).push(id); } }
let talkDropped = 0, detours = [];
for (const st of [...stations, ...dungeons]) {
  const list = st.steps;
  for (let k = list.length - 1; k >= 0; k--) {
    const s = list[k];
    if (s.v !== "做" || s.g || (s.more || []).length) continue;
    const q = db.quest(s.id);
    // 下一個任務步驟就是交這件：沒有目標，或目標就在交件人身上（對話類）→ 純對話，不放「做」
    const nextQ = list.slice(k + 1).find(isQ);
    if (q && nextQ && nextQ.v === "交" && nextQ.id === s.id && (!s.hasTargets || dist(s, nextQ) < 2)) { list.splice(k, 1); talkDropped++; }
  }
}
for (const st of stations) {
  const qs = st.steps.filter((s) => s.v === "做" && s.map !== undefined && !s.opt);
  for (const s of qs) {
    const k = st.steps.indexOf(s);
    const others = st.steps.filter((o, j) => j !== k && o.id !== s.id && o.map === s.map && o.x !== undefined);
    const nearest = Math.min(...others.map((o) => dist(o, s)));
    const qq = db.quest(s.id);
    if (nearest > 18 && nearest !== Infinity && !(s.cls || []).length && !(qq && qq.classes) && !(followUps.get(s.id) || []).length) {
      for (const o of st.steps.filter((o) => o.id === s.id)) o.opt = true;
      s.desc = [...(s.desc || []), "專程繞路，附近沒有其他目標；趕路可跳過。"];
      detours.push(`${st.id} ${qName(s.id)} ${s.id}（最近其他目標 ${nearest.toFixed(0)}）`);
    }
  }
}
// 買：找後面用得到這個物品的任務
const allSeq = stations.flatMap((st) => st.steps);
for (const s of allSeq.filter((x) => x.v === "買")) {
  const zh = itemZh(s.item);
  const k = allSeq.indexOf(s);
  const user = allSeq.slice(k + 1, k + 80).find((o) => o.id && (db.quest(o.id)?.obj || []).some((t) => typeof t === "string" && t.includes(zh)));
  if (user) s.fq = user.id;
}

// ── 輸出 ─────────────────────────────────────────────────────────────────────
const coordText = (s, map) => (s.x === undefined ? "?" : `${s.map && s.map !== map ? s.map + " " : ""}${fmt(s.x)}, ${fmt(s.y)}`);
const tagText = (s, extra = []) => {
  const t = [...extra];
  const q = s.id && db.quest(s.id);
  const cls = [...(s.cls || [])];
  if (!cls.length && q && q.classes) {
    const own = Object.entries(CLASS_BIT).filter(([b]) => Math.floor(q.classes / 2 ** (+b - 1)) % 2 === 1).map(([, z]) => z);
    if (own.length && own.length < 9) cls.push(...own);
  }
  if (cls.length) t.push("僅" + [...new Set(cls)].join("／"));
  if ((s.race || []).length) t.push("僅" + [...new Set(s.race)].join("／"));
  if (s.opt) t.push("可跳過");
  if (s.elite) t.push("有隊伍再做");
  if (s.whenever) t.push("之後順路");
  for (const d of s.desc || []) t.push("說明：" + clean(d));
  if (s.id && (!db.quest(s.id) || fixedIds.has(s.id))) t.push("需遊戲實測");
  return t.map((x) => `【${x}】`).join("");
};
const stepLine = (s, map, extraTags = []) => {
  const src = s.id ? ["補充：Guidelime TUGs", "QuestieDB"] : [];
  switch (s.v) {
    case "接": case "交": return `${s.v}｜${qName(s.id)}｜${s.id}｜${clean(s.npc) || "?"}｜${coordText(s, map)} ${tagText(s, [...src, ...extraTags])}`;
    case "做": return `做｜${qName(s.id)}｜${s.id}｜${clean(s.obj)}｜${[coordText(s, map), ...(s.more || []).map((p) => coordText(p, map))].join("／")} ${tagText(s, [...src, ...extraTags])}`;
    case "鳥": return `鳥｜${s.node}｜${coordText(s, map)}`;
    case "爐": return `爐｜${s.bind}`;
    case "飛": return `飛｜${s.to} ${tagText(s)}`.trim();
    case "船": return `船｜${s.to}｜${s.from || ""} ${tagText(s)}`.trim();
    case "練": return `練｜${s.lv} ${tagText(s)}`.trim();
    case "到": return `到｜${clean(s.text)}｜${coordText(s, map)} ${tagText(s)}`.trim();
    case "交通": return `交通｜${clean(s.text)} ${tagText(s)}`.trim();
    case "註": return `註｜${clean(s.text)} ${tagText(s)}`.trim();
    case "買": return `買｜${itemZh(s.item)} ×${s.n}｜${s.item}｜${s.fq || ""}｜${clean(s.npc)}｜${s.x === undefined ? "" : coordText(s, map)} ${tagText(s, ["QuestieDB"])}`.trim();
  }
  return "";
};
const stationBlock = (st) => {
  const out = [`## 第${st.num}站｜${st.name}（${st.lv[0]}–${st.lv[1]}）`, `- 限定｜${st.only || "無"}`, "- 二選一｜無", `- 地圖 ID｜${st.map}`];
  if (st.travel) out.push(`- 交通｜${st.travel}`);
  out.push("- 步驟", "");
  st.steps.forEach((s, k) => out.push(`${k + 1}. ${stepLine(s, st.map)}`));
  const sup = [...new Set(st.vendors)].map((id) => db.npc(id)).filter(Boolean).map((n) => ({ n, at: clusterCenter(n.spawns.filter((p) => p.map === st.map)) })).filter((x) => x.at);
  if (sup.length) { out.push(""); for (const { n, at } of sup) out.push(`- 補給｜修理｜${n.zhTW || n.en}｜${at.map} ${fmt(at.x)}, ${fmt(at.y)}`); }
  return out.join("\n");
};
const HEAD = {
  "01": ["# 聯盟 1–12 級起始路線", "",
    "選一條起始路線：人類走北郡山谷與艾爾文森林，矮人與地精走寒脊山谷與丹莫洛，夜精靈走幽影谷與泰達希爾，三條都在 9–11 級會合到丹莫洛與洛克莫丹。天裔精靈走微風島，離島後直接搭船到黑海岸。站首「限定」是插件辨識各族預設出生路線的欄位，所有聯盟角色均可自選起點。接、做、交步驟行尾的【僅某種族】或【僅某職業】標實際限制，其他角色略過該步。跨圖座標前加地圖 ID，查不到的台服名稱或座標以「?」表示。", "",
    "- [Guidelime TUGs 永恆版 1.60.1](https://www.curseforge.com/wow/addons/guidelime_tugs)（只取任務順序與 ID）", ""],
  "02": ["# 聯盟 12–30 級路線", "", "從黑海岸開始，往返東部王國與卡林多。跨圖座標前加地圖 ID。副本任務另列在 05-副本。", ""],
  "03": ["# 聯盟 30–45 級路線", "", "濕地、荊棘谷、阿拉希高地、塵泥沼澤、荒蕪之地到塔納利斯與菲拉斯。跨圖座標前加地圖 ID。精英任務標【有隊伍再做】。", ""],
  "04": ["# 聯盟 45–60 級路線", "", "塔納利斯、辛特蘭、灼熱峽谷、安戈洛環形山、費伍德森林，最後到燃燒平原與東西瘟疫之地。跨圖座標前加地圖 ID。", ""],
};
const FILE_NAME = { "01": "01-第一段-1到12級.md", "02": "02-12到30級.md", "03": "03-30到45級.md", "04": "04-45到60級.md" };
mkdirSync(OUT, { recursive: true });
let stepCount = 0;
for (const no of ["01", "02", "03", "04"]) {
  const list = stations.filter((x) => x.no === no);
  stepCount += list.reduce((n, x) => n + x.steps.length, 0);
  writeFileSync(join(OUT, FILE_NAME[no]), [...HEAD[no], ...list.map(stationBlock).flatMap((b) => [b, ""])].join("\n"));
}

// 05 副本
const dungeonBlocks = [];
dungeons.sort((a, b) => a.after - b.after);
for (const d of dungeons) {
  const info = DUNGEON.get(d.area);
  const zh = DUNGEON_ZH[d.area] || info.name;
  const qs = d.steps.filter((s) => s.id).map((s) => db.quest(s.id)).filter(Boolean);
  const lv = HORDE_LV.get(db.norm(info.name)) || HORDE_LV.get(db.norm(info.name.replace(/^The /, ""))) || [Math.max(1, Math.min(...qs.map((q) => q.level)) - 2), Math.max(...qs.map((q) => q.level)) + 3];
  const anchor = stations[d.after];
  const firstDo = d.steps.findIndex((s) => s.v === "做");
  const lastDo = d.steps.map((s) => s.v).lastIndexOf("做");
  const phase = (s, k) => {
    if (s.v === "做") return "in";
    // 給任務的人／物件只在副本裡（沒有室外座標）：副本內
    if ((s.v === "接" || s.v === "交") && (s.inDungeon || (s.x === undefined && !(s.v === "接" && k < firstDo)))) return "in";
    if (s.v === "接") return k < firstDo || firstDo < 0 ? "pre" : s.inDungeon || s.item ? "in" : "post";
    if (s.v === "交") return s.inDungeon && k <= lastDo ? "in" : k < firstDo ? "pre" : "post";
    return k <= firstDo || firstDo < 0 ? "pre" : "post";
  };
  const ph = { pre: [], in: [], post: [] };
  d.steps.forEach((s, k) => ph[phase(s, k)].push(s));
  const ent = info.entrance;
  const out = [`## 副本｜${zh}（${info.name}）（建議等級 ${lv[0]}–${lv[1]}）｜插入於 ${anchor.no}-第${anchor.num}站之後`, ""];
  if (ent.map) out.push(`- 入口｜${ZH[ent.map] || ""} ${ent.map} ${fmt(ent.x)}, ${fmt(ent.y)} 【QuestieDB】`);
  const inst = INSTANCES.get(d.area);
  if (inst) out.push(`- 副本ID｜${inst}`);
  if (d.pickAt !== d.after) { const pk = stations[d.pickAt]; out.push(`- 前置接取路線｜【接取錨點 ${pk.no}-第${pk.num}站】走到${pk.name}時先接進本前的任務，進本前不必專程回頭。`); }
  out.push("");
  let n = 0;
  const map = anchor.map;
  for (const [key, title] of [["pre", "進本前要接"], ["in", "副本內"], ["post", "出本後交"]]) {
    if (!ph[key].length) continue;
    out.push(`- ${title}`, "");
    for (const s of ph[key]) {
      // 副本內：離入口遠的點多半是別區同名怪／物件，不給座標
      if (key === "in" && s.x !== undefined && !(ent.map && s.map === ent.map && dist(s, ent) < 25)) { s.x = s.y = undefined; s.map = undefined; s.more = []; }
      const q = s.id && db.quest(s.id);
      const extra = s.v === "接" && q ? [`接取等級 ${q.reqLevel || 1}`, `建議等級 ${q.level}`] : [];
      out.push(`${++n}. ${stepLine(s, map, extra)}`);
    }
    out.push("");
  }
  dungeonBlocks.push(out.join("\n"));
}
writeFileSync(join(OUT, "05-副本.md"), ["# 聯盟 1–60 級副本路線", "",
  "組隊練級可在標示站點選擇進本。每段先核對隊友、角色等級和已接前置。建議等級是組隊區間，接取等級以本機 QuestieDB Forever 為準。挖掘場：溼地與諾莫瑞根的 TUGs 骨架尚未完成，諾莫瑞根只列進本前後的任務。", "",
  ...dungeonBlocks].join("\n"));

// 06 路線外任務
const ALLY = 4294967373n;
const allyOk = (q) => !q.races || (BigInt(q.races) & ALLY) !== 0n;
const SORT = { "-61": "職業任務", "-81": "職業任務", "-82": "職業任務", "-141": "職業任務", "-161": "職業任務", "-162": "職業任務", "-261": "職業任務", "-262": "職業任務", "-263": "職業任務",
  "-24": "專業任務", "-101": "專業任務", "-121": "專業任務", "-181": "專業任務", "-182": "專業任務", "-201": "專業任務", "-264": "專業任務", "-304": "專業任務", "-324": "專業任務" };
const stationOfMap = (map, lvl) => stations.filter((st) => st.steps.some((s) => s.map === map)).sort((a, b) => Math.abs(a.lv[0] - lvl) - Math.abs(b.lv[0] - lvl))[0];
// 路線任務的前置（遞迴）：路線外的前置都值得做
const feedAll = new Map();
const walk = (qid, root, seen) => { const q = db.quest(qid); if (!q) return; for (const p of [...q.preGroup, ...q.preSingle]) { if (seen.has(p)) continue; seen.add(p); if (!routeQuests.has(p) && !feedAll.has(p)) feedAll.set(p, [root]); walk(p, root, seen); } };
for (const id of routeQuests) walk(id, id, new Set());
const off = new Map();
for (const id of db.allQuestIds()) {
  if (routeQuests.has(id)) continue;
  const q = db.quest(id);
  if (!q || !allyOk(q)) continue;
  const lvl = q.level > 0 ? q.level : q.reqLevel;
  if (!lvl || lvl > 60 || q.reqLevel > 60) continue;
  if (!q.zhTW && !q.en) continue;
  const z = q.zoneOrSort;
  const giver = giverSpawns(q, false).spawns.filter((p) => !inDungeonMap(p.map));
  const gmap = giver.length ? clusterCenter(giver).map : undefined;
  let region, v, why;
  const feed = feedAll.get(id);
  const dArea = DUNGEON_OF.get(z);
  if (z < 0 && SORT[String(z)] === undefined) { region = "節慶與其他"; v = "可放掉"; why = "節慶或特殊分類任務，依活動開放再做，不影響練級。"; }
  else if (z < 0) {
    region = SORT[String(z)];
    if (feed) { v = "值得做"; why = `是路線任務「${db.quest(feed[0])?.zhTW || feed[0]}」的前置，先補做才接得到。`; }
    else if (region === "專業任務") { v = "可放掉"; why = "專業任務，有練這項專業再做。"; }
    else { v = "之後順路"; why = "職業任務，到接取點附近或回主城訓練時順手處理。"; }
  } else if (dArea) { region = DUNGEON_ZH[dArea] || DUNGEON.get(dArea).name; v = "之後順路"; why = "副本任務，路線的副本段沒列；組隊進本前再接。"; }
  else {
    const map = areaToUi.get(z) || gmap;
    region = ZH[map] || (map ? `地圖 ${map}` : "未分類");
    const st = map && stationOfMap(map, lvl);
    if (feed) { v = "值得做"; why = `是路線任務「${db.quest(feed[0])?.zhTW || feed[0]}」的前置，先補做才接得到。`; }
    else if (st && Math.abs(st.lv[0] - lvl) <= 6) { v = "之後順路"; why = `${st.name}（第${st.num}站）經過時，有空再接。`; }
    else if (st) { v = "可放掉"; why = "路線經過該區時等級落差大，跳過不影響練級。"; }
    else { v = "可放掉"; why = "路線不經過這區，跳過不影響練級。"; }
  }
  if (!off.has(region)) off.set(region, []);
  off.get(region).push(`${id}｜${clean(q.zhTW || q.en)}｜${lvl}｜${region}｜${v}｜${why}`);
}
let offCount = 0;
const offOut = ["# 聯盟 1–60 路線外任務", "",
  "以 01–05 的任務步驟為比對範圍，列出聯盟角色可接、等級 60 以內、路線沒排到的任務。等級欄使用 QuestieDB 任務等級，動態等級顯示最低可接等級。",
  "台服名稱採 QuestieDB，暫缺繁中時沿用英文。區域優先採任務日誌的區域，職業、專業、節慶另外分組。判定是自動初判（前置→值得做；路線經過且等級接近→之後順路；其餘→可放掉），需要再人工複查。", ""];
for (const [region, rows] of [...off.entries()].sort((a, b) => a[0].localeCompare(b[0], "zh-Hant"))) {
  offOut.push(`## 區域｜${region}`, "", ...rows.sort((a, b) => +a.split("｜")[2] - +b.split("｜")[2]), "");
  offCount += rows.length;
}
offOut.splice(4, 0, `共 ${offCount} 筆。`);
writeFileSync(join(OUT, "06-路線外任務.md"), offOut.join("\n"));

// 07 訓練師
const TRAINERS = {
  戰士: [["Llane Beshere", "北郡山谷", [4, 6], "僅人類"], ["Lyria Du Lac", "艾爾文森林 閃金鎮", [6, 8, 10], "僅人類"], ["Thran Khorman", "寒脊山谷", [4, 6], "僅矮人,地精"], ["Granis Swiftaxe", "丹莫洛 卡拉諾斯", [6, 8, 10], "僅矮人,地精"], ["Alyissia", "幽影谷", [4, 6], "僅夜精靈"], ["Kyra Windblade", "泰達希爾 多蘭納爾", [6, 8, 10], "僅夜精靈"], ["Ander Germaine", "暴風城", [], ""], ["Bilban Tosslespanner", "鐵爐堡", [], ""], ["Arias'ta Bladesinger", "達納蘇斯", [], ""]],
  聖騎士: [["Brother Sammuel", "北郡山谷", [4, 6], "僅人類"], ["Brother Wilhelm", "艾爾文森林 閃金鎮", [6, 8, 10], "僅人類"], ["Bromos Grummner", "寒脊山谷", [4, 6], "僅矮人"], ["Azar Stronghammer", "丹莫洛 卡拉諾斯", [6, 8, 10], "僅矮人"], ["Arthur the Faithful", "暴風城", [], ""], ["Brandur Ironhammer", "鐵爐堡", [], ""]],
  獵人: [["Thorgas Grimson", "寒脊山谷", [4, 6], "僅矮人"], ["Grif Wildheart", "丹莫洛 卡拉諾斯", [6, 8, 10], "僅矮人"], ["Ayanna Everstride", "幽影谷", [4, 6], "僅夜精靈"], ["Dazalar", "泰達希爾 多蘭納爾", [6, 8, 10], "僅夜精靈"], ["Daera Brightspear", "鐵爐堡", [], ""], ["Jocaste", "達納蘇斯", [], ""]],
  盜賊: [["Jorik Kerridan", "北郡山谷", [4, 6], "僅人類"], ["Keryn Sylvius", "艾爾文森林 閃金鎮", [6, 8, 10], "僅人類"], ["Solm Hargrin", "寒脊山谷", [4, 6], "僅矮人,地精"], ["Hogral Bakkan", "丹莫洛 卡拉諾斯", [6, 8, 10], "僅矮人,地精"], ["Frahun Shadewhisper", "幽影谷", [4, 6], "僅夜精靈"], ["Jannok Breezesong", "泰達希爾 多蘭納爾", [6, 8, 10], "僅夜精靈"], ["Osborne the Night Man", "暴風城", [], ""], ["Hulfdan Blackbeard", "鐵爐堡", [], ""], ["Syurna", "達納蘇斯", [], ""]],
  牧師: [["Priestess Anetta", "北郡山谷", [4, 6], "僅人類"], ["Priestess Josetta", "艾爾文森林 閃金鎮", [6, 8, 10], "僅人類"], ["Branstock Khalder", "寒脊山谷", [4, 6], "僅矮人"], ["Maxan Anvol", "丹莫洛 卡拉諾斯", [6, 8, 10], "僅矮人"], ["Shanda", "幽影谷", [4, 6], "僅夜精靈"], ["Laurna Morninglight", "泰達希爾 多蘭納爾", [6, 8, 10], "僅夜精靈"], ["High Priestess Laurena", "暴風城", [], ""], ["Braenna Flintcrag", "鐵爐堡", [], ""], ["Jandria", "達納蘇斯", [], ""]],
  法師: [["Khelden Bremen", "北郡山谷", [4, 6], "僅人類"], ["Zaldimar Wefhellt", "艾爾文森林 閃金鎮", [6, 8, 10], "僅人類"], ["Marryk Nurribit", "寒脊山谷", [4, 6], "僅地精"], ["Magis Sparkmantle", "丹莫洛 卡拉諾斯", [6, 8, 10], "僅地精"], ["Jennea Cannon", "暴風城", [], ""], ["Dink", "鐵爐堡", [], ""]],
  術士: [["Drusilla La Salle", "北郡山谷", [4, 6], "僅人類"], ["Maximillian Crowe", "艾爾文森林 閃金鎮", [6, 8, 10], "僅人類"], ["Alamar Grimm", "寒脊山谷", [4, 6], "僅地精"], ["Gimrizz Shadowcog", "丹莫洛 卡拉諾斯", [6, 8, 10], "僅地精"], ["Ursula Deline", "暴風城", [], ""], ["Briarthorn", "鐵爐堡", [], ""]],
  德魯伊: [["Mardant Strongoak", "幽影谷", [4, 6], "僅夜精靈"], ["Kal", "泰達希爾 多蘭納爾", [6, 8, 10], "僅夜精靈"], ["Sheldras Moontree", "暴風城", [], ""], ["Mathrengyl Bearwalker", "達納蘇斯", [], ""]],
};
const CITY_MAP = { 暴風城: 1453, 鐵爐堡: 1455, 達納蘇斯: 1457 };
const trainerOut = ["# 聯盟職業訓練師與學技能站", "",
  "格式為「職業｜等級｜地點｜NPC｜座標｜順路時機」。等級欄是建議回訪時機，可學技能以訓練視窗為準。出生地依種族各自走，進主線後在路線經過的主城補技能。天裔精靈的島上訓練師見部落版 07（微風島共用）。", "",
  "## 各職業建議回訪等級", ""];
const trainerMissing = [];
for (const [cls, list] of Object.entries(TRAINERS)) {
  trainerOut.push(`### ${cls}`, "");
  for (const [en, place, lvs, only] of list) {
    const id = db.idByEn("Npc", en);
    const n = id && db.npc(id);
    if (!n) { trainerMissing.push(`${cls} ${en}`); continue; }
    const cityMap = CITY_MAP[place];
    const at = clusterCenter(n.spawns.filter((p) => !cityMap || p.map === cityMap)) || clusterCenter(n.spawns);
    let levels = lvs, when;
    if (cityMap) {
      const visits = stations.filter((st) => st.lv[0] >= 10 && st.steps.some((s) => s.map === cityMap));
      levels = [...new Set(visits.map((st) => st.lv[0] + (st.lv[0] % 2)))].sort((a, b) => a - b);
      if (!levels.length) continue;
      when = `路線經過${place}時補技能（${visits.slice(0, 3).map((st) => `${st.no}-第${st.num}站`).join("、")}${visits.length > 3 ? "…" : ""}）。`;
    } else when = `${place}回交任務時補技能。`;
    trainerOut.push(`- ${cls}｜${levels.join("、")}｜${place}｜${n.zhTW || en}（${en}）｜${at ? `${at.map} ${fmt(at.x)}, ${fmt(at.y)}` : "?"}｜${when}【QuestieDB Forever】${only ? `【${only}】` : ""}`);
  }
  trainerOut.push("");
}
writeFileSync(join(OUT, "07-訓練師.md"), trainerOut.join("\n"));

// 08 保留物品：從物品開始的任務、要先買的任務物品
const keepRows = new Map();
const stationOf = (s) => stations.find((st) => st.steps.includes(s));
for (const st of stations) for (const s of st.steps) {
  if (s.v === "接" && s.item) {
    const q = db.quest(s.id);
    const turn = stations.find((x) => x.steps.some((o) => o.v === "交" && o.id === s.id));
    keepRows.set(s.item, `- ${itemZh(s.item)}｜${s.item}｜${st.name}，打怪或拾取時取得｜${clean(q?.zhTW || q?.en)}（${s.id}），${turn ? turn.name : st.name}`);
  }
  if (s.v === "買" && s.fq) {
    const q = db.quest(s.fq);
    keepRows.set(s.item, `- ${itemZh(s.item)}｜${s.item}｜${st.name}，向${s.npc || "商人"}購買 ${s.n} 個｜${clean(q?.zhTW || q?.en)}（${s.fq}），${(stationOf(allSeq.slice(allSeq.indexOf(s)).find((o) => o.id === s.fq)) || st).name}`);
  }
}
writeFileSync(join(OUT, "08-保留物品.md"), ["# 保留物品", "",
  "下表收錄聯盟路線中從物品開始的任務，以及要先買好的任務材料。若任務從物品開啟，先右鍵接取再確認任務日誌。", "",
  "每列依序為物品名｜物品ID｜何時拿到（地名）｜何時用到（任務名、地名）。", "", "## 1–60 級", "", ...keepRows.values(), ""].join("\n"));
copyFileSync(join(ROOT, "route", "xp-table.md"), join(OUT, "xp-table.md"));

writeFileSync(NOTES_OUT, [`# 匯入紀錄`, ``, `## 未處理的 TUGs 自由文字（${unknownNotes.length}）`, ...unknownNotes, ``, `## QuestieDB 沒有的任務（${missingQuests.size}）`, ...[...missingQuests].map(String),
  ``, `## 只有佔位內容的 TUGs 檔`, ...placeholders, ``, `## 標成專程繞路的任務（${detours.length}）`, ...detours, ``, `## 找不到的訓練師`, ...trainerMissing, ``].join("\n"));
console.log(`站 ${stations.length}、副本段 ${dungeons.length}、步驟 ${stepCount}、路線任務 ${routeQuests.size}、純對話去掉「做」${talkDropped}、繞路 ${detours.length}、路線外 ${offCount}、未處理文字 ${unknownNotes.length}、缺任務 ${missingQuests.size}`);
