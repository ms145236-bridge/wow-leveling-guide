// 離線建置：route/*.md → addon/ShengLeveling/Data/Route.lua + tools/unresolved.md
// 用法：node tools/build.mjs
// 缺任務 ID／座標時查 QuestieDB（zhTW、zhCN、enUS 名稱）。有「找不到／多個候選」時以結束碼 1 結束（輸出仍會寫出）。
//
// 路線寫法補充：
// - 職業任務段落：### 職業（可加種族）｜N 級｜第M站
//   預設排在第M站站尾的交通前面。要指定位置就在標題後面加一段：
//     ｜插在 #K 之後／｜插在 #K 之前（K＝該站步驟行開頭的編號，例如「91. 船｜棘齒城｜藏寶海灣」的 91）
//     ｜插在「船｜棘齒城」之後（引號裡寫該站某一步的開頭文字：動詞｜第一欄…，比對時不看【】標籤）
//   指定位置時，段落最後一個座標和插入點後面第一個有座標的主線步驟不在同一張地圖（或相距超過 10 格），
//   會自動補一步「回到路線：地圖 座標」（只給這個職業）；段落最後一步自己寫了交通／飛／船／爐就不補。
// - 爐｜X：用爐石回 X（軟步驟）。用了爐石並換區時勾掉；人已經在 X（zhTW 客戶端比區域名）、走到下一步附近、或後面的任務做了也算過了。
// - 交通文字有「綁爐石」（例如「在X旅店綁爐石」「到X找旅店老闆…綁爐石」「綁X爐石」）：改成綁爐石步驟，
//   爐石綁到 X（GetBindLocation）才勾；地點認不出來時，在這步收到 HEARTHSTONE_BOUND 就勾。
//   「已綁／仍綁／不改／保留…」這類說明、「可改找／可在…綁爐石」這類選擇性的不算。
// - 交通文字有好幾個座標：依序指路，走到最後一個才算到（船、飛照舊）。
import { readFileSync, writeFileSync, readdirSync, existsSync } from "node:fs";
import { createHash } from "node:crypto";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { ADDONS, openQuestieDB, clusterCenter, localVersion, readSnapshot, diffSnapshot, SNAPSHOT_COLS, SNAPSHOT_GONE } from "./questiedb.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
// 任務目標座標（tools/objective-coords.md，Codex 查的 Wowhead 永恆版／QuestieDB 點位）：補到「做」步驟的 more
// 一列＝一個目標實體（怪／物件／掉落來源）在一張地圖上的點：{ tid, name, map, pts }；同實體同地圖的列合併
const OBJ = new Map();
let objAdded = 0;
for (const line of readFileSync(join(ROOT, "tools", "objective-coords.md"), "utf8").split(/\r?\n/)) {
  const f = line.split("｜");
  if (f.length < 5 || !/^\d+$/.test(f[0]) || !/^\d+$/.test(f[3])) continue;
  const pts = f[4].split(";").map((p) => p.split(",").map(Number)).filter((p) => p.length === 2 && p.every(Number.isFinite)).map(([x, y]) => ({ map: +f[3], x, y }));
  if (!pts.length) continue;
  const tid = (f[2].match(/#(\d+)/) || [])[1] || f[2], ents = OBJ.get(+f[0]) || [];
  const same = ents.find((e) => e.tid === tid && e.map === +f[3]);
  if (same) same.pts.push(...pts);
  else ents.push({ tid, name: f[2].split(/\s*[#（(×]/)[0].trim(), map: +f[3], pts });
  OBJ.set(+f[0], ents);
}
// 陣營：FACTION=A 建聯盟（route-alliance → Data/RouteA*.lua），預設部落
const ALLY = process.env.FACTION === "A";
const ROUTE = process.env.ROUTE_DIR || join(ROOT, ALLY ? "route-alliance" : "route"); // 測試時可指到別的資料夾
const OUT = process.env.OUT_LUA || join(ROOT, "addon", "ShengLeveling", "Data", ALLY ? "RouteA.lua" : "Route.lua");
const REPORT = process.env.OUT_REPORT || join(ROOT, "tools", ALLY ? "unresolved-alliance.md" : "unresolved.md");
const LUA_PREFIX = ALLY ? "RouteA" : "Route"; // 語系檔：Route_<loc>.lua／RouteA_<loc>.lua
// 只載入自己陣營的路線（天裔精靈創角時就選好陣營，分聯盟、部落兩個種族 ID）
const GUARD = ALLY ? 'if UnitFactionGroup("player") ~= "Alliance" then return end\n' : 'if UnitFactionGroup("player") == "Alliance" then return end\n';

const HORDE = ALLY ? 4294967373n : 8589934770n; // QuestieDB 的本陣營種族遮罩（含永恆新種族位元；聯盟 0x10000004d、部落 0x2000000b2）
const CLASS = { 戰士: "WARRIOR", 獵人: "HUNTER", 薩滿: "SHAMAN", 薩滿祭司: "SHAMAN", 法師: "MAGE", 術士: "WARLOCK", 盜賊: "ROGUE", 德魯伊: "DRUID", 牧師: "PRIEST", 聖騎士: "PALADIN" };
const RACE = { 獸人: "Orc", 食人妖: "Troll", 牛頭人: "Tauren", 不死族: "Scourge", 亡靈: "Scourge", 被遺忘者: "Scourge", 血精靈: "BloodElf", 人類: "Human", 矮人: "Dwarf", 夜精靈: "NightElf", 地精: "Gnome", 德萊尼: "Draenei" };
const ZONE_MAP = { 杜洛塔: 1411, 莫高雷: 1412, 貧瘠之地: 1413, 提里斯法林地: 1420, 銀松森林: 1421, 石爪山脈: 1442, 梣谷: 1440, 灰谷: 1440, 千針石林: 1441, 希爾斯布萊德丘陵: 1424, 奧特蘭克山脈: 1416, 阿拉希高地: 1417, 塵泥沼澤: 1445, 荊棘谷: 1434, 淒涼之地: 1443, 菲拉斯: 1444, 塔納利斯: 1446, 辛特蘭: 1425, 悲傷沼澤: 1435, 荒蕪之地: 1418, 灼熱峽谷: 1427, 艾薩拉: 1447, 奧格瑪: 1454, 幽暗城: 1458, 雷霆崖: 1456 };
// ── 英文介面（Data/Route_enUS.lua）用的對照：站名、鳥點、步驟標籤。沒有對照的站名在遊戲裡用地圖名 ──
const STATION_EN = {
  試煉谷: "Valley of Trials", "杜洛塔 森金村／剃刀嶺": "Durotar: Sen'jin & Razor Hill", 納拉其營地: "Camp Narache", "莫高雷 血蹄村": "Mulgore: Bloodhoof Village",
  喪鐘鎮: "Deathknell", "提里斯法林地 布瑞爾": "Tirisfal Glades: Brill", 銀松森林: "Silverpine Forest", "貧瘠之地 十字路口": "The Barrens: Crossroads",
  "貧瘠之地 棘齒城短訪": "The Barrens: Ratchet (short visit)", "貧瘠之地 棘齒城／陶拉祖營地": "The Barrens: Ratchet & Camp Taurajo", 石爪山脈: "Stonetalon Mountains",
  梣谷: "Ashenvale", 希爾斯布萊德丘陵: "Hillsbrad Foothills", 千針石林: "Thousand Needles", "千針石林 亂風崗與閃光平原": "Thousand Needles: Freewind Post & Shimmering Flats",
  奧特蘭克山脈: "Alterac Mountains", 阿拉希高地: "Arathi Highlands", "阿拉希高地 落錘鎮第一次": "Arathi Highlands: Hammerfall", "阿拉希高地 落錘鎮第二次": "Arathi Highlands: Hammerfall",
  "塵泥沼澤 蕨牆村": "Dustwallow Marsh: Brackenwall Village", "荊棘谷 第一次": "Stranglethorn Vale", "荊棘谷 第二次": "Stranglethorn Vale", "荊棘谷 藏寶海灣回訪": "Stranglethorn Vale: Booty Bay (return)",
  "淒涼之地 葬影村第一次": "Desolace: Shadowprey Village", "淒涼之地 葬影村第二次": "Desolace: Shadowprey Village",
  "荒蕪之地 卡加斯": "Badlands: Kargath", "灼熱峽谷 瑟銀哨塔": "Searing Gorge: Thorium Point", "燃燒平原 烈焰峰與黑石山": "Burning Steppes: Flame Crest & Blackrock Mountain",
  "悲傷沼澤 斯通納德": "Swamp of Sorrows: Stonard", "悲傷沼澤 斯通納德與東風海岸第二次": "Swamp of Sorrows: Stonard",
  "塔納利斯 熱砂港與加基森第一次": "Tanaris: Steamwheedle Port & Gadgetzan", "塔納利斯 加基森與破碎石柱": "Tanaris: Gadgetzan & Broken Pillar", "塔納利斯 加基森與砂槌營地第二次": "Tanaris: Gadgetzan & Sandfury camp",
  "菲拉斯 莫沙徹營地第一次": "Feralas: Camp Mojache", "菲拉斯 莫沙徹營地與怒痕堡第二次": "Feralas: Camp Mojache & Dire Maul", "菲拉斯 莫沙徹營地短訪": "Feralas: Camp Mojache (short visit)",
  "菲拉斯 莫沙徹營地回訪": "Feralas: Camp Mojache (return)", "菲拉斯 第四次": "Feralas", "辛特蘭 惡齒村與辛薩羅": "The Hinterlands: Revantusk & Jintha'Alor",
  "艾薩拉 瓦羅莫克與阿克科蘭神殿": "Azshara: Valormok & Temple of Arkkoroc", "安戈洛環形山 馬紹爾營地第一次": "Un'Goro Crater: Marshal's Refuge", "安戈洛環形山 第二次": "Un'Goro Crater",
  "費伍德森林 南段與血毒崗哨": "Felwood: South & Bloodvenom Post", "費伍德森林 血毒崗哨至木喉要塞": "Felwood: Bloodvenom Post to Timbermaw Hold", "費伍德森林 第三次": "Felwood",
  "月光林地 第一次": "Moonglade", "月光林地 第二次": "Moonglade", "冬泉谷 永望鎮第一次": "Winterspring: Everlook", "冬泉谷 第二次": "Winterspring", "冬泉谷 第三次": "Winterspring",
  希利蘇斯: "Silithus", "西瘟疫之地 亡靈壁壘第一次": "Western Plaguelands: The Bulwark", "西瘟疫之地 第二次": "Western Plaguelands", "西瘟疫之地 第三次": "Western Plaguelands",
  "東瘟疫之地 聖光之願禮拜堂第一次": "Eastern Plaguelands: Light's Hope Chapel", "東瘟疫之地 第二次": "Eastern Plaguelands", "詛咒之地 血法師營地": "Blasted Lands",
  "血色修道院 墓地": "Scarlet Monastery: Graveyard", "血色修道院 圖書館": "Scarlet Monastery: Library", "血色修道院 軍械庫": "Scarlet Monastery: Armory", "血色修道院 大教堂": "Scarlet Monastery: Cathedral",
  "斯坦索姆 血色區": "Stratholme: Live", "斯坦索姆 亡靈區": "Stratholme: Undead", "厄運之槌 東區": "Dire Maul: East", "厄運之槌 西區": "Dire Maul: West", "厄運之槌 北區": "Dire Maul: North",
};
const NODE_EN = { 血蹄村: "Bloodhoof Village", 剃刀嶺: "Razor Hill", 布瑞爾: "Brill", 申德村: "Shen'dar Village", 瓦拉納爾: "Valanaar", 閃金鎮: "Goldshire", 多蘭納爾: "Dolanaar", 卡拉諾斯: "Kharanos", 安威瑪: "Anvilmar", 奧達希爾: "Aldrassil", 北郡修道院: "Northshire Abbey",
  蕨牆村: "Brackenwall Village", 斯通納德: "Stonard", 卡加斯: "Kargath", 莫沙徹營地: "Camp Mojache", 瑟銀哨塔: "Thorium Point", 惡齒村: "Revantusk Village", 瓦羅莫克: "Valormok",
  馬紹爾營地: "Marshal's Refuge", 烈焰峰: "Flame Crest", 聖光之願禮拜堂: "Light's Hope Chapel", 血毒崗哨: "Bloodvenom Post", 永望鎮: "Everlook", 月光林地: "Moonglade", 塞納里奧城堡: "Cenarion Hold",
  十字路口: "The Crossroads", 奧格瑪: "Orgrimmar", 雷霆崖: "Thunder Bluff", 塔倫米爾: "Tarren Mill", 烈日石居: "Sun Rock Retreat", 葬影村: "Shadowprey Village",
  加基森: "Gadgetzan", 羅格瑪: "Rog'mar", 遠境堡: "Farholde Keep", 污化丘陵: "Tainted Foothills", 永恆山峰: "Summit of Eternity",
  冰風崗: "Chillwind Camp", 刺枝林地: "Talonbranch Glade", 南海鎮: "Southshore", 哨兵嶺: "Sentinel Hill", 塔倫迪斯營地: "Talrendis Point", 塞拉摩: "Theramore", 塞爾薩瑪: "Thelsamar", 奧伯丁: "Auberdine", 達拉然: "Dalaran", 守望堡: "Nethergarde Keep", 尼耶爾前哨站: "Nijel's Point", 摩根的崗哨: "Morgan's Vigil", 暴風城: "Stormwind", 棘齒城: "Ratchet", 湖畔鎮: "Lakeshire", 石爪峰: "Stonetalon Peak", 米奈希爾港: "Menethil Harbor", 薩蘭納爾: "Thalanaar", 藏寶海灣: "Booty Bay", 避難谷地: "Refuge Pointe", 鐵爐堡: "Ironforge", 阿斯特蘭納: "Astranaar", 魯瑟蘭村: "Rut'theran Village", 鷹巢山: "Aerie Peak", 夜色鎮: "Darkshire", 羽月要塞: "Feathermoon Stronghold", 落錘鎮: "Hammerfall", 格羅姆高: "Grom'gol", 碎木崗哨: "Splintertree Post", 亂風崗: "Freewind Post", 陶拉祖營地: "Camp Taurajo", 幽暗城: "Undercity", 瑟伯切爾: "The Sepulcher" };
// 步驟標籤（第 3 行）：整段對得上才翻，對不上的英文介面不顯示
const TAG_EN = { 可跳過: "Optional", 需遊戲實測: "Unverified", 有隊伍再做: "Group", 怪多: "Crowded", 副本前置鏈: "Dungeon prereq", 精英: "Elite", 護送: "Escort", 組隊: "Group",
  副本: "Dungeon", 組隊護送: "Group escort", 有隊伍才下: "Group only", 有隊伍或能單刷: "Group or solo", 有掉落才做: "If it drops", 掉落時才做: "If it drops", 掉落觸發: "Drop starts it",
  巡邏掉落觸發: "Drop starts it", 掉落才接: "If it drops", 之後順路: "Later, on the way", 路過才做: "If passing by", 有餘力再做: "If time allows", 有遇到才做: "If you see it", 已遇到才做: "If you see it",
  能打高階怪再做: "Hard", 低等怪補缺口: "Fills an XP gap", 日後順路或有隊伍: "Later or with a group", 見到獵物才接: "If you see it", 材料齊才做: "When you have the items", 看得到才接: "If offered" };
const tagEn = (tag) => { const out = (tag || "").split(/\s*・\s*/).map((t) => TAG_EN[t.trim()]).filter(Boolean); return out.length ? [...new Set(out)].join(", ") : undefined; };
const enText = (t) => String(t || "").replace(/<([^<>\/]+)\/([^<>\/]+)>/g, "$1/$2").replace(/\$[Bb]/g, " ").replace(/\$[Nn]/g, "you").replace(/\$[CcRr]/g, "adventurer").replace(/\s+/g, " ").trim();
const VERB = { 接: "accept", 做: "do", 交: "turnin", 到: "goto", 鳥: "fp", 爐: "hearth", 飛: "fly", 船: "boat", 練: "level", 註: "note", 交通: "travel", 買: "buy", 撿: "buy" };
// 行尾標籤：這些不顯示；其餘（可跳過、有隊伍再做…）顯示在步驟第 3 行
// 條件入口：要先有掉落物、材料、聲望，或遇到巡邏的人才接得到。可跳過的接取步是「物品起始」或帶這些標籤 → 任務記 cond
// 建置不把它升成必做；引擎補經驗時不補還沒接的（Engine.lua FillPlan）
const COND_TAG = /^(掉落才接|有掉落才做|掉落時才做|掉落觸發|巡邏掉落觸發|有遇到才做|已遇到才做|見到獵物才接|撿到水球才接|材料齊才做|頁數齊才做|看得到才接)$/;
// 必做任務的可跳過前置，帶這些理由的不升成必做：精英、怪比你高 3 級、要另外繞路、條件入口
const KEEP_TAG = /^(有隊伍再做|能打高階怪再做|路過才做)$/;
const HIDDEN_TAG = /^(QuestieDB|補充|所在[：:]|影片|有前置|僅|非|說明|\d+\s*級起|接取等級|建議等級|可共享|不可共享|共享|前置[：:]|★|掉率|位置|副本前置[：:]|副本座標|副本區域[：:]|順序|部落可接|需遊戲實測|已開鳥點|未開鳥點|黑海岸分流|排除起點：|種族或起點：|排除種族與起點：|(?:持有|缺少)材料[：:]|舊鍵[：:]|已接任一[：:]|銀幣至少[：:]|副本內接取|出本優先回報|本外完成|當地補接種族[：:]|本次做完後回報|限用路線座標|共用野外前置|計數擊殺[：:]|收取任務物品[：:]|取得後繼續路線|攜物尋訪[：:]|在地辦理[：:]|人在任務點附近|站點區域[：:]|順訪不追回|前任已交[：:]|限真實副本[：:]|手動物品起任|保留主線日誌|裂隙捕捉|就地採集[：:]|自備材料[：:]|交回物品[：:]|副本材料怪[：:]|本內亦可取得[：:]|出本後才提示交件|戰鬥武器[：:]|持有或裝備[：:]|日誌確認互動|目標完成才交[：:]|任務未?失敗[：:]|原生可交|到[：:]|手動順路補接|徽章偵察[：:]|永恆接取等級|到站再預留|背包物品接取[：:]|怪物[：:]|自行選點補級|原進度文字[：:]|隨同交件[：:]|尚可接取[：:]|同一步座標|護送完成才勾|同圖才預覽下一點|安戈洛離站[：:])/;
// 【★獎勵：物品名（職業／職業…）】→ { item, class[] }；「全職業」或沒寫＝不限
const starOf = (tags) => {
  for (const t of tags) {
    const m = t.match(/^★\s*獎勵[：:]\s*(.+?)(?:[（(]([^）)]*)[）)])?\s*$/);
    if (!m) continue;
    const cls = (m[2] || "").split(/[／\/、,，]/).map((x) => CLASS[x.trim()]).filter(Boolean);
    return cls.length ? [m[1].trim(), cls] : [m[1].trim()];
  }
};
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
    else if ((m = t.match(/^前置[：:]\s*(.+)$/))) out.preText = (out.preText ? out.preText + "，" : "") + m[1].trim();
  }
  return out;
};

const db = openQuestieDB();
// 路線明確安排採買的任務物品，不把商人列入擊殺目標。
const boughtForQuest = new Map();
const localDrops = new Map();
const routeMobs = (id) => db.questMobs(id, boughtForQuest.get(id), localDrops.get(id));
// 沿用永恆版 TOC 的順序，後載入的永恆實測值覆蓋初始表。
const XP = new Map();
const xpDir = join(ADDONS, "QuestieDB/support/Forever/QuestXP");
for (const name of ["xpDB-classic.lua", "xpDB-traces.lua"]) {
  const file = join(xpDir, name);
  if (name === "xpDB-traces.lua" && !existsSync(file)) continue; // 相容還沒附實測表的 QuestieDB
  for (const m of readFileSync(file, "utf8").matchAll(/^\s*(?:QuestXP\.db)?\[(\d+)\] = \{\d+, (\d+)\}/gm)) XP.set(+m[1], +m[2]);
}
// QuestieDB 沒有的（多半是永恆新任務）：tools/quest-xp.md 補（Wowhead 永恆版任務頁的獎勵經驗；任務ID｜等級｜經驗）
for (const m of readFileSync(join(ROOT, "tools", "quest-xp.md"), "utf8").matchAll(/^(\d+)｜(\d+)｜(\d+)\s*$/gm)) if (!XP.has(+m[1]) && +m[3] > 0) XP.set(+m[1], +m[3]);
const classBlocks = [];
// 名稱整理：去掉引號類符號、<副標>、「物件／物品」前綴、前後空白，全形空白換半形
// 遊戲內實際名稱跟 QuestieDB 不同的 NPC（玩家在遊戲裡看到的為準，阿莫比玩家紀錄）：QuestieDB 名（cleanName 後）｜遊戲名
const GAME_NAME = {
  "小赫米特·奈辛瓦里": "赫米特·奈辛瓦里", "札爾提": "克薩爾迪", "祖母鷹風": "鷹風酋長的母親", "先知智慧行者": "先知奧薩迪·智慧行者", "小型大地之靈體": "大地之魂", "先知鴉羽": "鴉羽先知", "黑暗教士杜斯滕": "黑暗牧師杜斯滕",
  "黑暗教士貝里爾": "黑暗牧師貝里爾", "蠻兵勞格瑪": "步兵勞格瑪", "大地束縳者馬格蘭": "馬格蘭", "瑞什·長跑者": "瑞什·遠行者", "波卡·捷山": "波卡·雨山", "維茲羅·擦軸人": "維茲羅", "戰歌偵察騎兵": "戰歌偵查騎兵", "監工費蘇勒": "工頭費蘇勒",
  "希爾恩·火衛": "希爾恩·火結", "蠻兵多格蘭": "步兵多格蘭", "魔導師沃迪恩·虛無之光": "大法師沃迪恩·伍德格賴爾", "克拉維爾·濃鬚": "克拉維爾·濃須", "碎泥·杜特非": "馬德克拉什", "沼澤之眼加爾": "「沼澤之眼」加爾",
  "海狼馬克基雷": "「海狼」馬克基雷", "私掠者布勞茲": "海盜布勞茲", "病鬼菲力浦": "「病鬼」菲力浦", "普拉特·雲眼": "普拉特·白雲", "梅納拉·虛無撕裂者": "梅納拉·沃倫德", "隨從溫圖拉": "助手溫圖拉", "隨從瑪迦茲": "助手瑪迦茲",
  "魔導師提爾斯": "大法師提爾斯", "安全主管比格維茲": "安全主管吉羅姆·比格維茲", "首席工程師比格維茲": "首席工程師沙克斯·比格維茲", "威士忌·狡黠": "威士卡斯利姆", "卡拉然·溫布雷": "維拉若克‧溫布雷", "垂釣者卡圖姆": "釣魚者卡圖姆",
  "獵人馬克霍爾": "獵戶馬克霍爾", "薩特拉克·長齒": "薩特拉克", "祭師塞朵拉·穆瓦丹尼": "塞朵拉·穆瓦丹尼", "皇家監督者巴哈烏斯": "皇家管理人巴哈烏斯", "提里恩·弗丁": "提里奧·弗丁", "林格": "林哥", "奧蘭·蛇繞": "奧蘭·斯內克威瑟",
  "莫尼卡·森古斯": "莫尼卡·森古特斯", "馬丁·費爾本醫生": "馬丁·費爾本", "賢者圖希克": "聖者圖希克", "派翠克·加勒特": "派翠克·加瑞特", "暗影法師薇薇安·拉格雷": "暗法師薇薇安·拉格雷", "可敬的萊尼德·巴薩羅梅": "萊尼德·巴薩羅梅",
};
// 遊戲內任務名跟路線／QuestieDB 不同的任務（阿莫比玩家紀錄）：任務 ID｜遊戲名
const QUEST_NAME = {
  5214: "偉大的艾茲拉‧格里姆", // 永恆版任務名稱，見 quest tooltip 5214。
  23: "烏薩苟斯的爪子", 27: "一堂必修的課程", 264: "直到死亡把我們分離", 364: "無腦的殭屍", 382: "十字軍信差", 398: "通緝：蛆眼", 421: "證明你的價值", 439: "腐皮線索", 442: "突襲芬里斯島", 447: "致命配方",
  450: "致命配方", 451: "致命配方", 544: "入室偷竊", 580: "威士卡斯利姆的酒", 752: "一件瑣事", 753: "一件瑣事", 754: "淨化冰蹄之井", 758: "淨化雷角之井", 760: "淨化蠻鬃之井", 794: "燃刃勳章", 825: "海底沉船",
  826: "札拉贊恩", 842: "十字路口的徵兵行動", 852: "赫茲盧爾·血印", 853: "藥劑師札瑪", 869: "迅猛龍小偷", 893: "選擇武器", 894: "什麼什麼平衡器", 900: "什麼什麼平衡器", 901: "什麼什麼平衡器", 902: "什麼什麼平衡器",
  1062: "哥布林侵略者", 1098: "影牙城堡裡的亡靈哨兵", 1444: "向費澤盧爾覆命", 1506: "甘盧爾的召喚", 1840: "歐姆·石蹄和野蠻頭盔", 1918: "被污染的水元素", 1943: "食人妖法師迪諾", 2605: "口渴的哥布林",
  2822: "品質的保證", 2843: "出發！諾姆瑞根！", 2903: "作戰計畫", 2904: "一團混亂", 2945: "髒兮兮的戒指", 2973: "新斗篷的光輝", 2975: "菲拉斯的巨魔", 2980: "菲拉斯的巨魔", 3042: "食人妖調和劑",
  3090: "被污染的羊皮紙", 3099: "被污染的卷軸", 3122: "向巫醫尤克里回覆", 3221: "與倫法洛會面", 3376: "打斷尖牙！", 3380: "沉沒的神廟", 3523: "剃刀高地的天譴軍團", 3783: "雪怪計畫！", 3822: "克羅格盧爾",
  4102: "淨化費伍德", 4120: "腐化的力量", 4136: "雷布里·斯庫比格特", 4145: "拉里安和莫爾金", 4147: "瑪爾馮的工坊", 4641: "你在世上的定位", 4767: "雙足飛龍", 4881: "暗殺計畫", 4961: "奧拉赫寶珠的淨化",
  4976: "歸還淨化過的寶珠", 5041: "十字路口的補給物資", 5051: "合二為一", 5052: "阿迦瑪甘的血岩碎片", 5062: "聖火", 5064: "偵察恐怖圖騰族", 5083: "冬泉火水", 5214: "偉大的艾茲拉‧格里姆", 5251: "文獻管理員",
  5534: "基姆加爾「丟失」的裝備", 5863: "砂槌巨魔", 5901: "瘟疫與你", 5928: "回應召喚", 6162: "最後一戰", 6283: "血怒一族", 6382: "梣谷狩獵", 6383: "梣谷狩獵", 6421: "滾岩峽谷", 6462: "食人妖符咒",
  6482: "盧爾的自由", 6503: "梣谷先驅者", 6545: "戰歌信差的報告", 6546: "戰歌偵查騎兵的報告", 6561: "黑澗深淵中的惡魔", 6564: "上古之神的僕從", 6565: "上古之神的僕從", 7029: "維利塔恩的污染", 7064: "大地的污染",
  7723: "該死的胖手指！", 7724: "熔岩蜘蛛的威脅！", 7727: "燻火龍", 7816: "加莫里塔！", 8254: "幫助塞納里奧", 93430: "取回誘餌", 93680: "城市鑰匙", 94480: "敵人的禮物", 94556: "逃脫的忠忠",
  94672: "侵略暮光", 94680: "暮光信函", 94727: "發掘答案", 94744: "迷途的戰士", 94745: "開闢道路", 94748: "斷開鎖鏈", 94968: "馬戈之眼", 94971: "聖騎士的戰騎", 94972: "暮光典籍", 95121: "美味海味",
  95162: "收集白牙豬肉", 95163: "把牠們趕回去", 95183: "第一步：石頭", 95278: "是時候了，兄弟…", 95417: "紫色傢伙們", 95418: "散播傳言", 95420: "巨人之地", 95424: "以力服人", 95425: "不夠格的勇士",
  95428: "鈍拳的命令", 95601: "紫色傢伙們", 95602: "惱人光芒", 95748: "古拉巴什古代傳說", 95770: "定位失落之城", 95951: "現拿現削", 95955: "捅個痛快", 96026: "第二步：更多石頭", 96103: "禿鷲饗宴",
  96104: "陸行鳥之歌", 96105: "野原之王", 96108: "毒液小撇步", 96109: "獵人的箭袋", 96997: "死馬和活馬一樣強", 97022: "向丹妮莎報告", 97332: "二度落空的信任", 97530: "清算流沙之槌", 97534: "殘骸任務",
};
const cleanName = (n) => String(n || "").replace(/<[^>]*>/g, "").replace(/[『』「」《》“”"]/g, "").replace(/^(物件|物品)\s*/, "").replace(/　/g, " ").trim();
const gameName = (n) => GAME_NAME[cleanName(n)] || cleanName(n);
const questName = (q) => QUEST_NAME[q.id] || q.zhTW || q.en;
const enDiff = { quest: 0, npc: 0, tgt: 0 };
// 永恆 enUS 名稱查核表（tools/english-names.md，Codex 依任務／NPC／物件 ID 查 Wowhead Forever 與客戶端資料）：英文名以它為準，QuestieDB 是備援
// 任務表：任務ID｜中文名｜英文名｜NPC中文｜NPC英文｜來源；訓練師表：職業｜等級｜原文｜英文｜…；補給表：原文｜英文｜…
const MD_QUEST = new Map(); // 任務 ID → 英文任務名
const MD_ENT = new Map(); // "任務ID|名稱" → 英文（"?" 開頭＝查無）
const MD_NAME = new Map(); // 名稱 → 英文（訓練師、補給、練怪用）
{
  const key = (n) => db.norm(cleanName(n));
  for (const line of readFileSync(join(ROOT, "tools", "english-names.md"), "utf8").split(/\r?\n/)) {
    if (!line.startsWith("|")) continue;
    const c = line.split("|").slice(1, -1).map((x) => x.trim());
    if (c.length === 6 && /^\d+$/.test(c[0])) {
      MD_QUEST.set(+c[0], c[2]);
      MD_ENT.set(c[0] + "|" + key(c[3]), c[4]);
      if (!c[4].startsWith("?") && !MD_NAME.has(key(c[3]))) MD_NAME.set(key(c[3]), c[4]);
    } else if (c.length === 8 && /^[A-Z]+$/.test(c[0])) MD_NAME.set(key(c[2]), c[3]);
    else if (c.length === 5 && /^\d+$/.test(c[2]) && /^L\d+/.test(c[3])) MD_NAME.set(key(c[0]), c[1]);
  }
}
const mdEnt = (id, zh) => { const v = zh && MD_ENT.get(id + "|" + db.norm(cleanName(zh))); return v && (v.startsWith("?") ? "Quest object" : v); }; // 查無：中性的說法
const mdName = (zh) => zh && MD_NAME.get(db.norm(cleanName(zh)));
const nameIssues = []; // 名稱不一致（建置報告）
const dungeons = []; // 副本站：插在指定的站後面，引擎當成可選站
// 副本區域（QuestieDB support/Forever/Zones）：areaId → { name, alts }；instanceID → areaId
const ZONES = join(ADDONS, "QuestieDB/support/Forever/Zones");
const DUNGEON_AREA = new Map();
for (const m of readFileSync(join(ZONES, "dungeons.lua"), "utf8").matchAll(/\[(\d+)\]\s*=\s*\{"([^"]+)",(nil|\{[\d,]*\})/g)) {
  DUNGEON_AREA.set(+m[1], { name: m[2], alts: m[3] === "nil" ? [] : m[3].replace(/[{}]/g, "").split(",").filter(Boolean).map(Number) });
}
const CONST_NAME = (n) => n.toUpperCase().replace(/'/g, "").replace(/[^A-Z0-9]+/g, "_");
const INSTANCE_AREA = new Map();
for (const [, id, numericArea, namedArea] of readFileSync(join(ZONES, "instanceIdToAreaId.lua"), "utf8").matchAll(/\[(\d+)\]\s*=\s*(?:(\d+)|ZoneDB\.zoneIDs\.([A-Z0-9_]+))/g)) {
  const area = numericArea ? +numericArea : [...DUNGEON_AREA.entries()].find(([, d]) => CONST_NAME(d.name) === namedArea)?.[0];
  if (DUNGEON_AREA.has(area)) INSTANCE_AREA.set(+id, area);
}
// 打怪經驗用：每個目標 { 怪物平均等級, 數量, 1＝殺／2＝掉落物, 1＝精英 }。
// 數量從目標文字依序抓「N個／只／根…」；抓到的比目標少時，其餘當 1（多半是指名的首領），完全沒數字用 1。
// 每個目標的怪物名稱（和 mob 同順序；選取目標／標記用）
const targetsOf = (q) => {
  if (ALLY && q.id === 7701) return [["工頭瑪托留斯"]]; // Forever zhTW, NPC 14621
  const per = routeMobs(q.id).map((m) => (m && m.names ? [...new Set(m.names.filter(Boolean).map(cleanName))] : []));
  for (const m of routeMobs(q.id)) if (m && m.names && m.zhMissing) nameIssues.push(`- 任務 ${q.id}：目標怪 QuestieDB 沒有繁中名（${m.names.join("、")}）`);
  return per.some((n) => n.length) ? per : undefined;
};
const mobsOf = (q) => {
  const mobs = routeMobs(q.id);
  if (!mobs.length) return undefined;
  // 全形數字先轉半形；中文「N 個…」之外也認英文目標的「Kill／Defeat… N」（永恆新任務常只有英文）
  const objText = q.obj.join(" ").replace(/[０-９]/g, (c) => String.fromCharCode(c.charCodeAt(0) - 0xfee0));
  const nums = [...objText.matchAll(/(\d+)\s*(?:[大小]?塊|[個只隻根張份束件頭名條把顆片枚台臺])|\b(?:Kill|Slay|Defeat|Destroy|Collect|Gather|Obtain|Retrieve|Recover|Bring)\s+(\d+)\b/gi)].map((m) => +(m[1] ?? m[2]));
  // 怪物目標其實是跟 NPC 互動（聽提里奧說話、餵受訓者、救人、把動物趕回／送回…）：目標文字是對話／餵食，或任務說明只有互動、沒有打的字眼 → 不算打怪經驗
  const fight = /殺|擊敗|打敗|消滅|擊殺|幹掉|摧毀|征服|打死|制服|釋放|捕獲/.test(objText);
  const talkQ = /聽聽|聆聽|談話|交談|談談|談一談|談壹談|對話|包紮|餵|飽餐|救出|解救|送回|趕回|趕到|馴服/.test(objText) && !fight;
  const ownSide = (m) => (m.friendly || "").includes(ALLY ? "A" : "H"); // 目標是本陣營友善的 NPC、目標文字又沒有打的字眼：是互動
  const talk = (m) => m.kind === "kill" && (talkQ || (ownSide(m) && !fight) || /\b(talk|speak|listen|feed|fed|tame)\b/i.test(m.text || ""));
  return mobs.map((m, k) => m && m.kind !== "object" && !talk(m)
    ? [Math.round(m.lvl * 10) / 10, m.elite ? 0 : (nums.length ? (nums[k] ?? 1) : 1), m.kind === "drop" ? 2 : 1, m.elite ? 1 : 0] // 目標文字沒數字當 1；全是精英的目標數量記 0（單人補經驗不算，在日誌裡時遊戲給的剩餘數量照算）
    : [0, 0, 1, 0]);
};
const issues = { hard: [], warn: [] };
const hard = (where, text) => issues.hard.push(`- ${where}：${text}`);
const warn = (where, text) => issues.warn.push(`- ${where}：${text}`);

// 「入室偷竊（Prison Break In）」→ { zh, en }
// 「Camping 101: 專業」QuestieDB 多數沒有繁中名：照遊戲裡已有的版本補「紮營入門指南：專業」
const PROF_ZH = { Alchemy: "鍊金術", Blacksmithing: "鍛造", Cooking: "烹飪", Enchanting: "附魔", Engineering: "工程學", "First Aid": "急救", Fishing: "釣魚", Herbalism: "草藥學", Leatherworking: "製皮", Mining: "採礦", Skinning: "剝皮", Tailoring: "裁縫" };
const CAMP_ZH = (en) => { const p = PROF_ZH[(String(en || "").match(/^Camping 101: (.+)$/) || [])[1]]; return p && "紮營入門指南：" + p; };
const splitName = (s) => {
  const m = s.trim().match(/^(.*?)\s*[（(]([^（）()]*)[）)]\s*$/);
  return m ? { zh: m[1].trim(), en: m[2].trim() } : { zh: s.trim(), en: "" };
};
// 文字裡所有座標（依序）；at＝在去掉「約」之後的文字中的位置
const parseCoords = (s) => [...String(s || "").replace(/約/g, "").matchAll(/(?:(\d{3,5})\s*[｜:：\s]\s*)?(\d{1,2}(?:\.\d+)?)\s*[,，]\s*(\d{1,2}(?:\.\d+)?)/g)]
  .map((m) => ({ map: m[1] ? +m[1] : undefined, x: +m[2], y: +m[3], at: m.index }));
const parseCoord = (s) => { const c = parseCoords(s)[0]; return c ? { map: c.map, x: c.x, y: c.y } : null; };
// 種族條件輸出成 UnitRace 第 2 個回傳值（不隨客戶端語言變）；天裔精靈的各種寫法（天裔、天裔精靈、塑風者天裔精靈）都是 Skyborne（引擎用 me.sky 比）
const raceUnknown = new Set();
const raceToken = (zh) => RACE[zh] || (/天裔/.test(zh) ? "Skyborne" : (raceUnknown.add(zh), zh));
// 【僅獸人／食人妖】【非術士】→ when；【已開鳥點：卡加斯】【未開鳥點：卡加斯】→ when.fp／when.noFp（鳥點中文名，引擎看飛行地圖記下的）
const parseWhen = (tags) => {
  const when = {};
  const put = (key, v) => { (when[key] ||= []).includes(v) || when[key].push(v); };
  for (const tag of tags) {
    const m = tag.match(/^(僅|非)(.+)$/);
    const origin = tag.match(/^(排除起點|種族或起點|排除種族與起點)：(.+)$/);
    if (origin) {
      const key = { 排除起點: "notOrigin", 種族或起點: "raceOrOrigin", 排除種族與起點: "neitherRaceNorOrigin" }[origin[1]];
      for (const name of origin[2].split("／")) put(key, raceToken(name.trim()));
    }
    const lv = tag.match(/^(\d+)\s*級起$/);
    if (lv) when.lvMin = +lv[1];
    if (tag === "黑海岸分流：留岸") when.coastal = true;
    if (tag === "黑海岸分流：其餘") when.coastal = false;
    const dungeonPrep = tag.match(/^副本前置[：:]\s*(\d+-d\d+)$/);
    if (dungeonPrep) when.dungeonPrep = dungeonPrep[1];
    const fp = tag.match(/^(已開|未開)鳥點[：:]\s*(.+)$/);
    if (fp) when[fp[1] === "已開" ? "fp" : "noFp"] = fp[2].trim();
    // 【持有材料：2592×60】只計身上可直接交付的數量。
    const handIn = tag.match(/^目標完成才交[：:]\s*(\d+)$/);
    if (handIn) when.readyQuest = +handIn[1];
    const worn = tag.match(/^持有或裝備[：:]\s*(\d+)$/);
    if (worn) when.bagOrWorn = +worn[1];
    const anchor = tag.match(/^隨同交件[：:]\s*(\d+)$/);
    if (anchor) when.withTurnin = +anchor[1];
    const unstarted = tag.match(/^尚可接取[：:]\s*(\d+)$/);
    if (unstarted) when.canStart = +unstarted[1];
    const money = tag.match(/^銀幣至少[：:]\s*(\d+)$/);
    if (money) when.money = +money[1] * 100;
    const bag = tag.match(/^(持有|缺少)材料[：:]\s*(\d+)\s*×\s*(\d+)$/);
    if (bag) {
      const required = { item: +bag[2], count: +bag[3] };
      if (bag[1] === "缺少") when.missingBag = required;
      else if (when.bag) (when.additionalBags ||= []).push(required);
      else when.bag = required;
    }
    const localMap = tag.match(/^在地辦理[：:](\d+)$/);
    if (localMap) when.workMap = Number(localMap[1]);
    const parent = tag.match(/^前任已交[：:](\d+)$/);
    if (parent) when.turnedQuest = Number(parent[1]);
    // 【任務失敗：648】只在日誌回報失敗時適用；【任務未失敗：648】反之
    const failed = tag.match(/^任務(未?)失敗[：:]\s*(\d+)$/);
    if (failed) when[failed[1] ? "notFailedQuest" : "failedQuest"] = +failed[2];
    const instance = tag.match(/^限真實副本[：:]\s*(\d+)$/);
    if (instance) when.instanceID = Number(instance[1]);
    const log = tag.match(/^已接任一[：:]\s*(\d+(?:、\d+)*)$/);
    if (log) when.onQuestAny = log[1].split("、").map(Number);
    if (!m) continue;
    for (const raw of m[2].split(/[／\/、,，]/).map((s) => s.trim()).filter(Boolean)) {
      if (raw === "部落" || raw === "聯盟") continue;
      const neg = m[1] === "非";
      if (CLASS[raw]) put(neg ? "notClass" : "class", CLASS[raw]);
      else put(neg ? "notRace" : "race", raceToken(raw));
    }
  }
  return Object.keys(when).length ? when : undefined;
};
const horde = (q) => !q.races || (BigInt(q.races) & HORDE) !== 0n;
const near = (spawns, map) => clusterCenter(spawns.filter((p) => p.map === map)) || clusterCenter(spawns);

// ── 讀檔 ─────────────────────────────────────────────────────────────────────
const files = readdirSync(ROUTE).filter((f) => f.endsWith(".md")).sort((a, b) => (a.startsWith("_") - b.startsWith("_")) || a.localeCompare(b));
let stations = [];
const sideFile = (f) => /^0[6-9]-/.test(f) || f === "xp-table.md";
for (const file of files.filter((f) => !sideFile(f))) {
  const test = file.startsWith("_");
  const prefix = test ? "t" + (file.match(/\d+/)?.[0] ?? "") : file.match(/^\d+/)?.[0] ?? file.replace(/\.md$/, "");
  let st = null;
  readFileSync(join(ROUTE, file), "utf8").split(/\r?\n/).forEach((line, li) => {
    const where = `${file}:${li + 1}`;
    const h = line.match(/^##\s*第(\d+)站｜(.+?)[（(]\s*(\d+)\s*[–\-~－到]\s*(\d+)\s*[）)](?:｜影片\s*([\d:]+))?/);
    if (h) {
      st = { id: `${prefix}-${h[1]}`, name: h[2].trim(), lv: [+h[3], +h[4]], video: h[5], test, steps: [], tips: [], grind: [], file, where };
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
      if (/天裔/.test(ch[1])) (when.race ||= []).push("Skyborne");
      if (when.race && !when.race.length) delete when.race;
      if (!when.class?.length) warn(where, "職業任務標題找不到職業：" + ch[1]);
      // ｜插在 #K 之後／之前、｜插在「動詞｜文字」之後／之前
      const ins = line.match(/｜\s*插在\s*(?:#\s*(\d+)|「(.+?)」)\s*之(前|後)/);
      st = { classBlock: true, target: `${prefix}-${ch[3]}`, when, steps: [], tips: [], where, at: ins ? { no: ins[1] ? +ins[1] : undefined, text: ins[2], after: ins[3] === "後" } : undefined };
      classBlocks.push(st);
      return;
    }
    if (/^###\s/.test(line) && st && st.classBlock) { st = null; return; }
    if (/^##\s/.test(line)) { st = null; return; }
    if (!st) return;
    const bold = line.match(/^\s*\*\*(.+?)\*\*\s*$/);
    if (bold && st.steps.length) { st.steps.push({ t: "note", text: bold[1].trim().replace(/｜/g, "："), where }); return; }
    // 說明｜…：接在上一步，滑過步驟時顯示（護送、稀有掉落、要組隊、限時、物品要在某處使用…）
    // 不帶「-」的「說明｜」接在上一步；「- 說明｜」是整站的說明（放進 tips）
    const desc = line.match(/^\s*說明｜(.*)$/);
    if (desc) { const last = st.steps[st.steps.length - 1]; if (last) last.desc = desc[1].trim(); return; }
    if (st.dungeon) {
      const ent = line.match(/^\s*-\s*入口[：:｜]\s*(.+)$/);
      if (ent) {
        const c = parseCoord(ent[1]);
        const zone = Object.keys(ZONE_MAP).find((z) => ent[1].includes(z));
        st.entrance = { raw: ent[1], where, text: ent[1].replace(/【[^】]*】/g, "").replace(/(^|\s)\d{3,5}\s+(?=約?\s*\d)/, "$1").replace(/\s+/g, " ").trim(), map: c?.map || (zone && ZONE_MAP[zone]), x: c?.x, y: c?.y };
        return;
      }
      // 前置接取路線：一行文字；其中「0X-第N站」或「第N站」當建議提早接的站
      const pk = line.match(/^\s*-\s*前置接取路線[｜：:]\s*(.+)$/);
      if (pk) {
        st.pickupRaw = pk[1].trim();
        st.pickupAt = where;
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
    // 補給｜類型｜NPC｜座標（職業材料可在類型或行尾寫職業）；危險｜說明｜座標
    const sup = line.match(/^\s*-\s*補給｜(.*)$/);
    if (sup) {
      const f = sup[1].replace(/【[^】]*】/g, "").split("｜").map((x) => x.trim());
      const c = parseCoord(f[2]);
      const cls = Object.entries(CLASS).filter(([zh]) => sup[1].includes(zh)).map(([, tok]) => tok);
      const k = (f[0] || "").replace(/[（(].*$/, "").trim();
      if (k && c) (st.supply ||= []).push({ k, npc: f[1] || undefined, map: c.map || st.map, x: c.x, y: c.y, c: cls.length ? [...new Set(cls)] : undefined }); // 寫了職業（類型或【僅…】）就只給這些職業
      else warn(where, "補給格式看不懂：" + sup[1].slice(0, 40));
      return;
    }
    const dang = line.match(/^\s*-\s*危險｜(.*)$/);
    if (dang) {
      const f = dang[1].replace(/【[^】]*】/g, "").split("｜").map((x) => x.trim());
      const c = parseCoord(f[1]);
      if (f[0] && c) { (st.danger ||= []).push({ text: f[0], map: c.map || st.map, x: c.x, y: c.y }); (st.dangerAt ||= []).push(where); } // danger 整個輸出到 Route.lua，出處另記
      else warn(where, "危險格式看不懂：" + dang[1].slice(0, 40));
      return;
    }
    // 好裝｜…：不使用（副本好裝功能已拿掉），整行略過
    if (/^\s*-\s*好裝｜/.test(line)) return;
    // 練怪｜怪名｜等級 a-b｜座標｜說明
    const gr = line.match(/^\s*-\s*練怪｜(.*)$/);
    if (gr) {
      const f = gr[1].replace(/【[^】]*】/g, "").split("｜").map((x) => x.trim());
      const lv = (f[1] || "").match(/(\d+)\s*[-–~－]\s*(\d+)/);
      const c = parseCoord(f[2]);
      if (lv && c) (st.grind ||= []).push({ mob: f[0], npcId: Number(gr[1].match(/怪物[：:](\d+)/)?.[1]) || undefined, lv: [+lv[1], +lv[2]], map: c.map || st.map, x: c.x, y: c.y, note: f[3], where });
      else warn(where, "練怪格式看不懂：" + gr[1].slice(0, 40));
      return;
    }
    const route = st.dungeon && line.match(/^\s*動線[：:](.*)$/);
    if (route) {
      // 去掉來源標籤和「（12）」這類步驟編號
      const text = route[1].replace(/【[^】]*】/g, "").replace(/[（(]第?\s*\d+(?:\s*[–-]\s*\d+)?\s*步?[）)]/g, "").trim();
      if (text) st.tips.push({ k: "動線", raw: text, text, where, src: route[1] });
      return;
    }
    const meta = line.match(/^\s*-\s*(限定|二選一|地圖\s*ID|交通|取捨|提醒|未完|說明)｜(.*)$/);
    if (meta) {
      const [, key, val] = meta;
      const v = val.trim();
      if (key === "限定" && v !== "無") st.when = parseWhen([v]);
      else if (key === "二選一" && v !== "無") st.alt = v;
      else if (key.startsWith("地圖")) st.map = +v || undefined;
      else if (key === "未完") warn(`${st.id} ${st.name}`, `未完：${v}`);
      else if (key !== "限定" && key !== "二選一") {
        // 取捨的「值得做｜」「之後順路｜」是分類，不顯示（留在 verdict）；「可跳過」照樣顯示
        const vd = key === "取捨" && v.match(/^(值得做|之後順路)｜\s*/), body = vd ? v.slice(vd[0].length) : v;
        st.tips.push({ k: key, verdict: vd ? vd[1] : undefined, raw: body, text: body.replace(/【[^】]*】/g, "").trim(), where });
      }
      return;
    }
    const sm = line.match(/^\s*(?:(\d+)\s*[.、)]\s*|[-*]\s*)?(交通|接|做|交|到|鳥|爐|飛|船|練|註|買|撿)｜(.*)$/);
    if (!sm) return;
    const [, no, verb, rest0] = sm;
    const tags = [...rest0.matchAll(/【([^】]*)】/g)].map((m) => m[1]);
    const body = rest0.replace(/【[^】]*】/g, "").trim();
    const keep = /★/.test(body);
    const exitLeg = tags.find(t => t.startsWith("安戈洛離站："))?.slice("安戈洛離站：".length);
    const f = body.replace(/★/g, "").split("｜").map((s) => s.trim());
    // no、raw：職業任務段落的插入點用（#K、「動詞｜文字」）
    const step = { pick: verb === "撿" || undefined, surveyTag: tags.find(t => /^徽章偵察[：:]/.test(t)), verb, ungoroExit: ({東岸:"east", 北營:"camp", 北線船:"ship", 奧伯丁:"port", 確認位置:"wait", 島內傳送門:"islandPortal", 東渡北營:"eastCamp", 東渡碼頭:"eastPort", 暴風回程:"stormReturn", 東渡待確認:"eastWait", 暴風靠岸:"stormDock", 另一位發任人:"teacher", 鐵堡回程:"ironReturn"})[exitLeg], t: VERB[verb], authoredPoints: tags.includes("限用路線座標"), sharedOutdoorPrereq: tags.includes("共用野外前置"), sameObjective: tags.includes("同一步座標") || undefined, sameMapPreview: tags.includes("同圖才預覽下一點") || undefined, reserveOnVisit: tags.includes("到站再預留") || undefined, strictReady: tags.includes("護送完成才勾") || undefined, exitPriority: tags.includes("出本優先回報") || undefined, instancePickup: tags.includes("副本內接取") || undefined, outsideObjective: tags.includes("本外完成") || undefined, no: no ? +no : undefined, raw: verb + "｜" + body, where, when: parseWhen(tags), keep, video: tags.includes("影片") || undefined,
      tag: tags.filter((t) => !HIDDEN_TAG.test(t)).join("・") || undefined, opt: tags.includes("可跳過") || undefined, hold: (VERB[verb] !== "accept" && tags.includes("材料齊才做")) || undefined, native: (VERB[verb] === "do" && tags.includes("原生可交")) || undefined, cond: (VERB[verb] === "accept" && tags.includes("可跳過") && (f.slice(1, 3).some((x) => /^物品\s/.test(x)) || tags.some((t) => COND_TAG.test(t)))) || undefined, keepOpt: tags.some((t) => KEEP_TAG.test(t)) || undefined, hard: (tags.includes("可跳過") && tags.includes("能打高階怪再做")) || undefined, anyRace: tags.includes("部落可接") || undefined,
      desc: [...tags.filter((t) => /^說明[：:]/.test(t)).map((t) => t.replace(/^說明[：:]\s*/, "")),
        ...tags.filter((t) => /^(位置|順序)[：:]/.test(t)).map((t) => t.replace(/^(位置|順序)[：:]\s*/, "$1："))].join("；") || undefined,
      spot: (tags.find((t) => /^所在[：:]/.test(t)) || "").replace(/^所在[：:]\s*/, "") || undefined, // 副本內交的人在哪（副本中目標做完時顯示）
      star: starOf(tags), rate: (tags.map((t) => t.match(/^掉率\s*(\d+(?:\.\d+)?)\s*%/)).find(Boolean) || [])[1],
      pre: tags.map((t) => t.match(/^前置[：:].*?(\d{2,6})\s*$/)).filter(Boolean).map((m) => +m[1]),
      // 【舊鍵：a／b＋c】：改寫、合併過的步驟沿用舊存檔鍵。「／」分座標點（依序，最後一點是這步本身），「＋」是同一點的其他舊鍵（最後一個當這步的鍵）
      oldKeys: (tags.find((t) => /^舊鍵[：:]/.test(t)) || "").replace(/^舊鍵[：:]\s*/, "").split("／").map((p) => p.split("＋").map((s) => s.trim()).filter(Boolean)).filter((p) => p.length) };
    if (step.t === "accept" || step.t === "turnin" || step.t === "do") {
      Object.assign(step, splitName(f[0]));
      if (/^[?？]?$/.test(step.zh)) step.zh = ""; // 中文名未知：用 QuestieDB 的 zhTW，再不行用英文名
      // 任務 ID 欄寫一組（97924、97915…）＝這組任一：接＝玩家接哪個都算（step.any），交＝每個 ID 各展開成一步交（只顯示玩家接了的）
      const group = /^\d+(?:\s*[、,，]\s*\d+)+$/.test(f[1] ?? "") ? f[1].split(/\s*[、,，]\s*/).map(Number) : undefined;
      const hasId = Boolean(group) || /^(\d+|\?|？|)$/.test(f[1] ?? "");
      const rest = hasId ? f.slice(2) : f.slice(1);
      step.id = group ? group[0] : hasId && /^\d+$/.test(f[1]) ? +f[1] : undefined;
      if (group && step.t === "do") hard(where, "「做」不能寫一組任務 ID（交的那步會依玩家接的任務指路）");
      if (group && step.t === "accept") Object.assign(step, { any: group, text: f[0].trim(), zh: db.quest(group[0])?.zhTW || CAMP_ZH(db.quest(group[0])?.en) || step.zh, en: undefined, cond: true }); // text：清單標題；zh：任務資料用第一個的名稱
      if (group && step.t === "turnin") {
        for (const id of group) st.steps.push({ ...structuredClone(step), id, zh: db.quest(id)?.zhTW || CAMP_ZH(db.quest(id)?.en) || "", en: db.quest(id)?.en, raw: step.raw });
        return;
      }
      if (step.t === "do") {
        const source = tags.find(t => t.startsWith("副本材料怪："))?.match(/^副本材料怪：(\d+) (.+)$/);
        if (source) {
          step.componentNpcId = Number(source[1]);
          step.componentNpc = source[2];
        }
        const alternative = tags.join(" ").match(/本內亦可取得[：:](\d+)/);
        if (alternative) step.instanceMaterial = Number(alternative[1]);
        const items = tags.join(" ").match(/交回物品[：:]([0-9,]+)/);
        if (items) step.requiredItems = items[1].split(",").map(Number);
        const weapon = tags.join(" ").match(/戰鬥武器[：:](\d+)/);
        if (weapon) step.combatWeapon = Number(weapon[1]);
        const farm = tags.find(t => t.startsWith("就地採集："))?.match(/^就地採集：(\d+)×(\d+)／([\d,]+)$/);
        if (farm) {
          const item = Number(farm[1]), count = Number(farm[2]), mobs = farm[3].split(",").map(Number);
          if (count < 1 || !mobs.every(id => db.field("Item", item, 2)?.includes(id))) throw new Error(step.where + " 採集來源不符");
          step.farmMaterial = {item, count};
          localDrops.set(step.id, new Map([[item, mobs]]));
        }
        if (tags.includes("裂隙捕捉")) {
          const map = parseCoord(rest[1])?.map;
          const toolPoint = id => {
            const p = db.object(id)?.spawns.find(p => p.map === map);
            if (!p) throw new Error(where + " 缺少裂隙工具位置");
            return [p.map, p.x, p.y];
          };
          step.riftTools = { scroll: toolPoint(105175), chest: toolPoint(105174) };
          step.componentNpcId = 6492;
          step.componentNpc = "裂隙怒靈";
          step.confirmInteraction = true;
        }
        const material = tags.join(" ").match(/自備材料[：:](\d+)×(\d+)/);
        if (material) {
          step.supply = { item: +material[1], count: +material[2] };
          if (!boughtForQuest.has(step.id)) boughtForQuest.set(step.id, new Set());
          boughtForQuest.get(step.id).add(step.supply.item);
        }
        if (tags.includes("日誌確認互動")) step.confirmInteraction = true;
        step.hint = rest[0];
        step.coord = parseCoord(rest[1]);
        step.more = String(rest[1] || "").split("／").slice(1).map(parseCoord).filter(Boolean); // 其他怪點
      }
      else { step.npc = rest[0] && !/^[?？]$/.test(rest[0]) ? rest[0] : undefined; step.coord = parseCoord(rest[1]); }
    } else if (step.t === "goto") { step.text = f[0]; step.coord = parseCoord(f[1]); }
    // 買｜物品名 ×數量｜物品ID｜任務ID｜商人｜座標：背包裡夠了（或任務已完成）就勾掉
    else if (step.t === "buy") {
      const m = f[0].match(/^(.*?)\s*[×x]\s*(\d+)$/);
      Object.assign(step, { text: m ? m[1] : f[0], n: m ? +m[2] : 1, item: +f[1], fq: +f[2] || undefined, npc: f[3] || undefined, coord: parseCoord(f[4]) });
      if (!step.item) warn(step.where, "買：物品 ID 看不懂");
      if (step.item && step.fq && !step.opt && !step.when) {
        if (!boughtForQuest.has(step.fq)) boughtForQuest.set(step.fq, new Set());
        boughtForQuest.get(step.fq).add(step.item);
      }
    }
    else if (step.t === "fp") { step.node = f[0]; step.coord = parseCoord(f[1]); }
    else if (step.t === "hearth") step.bind = f[0];
    else if (step.t === "fly") step.to = f[0];
    // 船｜目的地｜出發地｜碼頭座標（「／」接別的上船處）：箭頭指去碼頭，搭上船才算完成
    else if (step.t === "boat") { step.to = f[0]; step.from = f[1]; step.coord = parseCoord(f[2]); step.more = String(f[2] || "").split("／").slice(1).map(parseCoord).filter(Boolean); }
    else if (step.t === "level") {
      step.lv = +f[0];
      step.chooseGrindSpot = tags.includes("自行選點補級") || undefined;
    }
    else if (step.t === "note") step.text = f[0];
    else if (step.t === "travel") {
      step.text = f.join("｜");
      // 既有交通步驟改寫時，可明列已發行繁中資料的文字，以保留玩家的進度鍵。
      const progressText = tags.find((tag) => /^原進度文字[：:]/.test(tag));
      if (progressText) step.key0 = progressText.replace(/^原進度文字[：:]\s*/, "") || undefined;
      // 綁爐石：交通改成「綁」（地點在全部檔讀完後才認，見下方）；座標取離「綁爐石」最近的那個（旅店老闆）
      const bindAt = step.text.replace(/約/g, "").indexOf("綁爐石");
      const pts = parseCoords(step.text);
      // 【到：地圖 x, y】：文字沒寫座標的交通，目的地寫在標籤（不顯示）；和一般交通一樣走到 50 碼內算到
      const to = !pts.length && tags.find((t) => /^到[：:]/.test(t));
      if (to) pts.push(...parseCoords(to));
      if (bindAt >= 0 && !/(已|仍|不改|保留|繼續)[^，。；]{0,8}綁|可(?:改|在|以)?[^，。；]*綁爐石/.test(step.text)) {
        step.t = "bind";
        step.bindAt = bindAt;
        const c = [...pts].sort((a, b) => Math.abs(a.at - bindAt) - Math.abs(b.at - bindAt))[0];
        step.coord = c ? { map: c.map, x: c.x, y: c.y } : null;
      } else {
        step.coord = pts[0] ? { map: pts[0].map, x: pts[0].x, y: pts[0].y } : null;
        // 其餘座標：依序指路，走到最後一個才算到；和前一點同地圖、0.5 格內的重複點不算
        step.via = pts.slice(1).filter((p, k) => p.map !== pts[k].map || Math.hypot(p.x - pts[k].x, p.y - pts[k].y) >= 0.5).map((p) => ({ map: p.map, x: p.x, y: p.y }));
      }
      step.pts = pts; // 地圖 ID 檢查（E4）用
    }
    if (st.dungeon) Object.assign(step, { ph: st.phase }, dungeonTags(tags));
    if (step.t === "turnin" && tags.includes("本次做完後回報")) step.afterWork = true;
    const kills = tags.join(" ").match(/計數擊殺[：:](\d+)×(\d+)/);
    if (kills) {
      const [npc, count] = kills.slice(1).map(Number);
      const quest = db.quest(step.id);
      if (step.t !== "do" || !db.field("Quest", step.id, 10)?.[0]?.some(([id]) => id === npc) ||
          mobsOf(quest)?.[0]?.[1] !== count) throw new Error(where + " 擊殺目標或數量不符");
      step.killCount = count;
      step.confirmInteraction = true;
    }
    const loot = tags.join(" ").match(/收取任務物品[：:](\d+)(?:×(\d+))?/);
    if (loot) {
      const item = Number(loot[1]);
      const count = Number(loot[2] || 1);
      const objectives = db.field("Quest", step.id, 10)?.get(3) || [];
      if (step.t !== "do" || !objectives.some(([id]) => id === item) || (count > 1 && mobsOf(db.quest(step.id))?.[0]?.[1] !== count))
        throw new Error(where + " 指定戰利品與任務目標不符");
      step.requiredLoot = item;
      step.lootFinishesWork = tags.includes("取得後繼續路線");
      if (count > 1) step.lootCount = count;
    }
    const provided = tags.join(" ").match(/攜物尋訪[：:](\d+)/);
    if (provided) {
      const item = Number(provided[1]);
      if (!["do", "turnin"].includes(step.t) || db.quest(step.id)?.sourceItem !== item) throw new Error(where + " 配發物品不符");
      step.providedVisit = item;
      step.confirmInteraction = true;
    }
    const fallback = tags.find(t => t.startsWith("當地補接種族："));
    if (fallback) {
      if (step.t !== "accept" || !step.coord?.map || !step.when?.race) throw new Error(where + " 當地補接需要原種族與發任點");
      const races = fallback.slice(fallback.indexOf("：") + 1).split("／").map(raceToken);
      step.when.localRaces = races;
      step.when.race.push(...races);
      step.when.nearPoint = [step.coord.map, step.coord.x, step.coord.y];
      step.when.localVisit = true;
    }
    if (tags.includes("出本後才提示交件")) {
      if ((st.dungeon && step.ph !== "post") || step.t !== "turnin" || !step.coord) throw new Error(step.where + " 需要本外回報座標");
      step.outsideHandoff = true;
    }
    const liveMinimum = tags.find(t => /^永恆接取等級 /.test(t));
    if (liveMinimum) {
      const match = liveMinimum.match(/^永恆接取等級 (\d+)$/);
      if (step.t !== "accept" || !match) throw new Error(step.where + " 永恆接取等級需要接任務及等級");
      step.verifiedMin = step.pickLv = Number(match[1]);
    }
    if (step.t === "do" && tags.includes("日誌確認互動")) step.confirmInteraction = true;
    const itemPickup = tags.find(t => /^背包物品接取[：:]/.test(t));
    if (itemPickup) {
      const item = Number(itemPickup.split(/[：:]/)[1]);
      if (step.t !== "accept" || !step.coord || !db.quest(step.id)?.startItems.includes(item)) {
        throw new Error(step.where + " 背包物品接取需要拾取座標及 QuestieDB 的任務起始物品");
      }
      step.pickupItem = item;
    }
    const wing = tags.map((tag) => tag.match(/^副本區域[：:]\s*(血色區|亡靈區|兩翼)$/)).find(Boolean);
    if (wing) {
      if (st.instance !== 329 || step.ph !== "in" || step.t !== "do") throw new Error(step.where + " 「副本區域」需要斯坦索姆本內目標");
      step.wing = ({血色區: "scarlet", 亡靈區: "undead", 兩翼: "either"})[wing[1]];
    }
    if (step.when?.instanceID && (!st.dungeon || step.ph !== "in" || st.instance !== step.when.instanceID)) {
      throw new Error(step.where + " 「限真實副本」需要相符的副本內步驟");
    }
    if (tags.includes("手動物品起任")) {
      if (step.t !== "accept" || (step.ph === "in" && !step.when?.instanceID) || !db.quest(step.id)?.startItems.includes(step.when?.bag?.item)) {
        throw new Error(step.where + " 「手動物品起任」需要真正的起始物品；副本內的接取另要副本限制");
      }
      step.manualAccept = true;
    }
    if (tags.includes("保留主線日誌")) {
      if (!st.dungeon || step.ph !== "post" || !step.opt || !step.manualAccept)
        throw new Error(step.where + " 「保留主線日誌」需要可跳過的出本手動物品接取");
      step.when.reserveDungeonPrep = true;
    }
    // 副本內的「做」：位置那段也當成副本中清單的補充行（spot）
    if (st.dungeon && step.ph === "in" && step.t === "do" && !step.spot) step.spot = (tags.find((t) => /^位置[：:]/.test(t)) || "").replace(/^位置[：:]\s*/, "") || undefined;
    if (tags.includes("人在任務點附近")) {
      if (!step.coord?.map || !["accept", "turnin"].includes(step.t)) {
        throw new Error(step.where + " 「人在任務點附近」需要接交步驟及完整世界座標");
      }
      (step.when ||= {}).nearPoint = [step.coord.map, step.coord.x, step.coord.y];
      if (tags.includes("順訪不追回") && !st.dungeon) step.when.localVisit = true;
    }
    const hubArea = tags.find((t) => /^站點區域[：:]\s*\d+$/.test(t));
    if (hubArea) {
      const quest = db.quest(step.id);
      const npcs = step.t === "accept" ? quest?.startNpcs : quest?.endNpcs;
      if (!st.dungeon || !step.when?.nearPoint || npcs?.length !== 1
          || (step.t === "accept" && step.when.dungeonPrep !== st.id)) {
        throw new Error(step.where + " 站點區域需要副本、附近座標和單一接交人");
      }
      step.when.hubArea = +hubArea.match(/\d+$/)[0];
      step.when.hubNpc = npcs[0];
    }
    if (tags.includes("手動順路補接")) {
      if (step.t !== "accept" || !step.opt || !step.when?.nearPoint || (st.dungeon && step.ph !== "post")) {
        throw new Error(step.where + " 手動順路補接需要可跳過、人在任務點附近的主線接取");
      }
      step.when.manualPickup = st.dungeon ? "dungeon" : true;
    }
    st.steps.push(step);
  });
}

const CLASS_BIT = { 1: "WARRIOR", 2: "PALADIN", 3: "HUNTER", 4: "ROGUE", 5: "PRIEST", 7: "SHAMAN", 8: "MAGE", 9: "WARLOCK", 11: "DRUID" };
const classWhen = (mask) => {
  if (!mask) return undefined;
  const cls = Object.entries(CLASS_BIT).filter(([id]) => Math.floor(mask / 2 ** (+id - 1)) % 2 === 1).map(([, t]) => t);
  return cls.length && cls.length < Object.keys(CLASS_BIT).length ? { class: cls } : undefined;
};

// 野外路線可共用同一任務在副本前置清單的指引。
const outdoorPrereqs = new Map();
for (const station of stations) {
  for (const step of station.steps) {
    if (step.t === "do" && step.sharedOutdoorPrereq) outdoorPrereqs.set(step.id, step);
  }
}

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
  for (const x of d.steps) for (const p of [x.coord, ...(x.via || [])]) if (p && !p.map) p.map = stations[at].map;
  if (!d.pickAt) d.pickAt = d.after;
  const pick = (ph) => d.steps.filter((x) => (x.ph || "pre") === ph);
  const go = d.entrance ? [{ t: "travel", text: "前往 " + d.name + " 入口", coord: d.entrance.x ? { map: d.entrance.map, x: d.entrance.x, y: d.entrance.y } : undefined, where: d.where }] : [];
  for (const x of d.steps) {
    const m = x.t === "goto" && /確認/.test(x.text || "") && (x.text || "").match(/(?<![\d.])(\d{3,6})(?![\d.,])/);
    if (m && db.quest(+m[1])) {
      const q = db.quest(+m[1]);
      const where = (x.text.match(/依(.+?)段/) || x.text.match(/詳見(.+?)[。；，]/) || [])[1];
      Object.assign(x, { t: "need", id: +m[1], zh: questName(q), text: "前置：" + questName(q) + (where ? "（在" + where.replace(/[。；，]$/, "") + (/段$/.test(where) ? "" : "段") + "接）" : ""), coord: undefined });
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
    const pres = q.preGroup.map(Math.abs); // 負號＝一定要是這個任務（見下方前置正規化）
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
      const outdoor = outdoorPrereqs.get(p);
      const base = { id: p, zh: questName(pq), en: pq.en, ph: "pre", tag: "副本前置鏈", chainOf: qid, where: d.where, when, outsideObjective: Boolean(outdoor) };
      // 野外接取寫了持物條件（物品起始、撿到才接）：補的接取沿用同一條件與可跳過，沒撿到就不出現
      const heldAccept = stations.flatMap((x) => x.steps).find((x) => x.t === "accept" && x.id === p && x.when?.bag);
      out.push({ ...base, t: "accept", verb: "接", when: heldAccept ? { ...when, bag: heldAccept.when.bag } : when, ...(heldAccept?.opt ? { opt: true } : {}) });
      if (outdoor || db.questMobs(p).length) {
        const work = { ...base, t: "do", verb: "做", hint: pq.obj.filter(Boolean).join(" ") };
        if (outdoor) Object.assign(work, { desc: outdoor.desc, coord: outdoor.coord, authoredPoints: outdoor.authoredPoints });
        out.push(work);
      }
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

// 職業任務併進指定的站：排在站尾的交通步驟前面，或標題指定的位置（｜插在 #K 之後…）
const MOVE_T = ["travel", "boat", "fly", "hearth"];
for (const blk of classBlocks) {
  const target = stations.find((s) => s.id === blk.target);
  if (!target) { hard(blk.where, "職業任務指定的站不存在：" + blk.target); continue; }
  for (const step of blk.steps) Object.assign(step, { when: { ...blk.when, ...(step.when || {}) }, cls: blk });
  let at = target.steps.length;
  if (blk.at) {
    const norm = (t) => t.replace(/\s+/g, "");
    const k = target.steps.findIndex((s) => !s.cls && (blk.at.no ? s.no === blk.at.no : s.raw && norm(s.raw).startsWith(norm(blk.at.text))));
    if (k < 0) { hard(blk.where, "職業任務的插入點在第" + blk.target.split("-")[1] + "站找不到：" + (blk.at.no ? "#" + blk.at.no : "「" + blk.at.text + "」")); continue; }
    at = blk.at.after ? k + 1 : k;
    while (target.steps[at]?.cls && target.steps[at].cls.anchor === target.steps[k]) at++; // 同一個插入點的段落照寫的順序排
    blk.anchor = target.steps[k];
    // 回到路線：座標在解析完任務座標後才補（見下方），用不到就拿掉
    const last = blk.steps[blk.steps.length - 1];
    if (last && !MOVE_T.includes(last.t)) blk.steps.push({ t: "travel", verb: "交通", back: true, cls: blk, when: { ...blk.when, ...(last.t === "buy" && last.when?.onQuestAny ? { onQuestAny: last.when.onQuestAny } : {}) }, where: blk.where }); // 段落最後是撿任務物品：只有撿的人才要回路線
  } else while (at > 0 && ["travel", "note", "boat", "fly", "hearth"].includes(target.steps[at - 1].t)) at--;
  target.steps.splice(at, 0, ...blk.steps);
}

// 綁爐石的地點：「在X旅店」「綁X爐石」，否則找「綁爐石」前面最後出現的已知地名（爐石回的地點、鳥點、站名、區域名）
// 地名 → 地圖（E4：交通座標沒寫地圖、文字卻是別張地圖的地名時警告）
const PLACE = new Map();
const putPlace = (n, map) => { if (n && n.length >= 2 && map && !PLACE.has(n)) PLACE.set(n, map); };
for (const st of stations) for (const s of st.steps) if (s.t === "fp") putPlace(s.node, s.coord?.map || st.map || ZONE_MAP[st.name.split(/[・·\s]/)[0]]);
for (const st of stations) for (const t of st.name.split(/[・·\s／與、]/)) putPlace(t, st.map || ZONE_MAP[st.name.split(/[・·\s]/)[0]]);
for (const [n, map] of Object.entries(ZONE_MAP)) putPlace(n, map);
const BIND_NAMES = new Set();
for (const st of stations) for (const s of st.steps) if (s.t === "hearth" && s.bind) BIND_NAMES.add(s.bind);
const placeBefore = (text, at, names) => {
  let best;
  for (const n of names) {
    const i = text.lastIndexOf(n, at - n.length);
    if (i >= 0 && i + n.length <= at && (!best || i + n.length > best.end || (i + n.length === best.end && n.length > best.n.length))) best = { n, end: i + n.length };
  }
  return best?.n;
};
const bindReport = [], mapWarn = [];
for (const st of stations) {
  const stMap = st.map || ZONE_MAP[st.name.split(/[・·\s]/)[0]];
  for (const s of st.steps) {
    if (s.t === "bind") {
      const text = s.text.replace(/約/g, "");
      // 「到／抵達／上／飛／回 X（後、先、並、開、找、向、，）」和已知地名：取離「綁爐石」最近（結束位置最後）的
      const known = placeBefore(text, s.bindAt, [...BIND_NAMES, ...PLACE.keys()]);
      const went = [...text.slice(0, s.bindAt).matchAll(/(?:到|抵達|上|飛(?!行)|回)\s*([^\s，。；、（(]{2,6}?)(?=後|先|並|開|找|向|，)/g)].pop();
      const wentEnd = went ? went.index + went[0].length : -1;
      s.bind = (text.match(/在([^\s，。；、（(]{2,8}?)的?旅店/) || text.match(/綁([^\s，。；、（(]{2,8}?)爐石/) || [])[1]
        || (went && (!known || wentEnd > text.lastIndexOf(known, s.bindAt - known.length) + known.length) ? went[1] : known);
      bindReport.push(`- ${s.where}：${s.bind || "（認不出地點：收到綁定事件就勾）"}｜${s.text.slice(0, 40)}`);
    }
    // E4：座標沒寫地圖，但座標前面最近的地名在別張地圖
    if (s.pts && stMap) for (const p of s.pts.filter((p) => !p.map)) {
      const text = s.text.replace(/約/g, "");
      const n = placeBefore(text, p.at + 1, PLACE.keys());
      // 地名和座標要在同一句（中間沒有，。；），才是在講這個座標
      if (n && PLACE.get(n) !== stMap && !/[，。；]/.test(text.slice(text.lastIndexOf(n, p.at + 1 - n.length) + n.length, p.at))) mapWarn.push(`- ${s.where}：座標 ${p.x}, ${p.y} 沒寫地圖 ID，文字的「${n}」在地圖 ${PLACE.get(n)}（本站 ${stMap}），會被當成本站地圖`);
    }
  }
}
for (const w of mapWarn) issues.warn.push(w);

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
  for (const p of [...(st.grind || []), ...(st.supply || []), ...(st.danger || [])]) p.map ||= st.map; // 解析當下站的地圖可能還沒定
  for (const step of st.steps) {
    if (!["accept", "do", "turnin"].includes(step.t)) {
      for (const p of [step.coord, ...(step.via || [])]) if (p) p.map ||= st.map;
      continue;
    }
    for (const p of step.more || []) p.map ||= st.map;
    // 「做」的多個點：路線寫的點＋這一步要找的目標實體點，按「目標＋地圖」各自 8 格內併成一群，地圖上一群一個點
    // Multisite component lists and unlocated instance objects do not share the outdoor quest giver's pin.
    const localComponent = step.ph === "in" && step.when?.missingBag;
    // 三枚不同的徽章各有自己的遺體；這些手寫點不能像一般怪群取平均。
    const survey = step.t === "do" && step.surveyTag;
    if (survey) {
      const [items, site] = survey.slice(5).split("／");
      const ids = items.split("、").map(Number);
      const points = [step.coord, ...step.more];
      const event = parseCoord(site);
      if (step.id !== 6185 || ids.length !== points.length || points.some(p => !p) || !event?.map)
        throw new Error(`${step.where} 徽章、遺體與偵察座標不一致`);
      step.survey = {
        badges: ids.map((id, i) => [id, points[i].map || st.map, points[i].x, points[i].y]),
        event: [event.map, event.x, event.y],
        labels: JSON.parse(readFileSync(join(ROOT, "tools/quest-6185-objectives.json"), "utf8")),
      };
    } else if (step.t === "do" && !step.authoredPoints && !step.supply && !step.farmMaterial && !step.requiredItems && !step.riftTools && !localComponent && (step.more?.length || OBJ.has(step.id))) {
      const own = [step.coord, ...(step.more || [])].filter(Boolean).map((p) => ({ map: p.map || st.map, x: p.x, y: p.y }));
      // 只加這一步要找的實體：說明寫到名字的、離路線點 8 格內的；都沒有才用路線點同地圖的（交物品、用物品的步驟不用）。
      // 路線沒寫點：寫到名字的實體，沒寫到就全部（跨地圖的點留著，執行時按玩家所在地圖挑）
      const ents = OBJ.get(step.id) || [];
      const text = [step.hint, step.zh, step.en].filter(Boolean).join(" ");
      const named = ents.filter((e) => e.name.length > 1 && text.includes(e.name));
      const near = ents.filter((e) => e.pts.some((p) => own.some((h) => h.map === p.map && Math.hypot(h.x - p.x, h.y - p.y) < 8)));
      const give = (step.hint || "").match(/交給|交付|帶給|拿給|放進|放入|使用|右鍵/);
      const handIn = give && !/收集|蒐集|擊殺|殺|打|拾取|取得|採|撿|找/.test(step.hint.slice(0, give.index));
      const pick = !own.length ? (named.length ? named : ents)
        : named.length || near.length ? [...new Set([...named, ...near])]
        : handIn ? [] : ents.filter((e) => own.some((h) => h.map === e.map));
      if (pick.length) objAdded++;
      // 分群：每群用第一個點當固定中心比距離（不會越併越歪），群中心取平均；目標點先排序，結果不受輸入順序影響
      const clusterOf = (pts) => pts.reduce((gs, p) => {
        const g = gs.find((g) => g.map === p.map && Math.hypot(g.ox - p.x, g.oy - p.y) < 8);
        if (g) { g.n++; g.sx += p.x; g.sy += p.y; } else gs.push({ map: p.map, ox: p.x, oy: p.y, n: 1, sx: p.x, sy: p.y });
        return gs;
      }, []).map((g) => ({ map: g.map, x: g.sx / g.n, y: g.sy / g.n, n: g.n }));
      const mine = clusterOf(own); // 路線寫的點照路線順序（第一個是主座標）
      const listed = pick.flatMap((e) => clusterOf([...e.pts].sort((a, b) => a.x - b.x || a.y - b.y)));
      const objs = [...listed].sort((a, b) => b.n - a.n || a.map - b.map || a.x - b.x || a.y - b.y)
        // 路線點 8 格內的目標群不另畫；不同目標的群相距 4 格內只留點多的那群
        .reduce((keep, g) => (mine.some((h) => h.map === g.map && Math.hypot(h.x - g.x, h.y - g.y) < 8) || keep.some((h) => h.map === g.map && Math.hypot(h.x - g.x, h.y - g.y) < 4) ? keep : [...keep, g]), []);
      // 只有目標點：主座標挑本站地圖（副本站是入口地圖）上的群，其次前一個有座標步驟的地圖，都沒有就用目標資料的第一群（不挑別張地圖上點最多的）
      if (!mine.length && objs.length) {
        const prevMap = st.steps.slice(0, st.steps.indexOf(step)).reverse().find((x) => x.coord?.map)?.coord.map;
        const lead = objs.find((g) => g.map === st.map) || objs.find((g) => g.map === prevMap) || objs.find((g) => g.map === listed[0].map) || objs[0];
        objs.splice(objs.indexOf(lead), 1);
        objs.unshift(lead);
      }
      const groups = [...mine, ...objs];
      // 散成 4 群以上、或範圍超過 35 格＝順路任務（不指路，路上遇到就打）；按地圖各自算，只看路線有寫主座標的步驟
      if (step.coord) {
        const raw = [...own, ...pick.flatMap((e) => e.pts)];
        for (const map of new Set(groups.map((g) => g.map))) {
          const on = raw.filter((p) => p.map === map);
          const span = on.reduce((m, a) => on.reduce((m, b) => Math.max(m, Math.hypot(a.x - b.x, a.y - b.y)), m), 0);
          if (groups.filter((g) => g.map === map).length >= 4 || span > 35) step.roam = true;
        }
      }
      const r2 = (n) => Math.round(n * 100) / 100;
      // 主座標＝第一群（路線寫的第一個點；只有目標點時是點最多的那群），其他群放 more（每點帶地圖）
      const [first, ...rest] = groups.map((g) => ({ map: g.map, x: r2(g.x), y: r2(g.y) }));
      step.coord = first || null;
      step.more = rest;
      if (step.more.length && !step.coord?.map) warn(`${step.where} ${step.verb}｜${step.zh}`, "「做」有多個點但沒有可導航的主座標");
    }
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
        const inRoute = (q) => [...q.preGroup.map(Math.abs), ...q.preSingle].some((p) => quests.has(p));
        narrow((q) => inRoute(q) || ![...q.preGroup.map(Math.abs), ...q.preSingle].some((p) => cands.some((c) => c.id === p)));
        cands.sort((a, b) => a.level - b.level || a.id - b.id);
        if (!cands.length) { hard(at, "QuestieDB 找不到這個任務"); continue; }
        id = cands[0].id;
        if (cands.length > 1) hard(at, `多個候選 ${cands.map((c) => c.id).join(", ")}，暫用 ${id}（可在檔案中直接寫 ID）`);
        else warn(at, `補上 ID ${id}`);
      }
    }
    step.id = id;
    const anyRace = step.anyRace; delete step.anyRace;
    used.add(`${step.t}:${id}`);
    if (step.t === "accept") { if (step.zh) lastByName.set(db.norm(step.zh), id); if (step.en) lastByName.set(db.norm(step.en), id); }
    const q = db.quest(id);
    if (!quests.has(id)) {
      quests.set(id, q
        ? { races: q.races && BigInt(q.races) !== HORDE ? q.races : undefined, xp: XP.get(id), mob: mobsOf(q), tgo: targetsOf(q), objs: (() => { const o = [...new Set(routeMobs(q.id).filter((m) => m && m.kind === "object").flatMap((m) => m.objects))]; return o.length ? o : undefined; })(),
            items: [...new Set([q.sourceItem, ...q.requiredSourceItems].filter((x) => x > 0))].length ? [...new Set([q.sourceItem, ...q.requiredSourceItems].filter((x) => x > 0))] : undefined,
            d: q.obj.filter(Boolean).join("\n").replace(/[０-９]/g, (c) => String.fromCharCode(c.charCodeAt(0) - 0xfee0)).replace(/\$(?![A-Za-z])/g, "").replace(/<name>[，,]\s*|[，,]\s*<name>/g, "") || undefined, // 全形數字轉半形；落單的「$」（任務文字控制符殘片）、稱呼玩家的 <name> 拿掉
            n: QUEST_NAME[id] || step.zh || q.zhTW || step.en || q.en, zt: q.zhTW && q.zhTW !== (QUEST_NAME[id] || step.zh || q.zhTW) ? q.zhTW : undefined, lvl: q.level, min: q.reqLevel, pg: q.preGroup, ps: q.preSingle, ex: q.exclusiveTo, next: q.next, pa: q.flags & 2 ? true : undefined, st: st.id }
        : { n: QUEST_NAME[id] || step.zh || step.en, st: st.id });
    }
    if (q && !quests.get(id).en) {
      const mobs = routeMobs(id);
      const tgoEn = mobs.map((m) => (m && m.namesEn ? [...new Set(m.namesEn.filter(Boolean).map(cleanName))] : []));
      const objsEn = [...new Set(mobs.filter((m) => m && m.kind === "object").flatMap((m) => m.objectsEn || []))];
      // 沒有英文目標文字：用目標怪／物件湊一句
      const kill = mobs.filter((m) => m && m.kind === "kill").flatMap((m) => m.namesEn || []);
      const drop = mobs.filter((m) => m && m.kind === "drop").flatMap((m) => m.namesEn || []);
      const gen = () => {
        const parts = [kill.length && "Kill: " + [...new Set(kill)].join(", "), drop.length && "Loot from: " + [...new Set(drop)].slice(0, 3).join(", "), objsEn.length && "Use/collect: " + objsEn.join(", ")].filter(Boolean);
        return parts.length ? parts.join(". ") : undefined;
      };
      const objEn = q.objEn.map(enText).filter(Boolean);
      // 選取目標：照中文 tgo／objs 的形狀逐一換英文（查核表＞QuestieDB 同位置）
      const e = quests.get(id);
      const tgo = e.tgo && e.tgo.map((list, g) => list.map((zh, k) => { const m = mdEnt(id, zh); if (m && tgoEn[g]?.[k] && m !== tgoEn[g][k]) enDiff.tgt++; return m || tgoEn[g]?.[k]; }).filter(Boolean));
      const objs = e.objs && e.objs.map((zh, k) => mdEnt(id, zh) || objsEn[k]).filter(Boolean);
      if (MD_QUEST.has(id) && q.en && MD_QUEST.get(id) !== q.en) enDiff.quest++;
      e.en = { n: MD_QUEST.get(id) || step.en || q.en, d: objEn.join("\n") || undefined, gen: objEn.length ? undefined : gen(), tgo: tgo && tgo.some((n) => n.length) ? tgo : undefined, objs: objs && objs.length ? objs : undefined, mk: { kill, drop, objsEn } };
    } else if (!q && !quests.get(id).en) quests.get(id).en = { n: MD_QUEST.get(id) || step.en || undefined };
    if (step.t === "turnin" && step.when?.readyQuest === id && step.when.additionalBags) {
      quests.get(id).deliveryItems = [step.when.bag, ...step.when.additionalBags];
      quests.get(id).confirmInteraction = true;
    }
    if (step.when?.localRaces) quests.get(id).localPickupRaces = step.when.localRaces;
    else if (step.when?.localVisit) quests.get(id).localVisit = true;
    if (step.requiredLoot) {
      quests.get(id).requiredLoot = step.requiredLoot;
      if (step.lootFinishesWork) quests.get(id).lootFinishesWork = true;
    }
    if (step.lootCount) quests.get(id).lootCount = step.lootCount;
    if (step.killCount) quests.get(id).killCount = step.killCount;
    if (step.providedVisit) quests.get(id).providedVisit = step.providedVisit;
    if (step.riftTools) quests.get(id).riftTools = step.riftTools;
    if (step.farmMaterial) quests.get(id).farmMaterial = step.farmMaterial;
    if (step.requiredItems) quests.get(id).requiredItems = step.requiredItems;
    if (step.combatWeapon) quests.get(id).combatWeapon = step.combatWeapon;
    if (step.supply) quests.get(id).supply = step.supply;
    if (step.confirmInteraction) quests.get(id).confirmInteraction = true;
    if (step.survey) quests.get(id).survey = step.survey;
    if (step.verifiedMin) quests.get(id).min = step.verifiedMin;
    if (step.keep) quests.get(id).keep = true;
    // 【部落可接】：實測部落能接，但 QuestieDB 的種族遮罩寫成聯盟限定
    if (anyRace) quests.get(id).races = undefined;
    // 【前置：… ID】寫在任何一個檔的任何一步，都併進這個任務的前置（全部要做）
    for (const p of step.pre || []) {
      const e = quests.get(id);
      if (!(e.pg || []).includes(p) && !(e.ps || []).includes(p)) e.pg = [...(e.pg || []), p];
    }
    if (step.star) quests.get(id).star = step.star;
    if (+step.rate > 0) quests.get(id).rate = +step.rate / 100;
    if (step.t === "do" || !q) { if (step.coord) step.coord.map ||= st.map; continue; }
    // 接/交：NPC 名與座標
    const npcIds = step.t === "accept" ? q.startNpcs : q.endNpcs;
    const objIds = step.t === "accept" ? q.startObjects : q.endObjects;
    const npcs = npcIds.map((n) => db.npc(n)).filter(Boolean);
    const namedNpc = step.npc && npcs.find((npc) => [npc.zhTW, npc.zhTW && gameName(npc.zhTW), npc.en].some((name) => name && db.norm(cleanName(name)) === db.norm(cleanName(step.npc))));
    // 共用職業任務常有兩陣營的訓練師。保留手寫指定，其餘優先採用本陣營可互動的 NPC。
    const friendly = npcs.find((npc) => npc.faction?.includes(ALLY ? "A" : "H"));
    const npcGiver = namedNpc || friendly || npcs.find((npc) => !npc.faction);
    const isNpc = Boolean(npcGiver);
    const giver = npcGiver || objIds.map((o) => db.object(o)).find(Boolean);
    if (!step.npc && giver) step.npc = isNpc && giver.zhTW ? gameName(giver.zhTW) : giver.zhTW || giver.en;
    // 英文：給任務的 NPC／物件英文名；從物品開始的任務用物品英文名（物件、物品不當選取目標）
    if (giver) { step.npcEn = mdEnt(id, step.npc) || cleanName(giver.en); if (step.npcEn !== cleanName(giver.en)) enDiff.npc++; if (!isNpc) step.npcObj = true; }
    else if (step.t === "accept" && q.startItems.length) { step.npcEn = mdEnt(id, step.npc) || db.itemEn(q.startItems[0]); step.npcObj = true; }
    if (isNpc) step.tgtEn = mdEnt(id, step.tgt) || cleanName(giver.en);
    if (isNpc) {
      const dbName = giver.zhTW ? gameName(giver.zhTW) : null;
      if (dbName) {
        step.tgt = dbName;
        if (step.npc && cleanName(step.npc) === cleanName(dbName)) step.npc = dbName; // 只差裝飾（引號等）→ 用遊戲名
        else if (step.npc) nameIssues.push(`- ${at}：路線寫「${step.npc}」，QuestieDB／遊戲名是「${dbName}」`);
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
    else if (!(step.t === "accept" && q.startItems.length && !npcIds.length && !objIds.length)) warn(at, "缺座標（QuestieDB 也沒有）");
  }
  const noCoord = st.steps.filter((s) => s.t === "do" && !s.coord).length;
  if (noCoord) warn(`${st.id} ${st.name}`, `${noCoord} 個「做」步驟沒有座標（不會出現箭頭）`);
  if (!st.map) hard(`${st.id} ${st.name}`, "沒有地圖 ID");
}

// 職業任務段落沒寫插入點的（預設在站尾）：座標解析完，若段落第一步的地圖在站尾之前就離開了（中間有船、飛、爐，或換到別洲），
// 搬到「站裡最後一個在那張地圖的主線步驟」後面（交通、註不算）；但那裡的預估等級（依站內位置從站的等級範圍內插）比段落起始等級低 2 級以上就不搬，只報告。
// 搬完檢查每段的段首和前一個主線座標：跨洲且中間沒有交通步驟的列為提醒（要手動寫插入點），同洲不同地圖的列在報告
const KALIMDOR = new Set([1411, 1412, 1413, 1438, 1439, 1440, 1441, 1442, 1443, 1444, 1445, 1446, 1447, 1448, 1449, 1450, 1451, 1452, 1454, 1456, 1457, 2482]);
const continent = (map) => (KALIMDOR.has(map) ? "卡林多" : (map >= 1415 && map <= 1437) || [1453, 1455, 1458].includes(map) ? "東部王國" : map === 2521 ? "微風島" : undefined); // 其他新地圖不判斷
const TRAVEL_T = ["travel", "boat", "fly", "hearth"];
const classMoved = [], classMap = [], classFar = [];
for (const st of stations) {
  for (const blk of [...new Set(st.steps.map((s) => s.cls).filter(Boolean))]) {
    const mine = st.steps.filter((s) => s.cls === blk);
    const first = mine.find((s) => s.coord?.map);
    if (!blk.at && first) {
      const rest = st.steps.filter((s) => s.cls !== blk);
      const M = first.coord.map;
      let k = -1;
      rest.forEach((s, i) => { if (!s.cls && s.coord?.map === M && !TRAVEL_T.includes(s.t) && s.t !== "note") k = i; });
      const tail = rest.slice(k + 1).filter((s) => !s.cls);
      const left = k >= 0 && tail.some((s) => ["boat", "fly", "hearth"].includes(s.t) || (s.coord?.map && continent(s.coord.map) && continent(M) && continent(s.coord.map) !== continent(M)));
      const main = rest.filter((s) => !s.cls);
      const lvAt = st.lv[0] + ((st.lv[1] - st.lv[0]) * (main.indexOf(rest[k]) + 1)) / main.length;
      if (left && lvAt >= blk.when.lvMin - 1) {
        let at = k + 1;
        while (rest[at]?.cls) at++; // 同一處的其他職業段落照原順序
        st.steps = [...rest.slice(0, at), ...mine, ...rest.slice(at)];
        classMoved.push(`- ${blk.where}：移到 ${rest[k].where}（${(rest[k].raw || rest[k].t).slice(0, 24)}）之後`);
      } else if (left) classFar.push(`- ${blk.where}：段落在地圖 ${M}，本站在站尾前就離開那裡，但那時預估才 ${Math.floor(lvAt)} 級（段落 ${blk.when.lvMin} 級起），沒有自動搬；請寫「｜插在…」`);
    }
    if (!first) continue;
    const i = st.steps.indexOf(mine[0]);
    const prev = st.steps.slice(0, i).reverse().find((x) => !x.cls && x.coord?.map);
    if (!prev || prev.coord.map === first.coord.map) continue;
    const a = continent(prev.coord.map), b = continent(first.coord.map);
    const moved = mine.slice(0, mine.indexOf(first) + 1).some((x) => TRAVEL_T.includes(x.t)) || TRAVEL_T.includes(prev.t);
    if (a && b && a !== b && !moved) classFar.push(`- ${blk.where}：插入點前一步在${a}（${prev.where}），段落第一步在${b}，中間沒有交通步驟；請寫「｜插在…」或補交通`);
    else classMap.push(`- ${blk.where}：插入點前一步地圖 ${prev.coord.map}（${prev.where}），段落第一步地圖 ${first.coord.map}`);
  }
}
for (const w of classFar) issues.warn.push(w);

// 職業任務段落的「回到路線」：指向插入點後面第一個有座標的主線步驟；段落最後的座標就在那附近（同地圖、10 格內）就不用。
// 主線在那個座標之前（含）自己有交通步驟的也不用：不然頂框先要人到目的地，怎麼去的說明反而排在後面
const backAdded = [], backDropped = [];
for (const st of stations) {
  st.steps = st.steps.filter((s, i) => {
    if (!s.back) return true;
    const next = st.steps.slice(i + 1).find((x) => !x.cls && x.coord);
    const prev = st.steps.slice(0, i).reverse().find((x) => x.cls === s.cls && x.coord);
    if (prev && !next) warn(s.where, `職業任務段落後面本站沒有有座標的主線步驟，「回到路線」拿掉了（段落最後在地圖 ${prev.coord.map}）；需要的話在段落最後自己寫交通`);
    if (!next || !prev || (prev.coord.map === next.coord.map && Math.hypot(prev.coord.x - next.coord.x, prev.coord.y - next.coord.y) <= 10)) return false;
    const own = st.steps.slice(i + 1, st.steps.indexOf(next) + 1).find((x) => !x.cls && MOVE_T.includes(x.t));
    if (own) { backDropped.push(`- ${s.where}：段落最後在 ${prev.coord.map} ${prev.coord.x}, ${prev.coord.y}；主線接著有交通（${own.where}：${(own.raw || own.t).slice(0, 40)}）`); return false; }
    s.coord = { map: next.coord.map, x: next.coord.x, y: next.coord.y };
    backAdded.push(`- ${s.where}：回到 ${s.coord.map} ${s.coord.x}, ${s.coord.y}（${next.where}）`);
    return true;
  });
}
// 爐石回 X／綁爐石（沒座標）：非中文介面翻不到地名時的地圖名（hm）。爐石回：前面最近綁在 X 的綁爐石步驟的地圖＞X 的地圖＞前面最近一次綁爐石的地圖；
// 不用下一步的地圖（站尾的爐石常接到別區的下一站）
const binds = [];
for (const st of stations) {
  const stMap = st.map || ZONE_MAP[st.name.split(/[・·\s]/)[0]];
  for (const s of st.steps) {
    const race = s.when?.race || st.when?.race; // 起點路線各族分開：別族的綁爐石不算
    if (s.t === "bind") { binds.unshift({ bind: s.bind, map: s.coord?.map || stMap, race }); if (!s.coord) s.hm = PLACE.get(s.bind) || stMap; }
    const mine = binds.filter((b) => !race || !b.race || b.race.some((r) => race.includes(r)));
    if (s.t === "hearth") s.hm = (s.bind && mine.find((b) => b.bind && (b.bind.includes(s.bind) || s.bind.includes(b.bind))))?.map || PLACE.get(s.bind) || mine[0]?.map || stMap;
  }
}

// 前置正規化（QuestieDB preQuestGroup 的語意）：負號＝一定要是這個任務；正號＝這個任務或它的互斥替代（exclusiveTo）任一個交了都算。
// 引擎只有「全部要做」（pg）和一組「任一個」（ps）：負號拿掉；有替代的正號前置併成 ps（只有一組替代、本來沒有 ps 時；否則只報告）
const exFixed = [];
for (const [id, e] of quests) {
  if (!e.pg?.length) continue;
  const exOf = (p) => (db.quest(p)?.exclusiveTo || []).filter((o) => o !== id);
  const alt = e.pg.filter((p) => p > 0 && exOf(p).length);
  if (e.pg.some((p) => p < 0)) exFixed.push(`- ${id} ${e.n}：前置 ${e.pg.filter((p) => p < 0).map(Math.abs).join("、")} 一定要是這個任務（拿掉負號）`);
  e.pg = e.pg.map(Math.abs);
  if (!alt.length) continue;
  const union = [...new Set(alt.flatMap((p) => [p, ...exOf(p)]))];
  if (e.ps?.length || !alt.every((p) => union.every((o) => o === p || exOf(p).includes(o)))) { exFixed.push(`- ${id} ${e.n}：前置 ${alt.join("、")} 有互斥替代，但已有任一前置或替代不只一組，沒改`); continue; }
  e.pg = e.pg.filter((p) => !alt.includes(p));
  e.ps = union;
  exFixed.push(`- ${id} ${e.n}：前置 ${alt.join("、")} 或它的替代 ${union.filter((p) => !alt.includes(p)).join("、") || "（互斥的前置之間）"} 任一個`);
}
// 互斥清單裡的導引（自己的前置，或 next 指向自己的）不算互斥：交完導引不會把主任務藏掉
// 同名、交給主任務發任務 NPC 的也是導引（例：虛弱妖術 5654 泰金→烏爾庫，主任務 5652 向烏爾庫接）
const exLead = [];
for (const [id, e] of quests) {
  const main = db.quest(id);
  const lead = (e.ex || []).filter((o) => {
    const q = db.quest(o);
    return [...(e.pg || []), ...(e.ps || [])].includes(o) || q?.next === id
      || (q && main && q.en === main.en && q.endNpcs.some((n) => main.startNpcs.includes(n)) && !q.startNpcs.some((n) => main.startNpcs.includes(n)));
  });
  if (!lead.length) continue;
  e.ex = e.ex.filter((o) => !lead.includes(o));
  exLead.push(`- ${id} ${e.n}：${lead.join("、")}`);
}
// 必做任務的前置在主線只有「可跳過」的步驟：那些前置改成必做（預設不帶可跳過時前置不成立，主任務整條會被藏）。前置的前置照樣往上找；前置標了「有隊伍再做」（精英）的不改：沒打就照舊把後續藏起來
const leadReq = [];
{
  const main = stations.filter((s) => !s.dungeon).flatMap((s) => s.steps);
  const turnin = (p, req) => main.some((x) => x.t === "turnin" && x.id === p && (!req || !x.opt));
  // 明確可選的入口（精英、太強、條件入口）後面的整條：前置沒做時後續本來就該藏，不升成必做
  const optRoot = (p, seen = new Set()) => {
    if (seen.has(p)) return false;
    seen.add(p);
    if (main.some((x) => x.id === p && x.opt && (x.keepOpt || x.cond))) return true;
    const e = quests.get(p);
    return [...(e?.pg || []), ...(e?.ps || [])].some((pp) => main.some((x) => x.id === pp && x.opt) && optRoot(pp, seen));
  };
  const queue = [...new Set(main.filter((x) => x.t === "accept" && x.id && !x.opt).map((x) => x.id))];
  for (let qi = 0; qi < queue.length; qi++) {
    const e = quests.get(queue[qi]);
    if (!e) continue;
    const ps = e.ps?.length && !e.ps.some((p) => turnin(p, true)) ? e.ps.filter((p) => turnin(p)) : [];
    for (const p of [...(e.pg || []).filter((p) => !turnin(p, true) && turnin(p)), ...ps]) {
      if (optRoot(p)) continue;
      for (const x of main.filter((x) => x.id === p && x.opt)) {
        delete x.opt;
        x.tag = (x.tag || "").split("・").filter((t) => t !== "可跳過").join("・") || undefined;
      }
      leadReq.push(`- ${queue[qi]} ${e.n}：前置 ${p} ${quests.get(p)?.n || ""} 改成必做`);
      if (!queue.includes(p)) queue.push(p);
    }
  }
}
// 條件入口記到任務上（引擎 FillPlan 用）
for (const x of stations.flatMap((s) => s.steps)) if (x.cond) for (const id of x.any || [x.id]) if (quests.has(id)) quests.get(id).cond = true;
// 補經驗只挑單人現在能打的任務。沿用 mobsOf 已排除的對話、物件與友方互動目標。
const optionalFights = new Set(stations.flatMap(st => st.steps.filter(s => s.opt && s.t === "accept").map(s => s.id)));
for (const st of stations) for (const s of st.steps) {
  const q = quests.get(s.id);
  if (!q || !(s.hard || (s.t === "do" && optionalFights.has(s.id)))) continue;
  const targets = routeMobs(s.id).filter((m, i) => m && q.mob?.[i]?.[0] > 0);
  if (targets.length) {
    q.hard = Math.max(...targets.map(m => m.hi));
    if (targets.some(m => m.elite)) q.soloElite = true;
  } else if (s.hard) q.hard = 99;
}
// 路線上有接的任務，前置在本陣營路線完全沒有交件步驟：永遠不成立，引擎會一直藏
{
  const all = stations.flatMap((s) => s.steps);
  const turned = new Set(all.filter((x) => x.t === "turnin" && x.id).map((x) => x.id));
  const accepted = new Set(all.filter((x) => x.t === "accept" && x.id).map((x) => x.id));
  for (const [id, e] of quests) {
    if (!accepted.has(id)) continue;
    const miss = [...(e.pg || []).filter((p) => !turned.has(p)), ...(e.ps?.length && !e.ps.some((p) => turned.has(p)) ? [e.ps.join("／")] : [])];
    if (miss.length) warn(`任務 ${id} ${e.n}`, `前置 ${miss.join("、")} 在路線上沒有交件步驟，這個任務會一直被藏起來`);
  }
}

// 純對話／送信任務（沒有任何目標）：「做」和「交」是同一件事，同站有交、地點也一樣就不放「做」
let talkOnly = 0;
for (const st of stations) {
  st.steps = st.steps.filter((s) => {
    if (s.t !== "do" || !s.id || s.desc || (s.ph === "post" && s.exitPriority) || routeMobs(s.id).length || db.quest(s.id)?.requiredSourceItems?.length) return true; // 寫了說明的不併（例如牽馬回農莊）
    // QuestieDB 沒記目標的新任務也可能要打怪、撿東西：說明看起來是要做事的就留著
    const h = s.hint || "";
    const talk = /^(把|將)[^，。；]*(交給|帶給|交還給|送給|送回|帶回|帶到|拿給)/.test(h) || /^(與|和|向|問)[^，。；]*(談一談|談話|交談|對話|報到|回報|報告)/.test(h) || /^(到|去)[^，。；]*(找|報到|向)/.test(h);
    if (!talk || /尋找|使用|餵|讀|點|搜尋|等|收集|殺|打|撿|拾|取得|×/.test(h)) return true;
    const t = st.steps.find((x) => x.t === "turnin" && x.id === s.id);
    const same = t && (!s.coord || (t.coord && t.coord.map === s.coord.map && Math.hypot(t.coord.x - s.coord.x, t.coord.y - s.coord.y) <= 2));
    if (same) talkOnly++;
    return !same;
  });
}

// 順序檢查：「接」的前置在同一站較後面才交 → 把這個接（和夾在中間的同任務步驟）移到那個交後面
const orderFixes = [];
for (const st of stations) {
  if (st.dungeon) continue;
  for (let guard = 0; guard < 100; guard++) {
    let moved = false;
    for (let i = 0; i < st.steps.length && !moved; i++) {
      const a = st.steps[i];
      if (a.t !== "accept" || !a.id) continue;
      const e = quests.get(a.id) || {};
      const pres = [...(e.pg || []), ...((e.ps || []).length === 1 ? e.ps : [])];
      for (const p of pres) {
        const j = st.steps.findIndex((x, k) => k > i && x.t === "turnin" && x.id === p);
        if (j < 0) continue;
        const mine = st.steps.filter((x, k) => k >= i && k < j && x.id === a.id);
        st.steps = st.steps.filter((x, k) => !(k >= i && k < j && x.id === a.id));
        st.steps.splice(st.steps.findIndex((x) => x.t === "turnin" && x.id === p) + 1, 0, ...mine);
        orderFixes.push(`- ${st.id} ${st.name}：接「${e.n}」（${a.id}）原本排在前置「${quests.get(p)?.n || p}」（${p}）交之前，已移到交之後`);
        moved = true;
        break;
      }
    }
    if (!moved) break;
  }
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
// 會開後續任務的不當順路任務：照順序先做完，免得後面接不到
let roamKept = 0;
for (const st of stations) for (const step of st.steps) if (step.roam && quests.get(step.id)?.fol) { step.roam = undefined; roamKept++; }

// 遊戲 zhTW 字型缺的字：・（U+30FB）→ 空白，彎引號 → ASCII
const idStats = new Map(); // 檔案 → 換掉的裸 ID 數
let idFile = "";
const MAP_IDS = new Set(Object.values(ZONE_MAP).concat([1458, 1454, 1456, 2521, 2548]));
const mapId = (n) => MAP_IDS.has(n) || (n >= 1400 && n < 3000); // 中文說明裡座標前的地圖 ID（1453 暴風城等不在 ZONE_MAP 的也算）
const CLASS_RE = new RegExp("^(" + Object.keys(CLASS).join("|") + ")");
const RACE_ZH = { ...RACE, 天裔: "Skyborne" };
const RACE_RE = new RegExp("^(" + Object.keys(RACE_ZH).join("|") + ")");
const sentences = (raw) => {
  const out = [];
  for (let piece of String(raw || "").split(/[；。]/)) {
    piece = piece.trim();
    if (!piece) continue;
    const tags = [...piece.matchAll(/【([^】]*)】/g)].map((m) => m[1]);
    let text = piece.replace(/【[^】]*】/g, "").trim();
    if (!text) continue;
    let when = parseWhen(tags) || {};
    // 句首的職業／種族名
    let head = text.replace(/^[‧\-\s]+/, ""), neg = false;
    if (head.startsWith("非")) { neg = true; head = head.slice(1); }
    let m, found = false;
    while ((m = head.match(RACE_RE) || head.match(CLASS_RE))) {
      const zh = m[1];
      if (CLASS[zh]) (when[neg ? "notClass" : "class"] ||= []).push(CLASS[zh]);
      else (when[neg ? "notRace" : "race"] ||= []).push(RACE_ZH[zh]);
      head = head.slice(zh.length).replace(/^[／\/、和與]/, "");
      found = true;
    }
    out.push(Object.keys(when).length ? [text, when] : [text]);
  }
  return out;
};
let refPrefix = "";
const stationName = (id) => {
  const st = stations.find((x) => x.id === id);
  if (!st) return null;
  const twin = stations.filter((x) => x.name === st.name).length > 1;
  return "「" + st.name + (twin ? " " + st.lv[0] + "-" + st.lv[1] : "") + "」"; // 用引號框起來，接在句子裡才看得清楚
};
const replaceStations = (text) => text
  .replace(/(\d{2})\s*-\s*第(\d+)站/g, (all, p, n) => stationName(p + "-" + n) || all)
  .replace(/第(\d+)\s*[–\-~－到或]\s*第?(\d+)站/g, (all, a, b) => { const x = stationName(refPrefix + "-" + a), y = stationName(refPrefix + "-" + b); return x && y ? x + "或" + y : all; })
  .replace(/第(\d+)站/g, (all, n) => stationName(refPrefix + "-" + n) || all);
// 「第 N 步」：遊戲內的步驟編號是相對的（依角色過濾、職業段落插入），換成被指的那步的短標題（同站、同段落的 md 編號）；範圍寫「從『A』到『B』」。
// 有一步找不到或沒有標題、前面緊接地名（指別站的第 N 步）、翻譯的編號和中文對不上（翻譯舊了）就整段不換
let refSteps = [];
const REF_SEP = String.raw`[,，、&]|oder|или|and|und|or|ou|et|и|및|와|과|和|與|及|y|e|o`, REF_DASH = String.raw`[–\-~～至到]`;
const REF_LIST = String.raw`\d+(?:\s*(?:${REF_SEP}|${REF_DASH})\s*\d+)*`;
const REF_RE = {
  zh: new RegExp(String.raw`第\s*(${REF_LIST})\s*步`, "g"),
  ko: new RegExp(String.raw`(${REF_LIST})\s*단계`, "g"),
  latin: new RegExp(String.raw`(?<!\p{L})(steps?|Schritte?n?|étapes?|pasos?|etapas?|passos?|шаг\p{L}*)\s+(${REF_LIST})`, "giu"),
};
const refItems = (list) => list.split(new RegExp(String.raw`\s*(?:${REF_SEP})\s*`)).map((p) => p.split(new RegExp(String.raw`\s*${REF_DASH}\s*`)).map(Number));
const refNums = (text, kind) => [...text.matchAll(REF_RE[kind])].filter((m) => kind !== "zh" || ![...PLACE.keys()].some((n) => text.slice(0, m.index).endsWith(n)))
  .flatMap((m) => refItems(m[kind === "latin" ? 2 : 1]).flat()).sort((a, b) => a - b).join();
const stepRefs = (text, title, kind, zhSrc) => {
  if (!text || !refSteps.length || (zhSrc !== undefined && refNums(zhSrc, "zh") !== refNums(text, kind))) return text;
  return text.replace(REF_RE[kind], (...a) => {
    const at = a.at(-2), [word, list] = kind === "latin" ? [a[1], a[2]] : [undefined, a[1]];
    if (kind === "zh" && [...PLACE.keys()].some((n) => text.slice(0, at).endsWith(n))) return a[0];
    // 中文：引用在句首（「第 2 步飛雷霆崖」）時句子本身就在講那一步，引用整個拿掉，不塞標題
    if (kind === "zh" && /(^|[，。；、：:,.;（(])\s*$/.test(text.slice(0, at)) && refItems(list).flat().every((n) => refSteps.some((x) => x.no === n))) return "";
    const items = refItems(list).map((r) => r.map((n) => { const s = refSteps.find((x) => x.no === n); return s && title(s); }));
    if (items.flat().some((x) => !x)) return a[0]; // 指到交通、註這類沒有短標題的步驟：照原文
    const q = kind === "zh" ? (x) => "『" + x + "』" : (x) => "“" + x + "”";
    const joined = items.map((r) => (r.length > 1 ? (kind === "zh" ? `從${q(r[0])}到${q(r.at(-1))}` : `${q(r[0])}–${q(r.at(-1))}`) : q(r[0]))).join(kind === "zh" ? "、" : ", ");
    return kind === "zh" ? joined : kind === "ko" ? joined + " 단계" : word + " " + joined;
  });
};
const ZH_VERB = { accept: "接 ", do: "做 ", turnin: "交 ", fp: "開鳥點：", hearth: "爐石回 ", bind: "綁爐石", fly: "飛往 ", boat: "搭船往 ", buy: "買 " };
const zhTitle = (s) => {
  const q = s.zh || (s.id && db.quest(s.id) && questName(db.quest(s.id)));
  if (["accept", "do", "turnin"].includes(s.t)) return q && ZH_VERB[s.t] + q;
  if (s.t === "level") return `練到 ${s.lv} 級`;
  if (s.t === "bind") return ZH_VERB.bind + (s.bind ? "：" + s.bind : "");
  const name = s.t === "buy" ? s.text : s.node || s.bind || s.to;
  if (ZH_VERB[s.t] && name) return ZH_VERB[s.t] + name;
  return undefined; // 交通、到、註、沒寫地名的：沒有短標題（不把整句塞進別的句子）
};
// 裸數字只在「不是數量」時才當任務 ID：後面接單位（金、經驗、號、型…）、前面是「約／捐／共…」、網址裡的數字都保持原樣
// 名字已寫在 ID 前面（「名」「名（英文）」「英文 中文」）時，前面那段名字要收成一個中文名，所以逐個比對、自己接字串，不用 replace callback
const replaceIds = (text) => {
  const src = replaceStations(stepRefs(text, zhTitle, "zh"));
  let out = "", last = 0;
  for (const m of src.matchAll(/(?<![\d.\w/=])(?<!(?:約|捐|共|花|付|需|值)\s?)(\d{3,6})(?![\d.,]|\s*(?:[個隻只根張份塊件頭名條把顆片枚級%金銀銅格秒次碼號型倍]|經驗|XP|xp|分鐘|小時)|\s+\d+[.,]\d)/g)) {
    const num = m[1], at = m.index, id = +num, rest = src.slice(at + num.length);
    out += src.slice(last, at);
    last = at + num.length;
    const q = db.quest(id);
    // 地圖 ID 只在後面接座標、或前面寫「地圖／map」時保持原樣；和地圖 ID 同號的任務照樣換
    const keep = !q || (mapId(id) && (/^\s*[（(]?約?\s*\d{1,2}(?:[.,]\d+)?\s*[,，]/.test(rest) || /(?:地圖|map|uiMapID)\s*(?:ID)?\s*[｜|:：]?\s*$/i.test(out)))
      // 沒換掉的「第 N 步」「第 N–M、K 步」裡的數字是步驟編號，不是任務 ID
      || (/第[\s\d、，,–\-~～至到和與及]*$/.test(out) && /^[\s\d、，,–\-~～至到和與及]*步/.test(rest));
    if (keep) { out += num; continue; }
    // 顯示路線上寫的中文任務名（QuestieDB 有些永恆版任務只有英文）
    const name = [quests.get(id)?.n, questName(q)].find((n) => n && /\p{Script=Han}/u.test(n)) || questName(q);
    const names = [name, questName(q), q.zhTW, q.en, quests.get(id)?.n, quests.get(id)?.zt].filter(Boolean).sort((a, b) => b.length - a.length);
    idStats.set(idFile, (idStats.get(idFile) || 0) + 1);
    const sample = idFile + "：…" + src.slice(Math.max(0, at - 12), at + num.length + 4) + "… → " + name;
    if (idSamples.length < 40 && !idSamples.includes(sample)) idSamples.push(sample);
    const sep = out.match(/[\s（(「]*$/)[0];
    // 已寫的中文名照原樣留（路線標題和 QuestieDB 譯名不一定同一個），只有英文時才換成中文名
    let before = out.slice(0, out.length - sep.length), ws, n, shown;
    while ((n = names.find((x) => before.endsWith(x) || before.endsWith("（" + x + "）")))) {
      const paren = before.endsWith("（" + n + "）");
      const cut = before.slice(0, before.length - (paren ? n.length + 2 : n.length));
      before = cut.trimEnd();
      ws = cut.slice(before.length);
      shown = paren ? (!ws && /\p{Script=Han}$/u.test(before) ? "" : shown) : /\p{Script=Han}/u.test(n) ? n : shown; // 「中文（英文）」：中文是作者寫的譯名
    }
    if (ws !== undefined) out = before + (shown === "" ? "" : ws + (shown || name)) + sep; // 前面的名字整段收成一個中文名，拿掉 ID
    else if (!names.some((x) => rest.replace(/^[\s（(「]+/, "").startsWith(x))) out += name; // 名字已寫在 ID 後 → 只拿掉 ID
  }
  return (out + src.slice(last)).replace(/(?<![\d.])(\d{4})\s+(?=約?\s*\d{1,2}(?:\.\d+)?\s*[,，])/g, (all, num) => (mapId(+num) ? "" : all)) // 座標前的地圖 ID 不顯示
    .replace(/\s+([）)，。；])/g, "$1").replace(/（\s*）|\(\s*\)/g, "").replace(/\s+$/, "");
};
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
  manualAccept: s.manualAccept, wing: s.wing,
  pickupItem: s.pickupItem,
  sameObjective: s.sameObjective, sameMapPreview: s.t === "travel" && s.sameMapPreview || undefined, reserveOnVisit: s.t === "accept" && s.reserveOnVisit || undefined, strictReady: s.t === "do" && s.strictReady || undefined,
  exitPriority: s.ph === "post" && ["accept", "do", "turnin"].includes(s.t) && s.exitPriority || undefined,
  chooseGrindSpot: s.chooseGrindSpot, ungoroExit: s.ungoroExit,
  outsideHandoff: s.outsideHandoff || undefined,
  afterWork: s.afterWork, providedVisit: s.providedVisit, instanceMaterial: s.instanceMaterial || undefined, componentNpc: s.componentNpc,
  outsideObjective: s.ph && s.outsideObjective || undefined,
  star: s.star, t: s.t, any: s.any, instancePickup: s.ph === "in" && s.t === "accept" && s.instancePickup || undefined, q: s.t === "need" || s.t === "accept" || s.t === "do" || s.t === "turnin" ? s.id : undefined, ph: s.ph, pickLv: s.pickLv, recLv: s.recLv, share: s.share, preText: s.preText, opt: s.opt,
  // 說明段用「；」接起來：句號結尾的段後面不再補「；」，完全相同的段只留一次（翻譯照原本的「；」切段，不受影響）
  desc: s.desc && [...new Set(s.desc.split("；").map((x) => x.trim()).filter(Boolean))].reduce((a, x) => (a ? a + (/[。！？]$/.test(a) ? "" : "；") : "") + x, ""), spot: s.spot, tag: s.tag, npc: s.npc, tgt: s.tgt, hint: s.hint, text: s.text, key0: s.key0, item: s.item, n: s.n, fq: s.fq, pick: s.pick, node: s.node, bind: s.bind, to: s.to, from: s.from, lv: s.lv,
  map: s.coord?.map, x: s.coord?.x, y: s.coord?.y, more: s.more?.length ? s.more.map((p) => [p.map, p.x, p.y]) : undefined, via: s.via?.length ? s.via.map((p) => [p.map, p.x, p.y]) : undefined, skey: s.oldKeys?.length ? s.oldKeys.at(-1).at(-1) : undefined, akeys: s.oldKeys?.at(-1)?.length > 1 ? s.oldKeys.at(-1).slice(0, -1) : undefined, vkeys: s.oldKeys?.length > 1 ? s.oldKeys.slice(0, -1) : undefined, r: s.r, back: s.back, hm: s.hm, when: stepWhen(s.when, st.when), video: s.video, roam: s.roam, hold: s.hold, native: s.native,
});
// 打怪經驗估算的上限：每個目標最多算 KILL_CAP 隻（掉落目標＝數量 ÷ 掉率，沒寫掉率時和 Engine.lua 的 DROP_RATE 一樣用 0.4）
const KILL_CAP = 40, DROP_RATE = 0.4;
for (const q of quests.values()) for (const m of q.mob || []) {
  const rate = m[2] === 2 ? q.rate || DROP_RATE : 1;
  if (m[1] / rate > KILL_CAP) m[1] = Math.round(KILL_CAP * rate * 100) / 100;
}
let out = GUARD + `-- 由 tools/build.mjs 產生，勿手改。來源：${ALLY ? "route-alliance" : "route"}/*.md\nlocal _, MG = ...\nMG.Route = {\n  built = "@@BUILT@@",\n  stations = {\n`;
for (const s of stations) {
  idFile = s.file;
  refPrefix = s.dungeon ? s.after.split("-")[0] : s.id.split("-")[0];
  refSteps = s.steps.filter((x) => !x.cls); // 站的提醒：指主線的 md 編號
  // 起點路線：從 1 級開始的種族限定站，和接在後面、種族相同的站（01-9 這種多族共用的 9 級站不是起點，照 when 過濾）
  const raceKey = s.when?.race?.join("/");
  const start = raceKey && s.lv[0] <= 12 && stations.some((x) => x.lv[0] === 1 && x.when?.race?.join("/") === raceKey) ? raceKey : undefined;
  // 顯示用短名：去掉「第一次」，第二次起改成 visit＝2、3…（介面以淡色 (2) 顯示）；子區域有「與／、」只留第一個＋「等」
  let visit;
  const full = safeText(s.name);
  let short = full.replace(/\s*第([一二三四五])次$/, (_, c) => { visit = "一二三四五".indexOf(c) + 1; return ""; });
  const sp = short.indexOf(" ");
  if (sp > 0) {
    const parts = short.slice(sp + 1).split(/與|／|、/);
    if (parts.length > 1) short = short.slice(0, sp + 1) + parts[0] + "等";
  }
  out += `    { id=${lua(s.id)}, start=${lua(start)}, name=${lua(s.name)}, short=${lua(short !== full ? short : undefined)}, visit=${lua(visit > 1 ? visit : undefined)}, map=${lua(s.map)}, lv=${lua(s.lv)}, video=${lua(s.video)}, test=${lua(s.test || undefined)}, alt=${lua(s.alt)}, when=${lua(s.when)}, tips=${lua(s.tips.map((t) => ({ k: t.k, text: t.text, s: sentences(t.raw ?? t.text) })))}, dungeon=${lua(s.dungeon)}, grind=${lua(s.grind && s.grind.length ? s.grind.map((g) => ({ mob: g.mob, lv: g.lv, map: g.map, x: g.x, y: g.y, note: g.note })) : undefined)}, after=${lua(s.after)}, entrance=${lua(s.entrance?.text)}, pickup=${lua(s.pickup)}, pickupS=${lua(s.pickupRaw ? sentences(s.pickupRaw) : undefined)}, pickAt=${lua(s.pickAt)}, inst=${lua(s.inst)}, dq=${lua(s.dq)}, supply=${lua(s.supply)}, danger=${lua(s.danger)},\n      steps = {\n`;
  for (const [i, step] of s.steps.entries()) {
    if (!step.sameObjective) continue;
    const previous = s.steps[i - 1];
    if (step.t !== "do" || !step.when || !step.id || previous?.t !== "do" || previous.id !== step.id || previous.ph !== step.ph) {
      hard(step.where, "同一步座標必須是有條件的做，緊接同任務、同階段的做");
    }
  }
  for (const step of s.steps) if (step.t !== "accept" && step.t !== "do" && step.t !== "turnin" || step.id) { refSteps = s.steps.filter((x) => x.cls === step.cls); out += `        ${lua(stepOut(step, s))},\n`; }
  out += `      } },\n`;
}
refSteps = [];
idFile = "任務表";
// ── 06 路線外任務：任務ID｜任務名｜等級｜區域｜判定｜理由 ──
const VERDICT = new Set(["值得做", "之後順路", "可放掉"]);
const offroute = new Map();
const offAt = new Map(); // 任務 ID → 出處（英文理由用；offroute 整個輸出到 Route.lua）
for (const file of files.filter((f) => /^06-/.test(f))) {
  readFileSync(join(ROUTE, file), "utf8").split(/\r?\n/).forEach((line, li) => {
    const m = line.match(/^\s*-?\s*(\d+)｜(.*)$/);
    if (!m) return;
    const f = m[2].split("｜").map((x) => x.trim());
    if (!VERDICT.has(f[3])) return warn(`${file}:${li + 1}`, "判定看不懂：" + f[3]);
    if (quests.has(+m[1])) warn(`${file}:${li + 1}`, `任務 ${m[1]} 在路線上，路線外判定不會用到`);
    offroute.set(+m[1], { v: f[3], why: (f[4] || "").replace(/【[^】]*】/g, "").trim() || undefined });
    offAt.set(+m[1], `${file}:${li + 1}`);
  });
}
// 路線外但是路線任務的前置 → 值得做（接後續）
const feeds = new Map();
for (const [id, q] of quests) for (const p of [...(q.pg || []), ...(q.ps || [])]) if (!quests.has(p) && !feeds.has(p)) feeds.set(p, id);
// 07 訓練師.md 不讀了（學技能不排進路線）
// ── 08 保留物品：物品名｜物品ID｜何時拿到｜何時用到（用到的任務 ID 寫在文字裡就會在任務交掉後不再提示） ──
const keep = new Map();
const keepAt = new Map(); // 物品 ID → 出處（英文用途用）
for (const file of files.filter((f) => /^08-/.test(f))) {
  readFileSync(join(ROUTE, file), "utf8").split(/\r?\n/).forEach((line, li) => {
    const f = line.replace(/^\s*-\s*/, "").split("｜").map((x) => x.trim());
    if (f.length < 4 || !/^\d+$/.test(f[1])) return;
    const use = f[3].replace(/【[^】]*】/g, "").trim();
    const legacyQuest = [...f[3].matchAll(/\d{2,6}/g)].map((m) => +m[0]).find((n) => quests.has(n));
    const uses = [];
    for (const part of f[3].split("；")) {
      const id = Number(part.match(/[（(](\d{2,6})[）)]/)?.[1]);
      if (!quests.has(id)) continue;
      const tags = [...part.matchAll(/【([^】]*)】/g)].map((m) => m[1]);
      const count = Number(tags.find((tag) => /^保留數量[：:]\d+$/.test(tag))?.slice(5)) || undefined;
      uses.push({ q: id, when: parseWhen(tags), count });
    }
    const scoped = uses.some((v) => v.when || v.count);
    keep.set(+f[1], scoped ? { n: f[0], use, q: uses[0].q, uses } : { n: f[0], use, q: legacyQuest });
    keepAt.set(+f[1], `${file}:${li + 1}`);
  });
}
const luaMap = (m) => (m.size ? "{" + [...m].map(([k, v]) => `[${k}]=${lua(v)}`).join(", ") + "}" : "nil"); // 數字鍵（任務 ID）
out += `  },\n  offroute = ${luaMap(offroute)},\n  feeds = ${luaMap(feeds)},\n  keep = ${luaMap(keep)},\n`;
out += `  quests = {\n`;
for (const [id, q] of [...quests.entries()].sort((a, b) => a[0] - b[0])) {
  const { st, next, en, ...rest } = q;
  out += `    [${id}] = ${lua(rest)},\n`;
}
out += `  },\n}\n`;
// 台服用詞（tools/用詞.md）：只改說明文字欄位與句子陣列，任務名／NPC／怪名保持和遊戲一致
const wording = readFileSync(join(ROOT, "tools", "用詞.md"), "utf8").split(/\r?\n/)
  .map((l) => l.match(/^-\s*([^｜]+)｜(.*)$/)).filter(Boolean).map((m) => [m[1].trim(), m[2].trim()]);
// QuestieDB 的 zhTW 任務文字有一批是簡體硬轉的（一→壹、里→裏、钻→鉆…）：顯示用的說明欄位改回台灣寫法。
// 譯名裡的「里」（提里奧、塞納里奧…）先改回來，剩下的「裏」才是「裡」。任務名／NPC／怪名不經過這裡
const ZH_FIX = [
  ["裏→里（譯名）", /(加莫|提|塞納|卡|雷布|哈|瑪科|薩瓦|尤克|瑪艾|雷姆托|杜|加|格|索|貝|梅|史克|拉索)裏(?=塔|奧|爾|·|石板|克|希望|談|的營地|的頭顱|和取|楊|什|姆|薩拉|加爾)/g, "$1里"],
  ["裏→裡", /裏/g, "裡"], ["壹→一", /壹/g, "一"], ["只→隻（量詞）", /([0-9０-９一兩幾])只/g, "$1隻"],
  ["信息→訊息", /信息(?!素)/g, "訊息"], ["惟一→唯一", /惟一/g, "唯一"], ["激活→啟動", /激活/g, "啟動"], ["麽→麼", /麽/g, "麼"], ["凈→淨", /凈/g, "淨"], ["鉆→鑽", /鉆/g, "鑽"],
  ["余燼→餘燼", /余燼/g, "餘燼"], ["恒→恆", /恒/g, "恆"], ["采→採", /采/g, "採"], ["巖→岩", /巖/g, "岩"], ["沈沒→沉沒", /沈沒/g, "沉沒"], ["沖擊→衝擊", /沖擊/g, "衝擊"],
  ["咨詢→諮詢", /咨詢/g, "諮詢"], ["象征→象徵", /象征/g, "象徵"], ["聯系→聯繫", /聯系/g, "聯繫"], ["關系→關係", /關系/g, "關係"], ["頭發→頭髮", /頭發/g, "頭髮"],
  ["幹→乾", /曬幹|幹肉/g, (m) => m.replace("幹", "乾")], ["蔔→卜", /占蔔|地蔔師/g, (m) => m.replace("蔔", "卜")], ["制→製", /(?<![控限抑克壓強編機體])制(?=作|造|成)|粗制/g, (m) => m.replace("制", "製")],
];
const zhFixed = new Map();
const reword = (text) => ZH_FIX.reduce((t, [label, from, to]) => t.replace(from, (...m) => {
  zhFixed.set(label, (zhFixed.get(label) || 0) + 1);
  return typeof to === "function" ? to(m[0]) : to.replace("$1", m[1]);
}), wording.reduce((t, [from, to]) => t.split(from).join(to), text));
out = out
  .replace(/\b(d|desc|spot|hint|pickup|text|why|use|note|entrance)="(?:[^"\\]|\\.)*"/g, reword)
  .replace(/\b(s|pickupS)=\{(?:[^{}"]|"(?:[^"\\]|\\.)*")*\}/g, reword);
// 資料版本＝內容雜湊（不放時間，內容沒變就不會產生差異）
const version = createHash("sha1").update(out).digest("hex").slice(0, 8);
out = out.replace("@@BUILT@@", version);
writeFileSync(OUT, out);
// QuestieDB 快照與釘選版本：記下這份 Data 用到的任務欄位（路線任務與它們的前置），CI 不用 QuestieDB 也能核對 Data。
// 本機版本和上次建置不同時，列出路線任務的欄位變動（建置前也可先跑 node tools/questiedb-drift.mjs）
{
  const side = ALLY ? "Alliance" : "Horde";
  const dir = process.env.OUT_LUA ? dirname(OUT) : join(ROOT, "tools"); // 測試建置寫到輸出旁邊，不動 repo 的快照
  const snapFile = join(dir, "questiedb-snapshot.tsv"), verFile = join(dir, "questiedb-version.txt");
  const oldText = existsSync(snapFile) ? readFileSync(snapFile, "utf8") : "";
  const before = readSnapshot(oldText);
  // 路線任務、Data 裡的前置、QuestieDB 的前置都要有列；QuestieDB 沒有的記 SNAPSHOT_GONE，消失時才會列進變動，guard 也能查缺列
  const ids = [...new Set([...quests].flatMap(([id, e]) => { const q = db.quest(id); return [id, ...(e.pg || []), ...(e.ps || []), ...(q ? [...q.preGroup.map(Math.abs), ...q.preSingle] : [])]; }))].sort((a, b) => a - b);
  const after = new Map(ids.map((id) => [`${side}\t${id}`, `${side}\t${db.snapshot(id) ?? `${id}\t${SNAPSHOT_GONE}`}`]));
  const pins = new Map((existsSync(verFile) ? readFileSync(verFile, "utf8") : "").split(/\r?\n/).filter((l) => l && !l.startsWith("#")).map((l) => [l.split("\t")[0], l]));
  const local = localVersion(), pinned = pins.get(side)?.split("\t")[1];
  if (pinned !== local) {
    const changes = diffSnapshot(before, after);
    console.warn(`警告：本機 QuestieDB（${local}）和上次建置釘選的（${pinned || "無"}）不同；路線任務欄位變動 ${changes.length} 筆，逐筆核對後記進 ROUTE-AUDIT.md：\n${changes.join("\n")}`);
  }
  const rows = [...[...before].filter(([k]) => !k.startsWith(side + "\t")).map(([, l]) => l), ...after.values()]
    .sort((a, b) => b.startsWith("Horde") - a.startsWith("Horde") || +a.split("\t")[1] - +b.split("\t")[1]); // 部落在前，再依任務 ID
  writeFileSync(snapFile, `# ${SNAPSHOT_COLS.join("\t")}\n# 由 tools/build.mjs 產生，勿手改\n${rows.join("\n")}\n`);
  pins.set(side, `${side}\t${local}\t${version}`);
  writeFileSync(verFile, `# 陣營\tQuestieDB 版本\tData 資料版本（built）：由 tools/build.mjs 產生，勿手改\n${["Horde", "Alliance"].filter((k) => pins.has(k)).map((k) => pins.get(k)).join("\n")}\n`);
}
console.log(`簡體硬轉字改回台灣寫法 ${[...zhFixed.values()].reduce((a, b) => a + b, 0)} 處：${[...zhFixed].map(([k, n]) => `${k} ${n}`).join("、") || "無"}`);

// ── Data/Route_enUS.lua：英文介面／英文客戶端用的名稱與說明（站 ID＋步驟序號、任務 ID 對到 Route.lua）──
// 之後加語言：再產生一個 Route_<locale>.lua，結構相同
const plain = (v) => {
  if (v === undefined || v === null) return "nil";
  if (typeof v === "boolean" || typeof v === "number") return String(v);
  if (typeof v === "string") return JSON.stringify(safeText(v));
  if (Array.isArray(v)) return "{" + v.map(plain).join(", ") + "}";
  const e = Object.entries(v).filter(([, x]) => x !== undefined && !(Array.isArray(x) && !x.length) && !(x && typeof x === "object" && !Array.isArray(x) && !Object.keys(x).length));
  return "{" + e.map(([k, x]) => `${/^[A-Za-z_]\w*$/.test(k) ? k : /^\d+$/.test(k) ? "[" + k + "]" : "[" + JSON.stringify(k) + "]"}=${plain(x)}`).join(", ") + "}";
};
const reverseGame = Object.fromEntries(Object.entries(GAME_NAME).map(([a, b]) => [b, a]));
const npcEn = (n) => { const c = cleanName(n); return c ? mdName(c) || db.enByZh("Npc", c) || (reverseGame[c] && db.enByZh("Npc", reverseGame[c])) : undefined; };
const questEn = (id) => quests.get(id)?.en?.n || db.quest(id)?.en;
const missNpc = [];
// 英文短站名（清單、站名列用；全名在滑鼠提示）：24 字內用全名；否則「區域: 地點」依序去掉開頭 The、括號說明、「&」之後的地點（留「+」），再不行只留地點
const SHORT_MAX = 24;
const shortEn = (n) => {
  if (!n || n.length <= SHORT_MAX) return undefined;
  const noThe = (x) => x.replace(/^The /, "");
  const bare = (x) => x.replace(/\s*\(.*\)$/, "");
  const sep = n.indexOf(": ");
  const zone = sep > 0 ? noThe(n.slice(0, sep)) + ": " : "";
  const place = sep > 0 ? n.slice(sep + 2) : n;
  const parts = bare(place).split(/ & | to /);
  const first = parts[0] + (parts.length > 1 ? " +" : "");
  const tries = [noThe(n), zone + bare(place), zone + first, bare(place), first, parts[0]];
  return tries.find((x) => x.length <= SHORT_MAX) || parts[0];
};
// 說明文字英文（tools/route-text-enUS.md，Codex 翻）：檔名:行號｜類型｜中文原文｜英文（原文裡有｜時，前兩個和最後一個｜切欄）
// 先比對「檔名:行號＋原文」，再只比對原文；比對時去掉【】標記與多餘空白。英文還有中日韓字的列不用（英文介面不顯示）
const txKey = (s) => String(s || "").replace(/【[^】]*】/g, "").replace(/｜/g, "：").replace(/\s+/g, " ").trim(); // ｜：粗體註記的分隔，顯示時換成「：」
const CJK = /[　-〿぀-ヿ㐀-鿿가-힯＀-￯]/;
const TX_ROWS = [], TX_AT = new Map(), TX = new Map(), txUsed = new Set();
// 聯盟另有 tools/route-text-alliance-<loc>.md：先讀，同檔名同行號時優先
const txLines = (loc) => {
  const own = join(ROOT, "tools", `route-text-alliance-${loc}.md`);
  return (ALLY && existsSync(own) ? readFileSync(own, "utf8").split(/\r?\n/) : []).concat(readFileSync(join(ROOT, "tools", `route-text-${loc}.md`), "utf8").split(/\r?\n/));
};
const txNeed = new Map(); // 英文翻不到的中文（TX_NEED=檔案 時輸出，拿去翻）
for (const line of txLines("enUS")) {
  const f = line.split("｜");
  if (f.length < 4 || !/\.md:\d+$/.test(f[0])) continue;
  const row = { at: f[0], type: f[1], zh: txKey(f.slice(2, -1).join("｜")), en: f[f.length - 1].trim() };
  TX_ROWS.push(row);
  if (!row.zh || !row.en || CJK.test(row.en)) continue;
  if (!TX_AT.has(row.at + "|" + row.zh)) TX_AT.set(row.at + "|" + row.zh, row.en);
  if (!TX.has(row.zh)) TX.set(row.zh, row.en);
}
// 譯文裡的站號（stop 29、Station 2 von Teil 1、04-parada 58、第4部分第59站、29번째 지점…）→ 該語系的站名；站號全路線不重複，不必看第幾部分。
// 只換中文原文裡寫成「第N站」的那些號碼（法文、俄文的「étape／этап N」也拿來寫「第 N 步」，不能照字面全換）。
// 緊跟在地名後面的括號（Tanaris (1st visit, stop 38)）只拿掉站號。建置時沒有站名的（遊戲裡用地圖名）寫成 {s:站ID}，E.Localize 換
const STOP_W = "(?:[Ss]top|Station|l['’]étape|étape|(?:(?<![A-Za-zÀ-ÿ])la )?parada|остановк[а-яё]*|этап[а-яё]*|지점|정거장)";
const stationRefs = (t, zh, nameOf) => {
  const nums = new Set([...String(zh || "").matchAll(/第\s*(\d+)\s*(?:[–\-~－到或]\s*第?\s*(\d+)\s*)?站/g)].flatMap((m) => [m[1], m[2]]).filter(Boolean).map(Number));
  if (!nums.size) return t;
  const name = (all, n) => (nums.has(+n) && nameOf(+n)) || all;
  const drop = (all, a, b) => (nums.has(+(a || b)) ? "" : all);
  return t
    .replace(new RegExp("\\s*[（(]\\s*(?:第\\s*(\\d+)\\s*站|" + STOP_W + " (\\d+)|(\\d+)번(?:째)? ?" + STOP_W + ")\\s*[)）]", "g"), (all, z, a, b) => drop(all, z || a, b))
    .replace(new RegExp("[,，] ?(?:" + STOP_W + " (\\d+)|(\\d+)번(?:째)? ?" + STOP_W + ")(?=[)）])", "g"), drop)
    .replace(new RegExp("(?:\\d{1,2}-)?" + STOP_W + " (\\d+) (?:of|von|de la|da|de) (?:part|chapter|Teil|partie|parte) \\d+", "g"), name)
    .replace(new RegExp(STOP_W + " (\\d+) части \\d+", "g"), name)
    .replace(new RegExp("\\d+부 (\\d+)번(?:째)? ?" + STOP_W, "g"), name)
    .replace(/第\s*\d+\s*部分第\s*(\d+)\s*站/g, name)
    .replace(new RegExp("(?<!\\d)\\d{1,2} ?- ?(?:" + STOP_W + " ?(\\d+)번?|第\\s*(\\d+)\\s*站|(\\d+)번(?:째)? ?" + STOP_W + "|(\\d+)[-‑]?(?:й|го|м)? ?" + STOP_W + ")", "g"), (all, a, b, c, d) => name(all, a || b || c || d))
    .replace(new RegExp("(?<!\\d)\\d{1,2}, (" + STOP_W + ") (\\d+)", "g"), (all, w, n) => name(all, n))
    .replace(new RegExp(STOP_W + " (\\d+)번?(?!\\d|[.,]\\d)", "g"), name)
    .replace(new RegExp("(?<![\\d.,])(\\d+)(?:번(?:째)?|[-‑]?(?:й|го|м))? ?" + STOP_W, "g"), name)
    .replace(/第\s*(\d+)\s*站/g, name);
};
// 英文裡的任務 ID → 英文任務名（名字已寫在旁邊就只拿掉 ID）；「02-Stop 8」→ 英文站名；座標前的地圖 ID 拿掉（hit：記下換掉的任務 ID，其他語系照著換）
const enIds = (t, hit) => t
  .replace(/\b(\d{2})-Stop (\d+)/g, (all, p, n) => { const x = stations.find((s) => s.id === p + "-" + n); return (x && (STATION_EN[safeText(x.name)] || x.en)) || all; })
  .replace(/(?<![\d.\w×]|level |Level |lv\.? )(\d{3,6})(?![\d%]|[.,]\d|\s*(?:×|x\d)|\s*(?:experience|exp|xp|XP|gold|g)\b|\s+(?:[Aa]bout|[Aa]pprox\w*\.? )?\d+[.,]\d)/g, (all, num, at, whole) => {
    const id = +num;
    const name = !MAP_IDS.has(id) && db.quest(id) && questEn(id);
    if (!name) return all;
    if (hit) hit.add(id);
    const before = whole.slice(0, at).replace(/[\s("]+$/, ""), after = whole.slice(at + num.length).replace(/^[\s("]+/, "");
    return before.endsWith(name) || after.startsWith(name) ? "" : name;
  })
  .replace(/(?<![\d.])(\d{4})\s+(?=(?:about |approx\w*\.? )?\d{1,2}(?:\.\d+)?\s*,)/gi, (all, num) => (MAP_IDS.has(+num) || (+num >= 1400 && +num < 3000) ? "" : all))
  .replace(/\(\s*\)/g, "").replace(/\s+([),.;])/g, "$1").replace(/ {2,}/g, " ").trim();
const tx = (where, zh) => {
  const k = txKey(zh);
  if (k && !CJK.test(k.replace(/／/g, "/"))) return k.replace(/／/g, "/"); // 原文本來就是英文（目標怪名、物品名）
  const en = k && (TX_AT.get(where + "|" + k) ?? TX.get(k));
  if (!en) { if (k && !txNeed.has(k)) txNeed.set(k, where); return undefined; }
  txUsed.add(k);
  return stationRefs(enIds(en), k, (n) => { const x = stations.find((s) => s.id.endsWith("-" + n)); return x && (STATION_EN[safeText(x.name)] || x.en || "{s:" + x.id + "}"); });
};
// 英文句子（站的提醒、前置接取路線）：中文每句有種族／職業條件時，句數相同就逐句對上；全部同條件就整段套；對不上就不帶條件
const enSplit = (t) => t.split(/(?<=[.;!?])\s+(?=[A-Z0-9"'(])/).map((x) => x.replace(/[.;]$/, "").trim()).filter(Boolean);
const enSents = (zhRaw, en, join, split = enSplit) => {
  const whens = sentences(zhRaw).map((x) => x[1]);
  const same = whens.every((w) => JSON.stringify(w) === JSON.stringify(whens[0]));
  if (join && same) return whens[0] ? [[en, whens[0]]] : undefined; // 交通、取捨：介面整段接成一句
  const es = split(en);
  if (es.length === whens.length) return es.map((x, i) => (whens[i] ? [x, whens[i]] : [x]));
  if (!same) cov.whenLost++;
  return es.map((x) => (same && whens[0] ? [x, whens[0]] : [x]));
};
const cov = { steps: 0, hint: 0, hintGen: 0, tgtNeed: 0, tgt: 0, npcNeed: 0, npc: 0, stName: 0, stations: 0, quests: 0, qName: 0, qObj: 0, whenLost: 0, zhOnly: { desc: 0, tips: 0, travelText: 0, note: 0, grindNote: 0, danger: 0, offrouteWhy: 0, pickup: 0, entrance: 0, keepUse: 0, tag: 0, star: 0 } };
const leftAt = []; // 翻了之後仍只有中文的步驟欄位（TX_MISS 報告用）
const left = Object.fromEntries(Object.keys(cov.zhOnly).map((k) => [k, 0])); // 翻了之後仍只有中文（英文介面不顯示）
const newCov = () => JSON.parse(JSON.stringify(cov));
// Route_<locale>.lua 一份：X 給這個語系的換字函式（英文全是原樣）
// T 說明文字、N 名稱（選取目標要和遊戲內一字不差）、F 固定字、station 站名、node 鳥點、qn 任務名、qd 任務目標文字、item 物品名
const emitRoute = (X) => {
  const { loc, N, F, cov, left, leftAt, missNpc } = X;
  // 說明文字裡的「第 N 步」換成被指那步的名字（stepRefs）：英文帶動詞，其他語系只用任務／地點名
  const EN_VERB = { accept: "Accept ", do: "Do ", turnin: "Turn in ", fp: "Flight path: ", hearth: "Hearth to ", bind: "Set hearth: " };
  const title = (s) => {
    const name = s.id && ["accept", "do", "turnin"].includes(s.t) ? X.qName(s.id, quests.get(s.id)?.en || {}) : s.t === "fp" ? X.node(s).node : (s.t === "hearth" || s.t === "bind") && s.bind ? X.node({ ...s, node: s.bind }).node : undefined;
    return name && (loc === "enUS" ? EN_VERB[s.t] : "") + name;
  };
  const kind = loc === "zhCN" ? "zh" : loc === "koKR" ? "ko" : "latin";
  const T = (where, zh) => stepRefs(X.T(where, zh), title, kind, zh);
  let en = GUARD + `-- 由 tools/build.mjs 產生，勿手改。${LUA_PREFIX}.lua 的${X.title}名稱與說明（站 ID→步驟序號、任務 ID）\n-- 包成函式：只有介面、客戶端用到的語系才建表（Engine.lua E.Localize），其餘載入後就丟掉\nlocal _, MG = ...\nMG.RouteL = MG.RouteL or {}\nMG.RouteL.${loc} = function() return {\n  stations = {\n`;
  for (const s of stations) {
    cov.stations++;
    const nm = X.station(s);
    const name = nm.name;
    if (name) cov.stName++;
    const steps = {};
    let k = 0;
    for (const step of s.steps) {
      if (!(step.t !== "accept" && step.t !== "do" && step.t !== "turnin" || step.id)) continue;
      k++;
      refSteps = s.steps.filter((x) => x.cls === step.cls);
      cov.steps++;
      const e = {};
      const q = step.id && quests.get(step.id);
      if (step.componentNpcId) {
        // The Forever esES name differs from the Questie translation and from esMX.
        const nativeName = step.componentNpcId === 641 && loc === "esES" ? "Tallamadera goblin" : undefined;
        e.componentNpc = nativeName || db.l10nName("Npc", step.componentNpcId, loc) || db.npc(step.componentNpcId)?.en;
      }
      if (step.t === "accept" || step.t === "turnin") {
        e.npc = N(step.npcEn || mdEnt(step.id, step.npc)); e.tgt = N(step.tgtEn || (step.tgt && mdEnt(step.id, step.tgt))); e.npcObj = step.npcObj || (/^(物件|物品)/.test(step.npc || "") || undefined);
        cov.npcNeed++; if (e.npc) cov.npc++; else missNpc.push(`${step.id} ${step.npc}`);
        if (step.tgt) { cov.tgtNeed++; if (e.tgt) cov.tgt++; }
      } else if (step.t === "do") {
        cov.hint++;
        e.hint = (step.providedVisit || step.farmMaterial || step.riftTools || (step.requiredItems && step.when?.workMap)) ? T(step.where, step.hint) : X.hint(q, step.id);
        if (!q?.en?.d && q?.en?.gen) cov.hintGen++;
        if (!e.hint) { cov.hint--; e.hint = F.complete; }
      } else if (step.t === "need") e.text = F.prereq + (X.qn(step.id) || F.quest + step.id);
      else if (step.t === "travel" && /^前往 .+ 入口$/.test(step.text || "")) e.text = F.entrance.replace("%s", () => name || F.dungeon);
      else if ((step.t === "travel" || step.t === "bind" || step.t === "goto" || step.t === "note") && step.text) {
        const kind = step.t === "note" ? "note" : "travelText";
        cov.zhOnly[kind]++;
        e.text = step.text && T(step.where, step.text);
        if (!e.text) left[kind]++;
      }
      // 任一組的接：清單標題＝該語系任務名的共同部分（「Camping 101: 剝皮」的冒號前）＋翻譯的括號說明（route-text 的「（任選專業）」）
      if (step.any && step.text) {
        cov.zhOnly.travelText++;
        const base = X.qName(step.id, quests.get(step.id)?.en || {}).replace(/\s*[:：].*$/, ""), tail = (step.text.match(/（[^（）]*）$/) || [])[0];
        const suffix = tail && T(step.where, tail);
        e.text = suffix ? base + (/^[（(]/.test(suffix) && /^（/.test(suffix) ? "" : " ") + suffix : undefined;
        if (!e.text) { left.travelText++; leftAt.push(step.where + "｜任一｜" + step.text); }
      }
      if (step.t === "buy") { e.text = cleanName(db.l10nName("Item", step.item, loc) || db.itemEn(step.item) || "") || undefined; e.npc = N(npcEn(step.npc)); }
      if (step.t === "fp") Object.assign(e, X.node(step));
      // 飛、船的目的地／出發地：顯示用譯名（Route.lua 的 to／from 留中文給判斷用）
      if ((step.t === "fly" || step.t === "boat") && step.to) { const a = X.node({ ...step, node: step.to }); e.to = a.node; e.toA = a.nodeA; }
      if (step.t === "boat" && step.from) { const a = X.node({ ...step, node: step.from }); e.from = a.node; e.fromA = a.nodeA; }
      // 爐石地點（標題用）：其他語系拿到的只是英文名就不放，標題改用 hm 的地圖名（遊戲語言）
      if ((step.t === "hearth" || step.t === "bind") && step.bind) { const b = X.node({ ...step, node: step.bind }); e.bind = loc === "enUS" || b.node !== NODE_EN[step.bind] ? b.node : undefined; e.bindA = b.nodeA; }
      if (step.tag) {
        // 標籤：固定對照（TAG_EN）＞翻譯檔；「目標：…」「提醒：…」翻內容
        const parts = step.tag.split(/\s*・\s*/).map((t) => t.trim()).filter(Boolean).map((t) => {
          const fixed = X.tag(t, step.where);
          if (fixed) return fixed;
          const m = t.match(/^(目標|提醒)[：:]\s*(.+)$/);
          const x = T(step.where, m ? m[2] : t);
          return x && (m && m[1] === "目標" ? F.target + x : x);
        });
        if (!tagEn(step.tag)) cov.zhOnly.tag++;
        if (parts.some((x) => !x)) { left.tag++; leftAt.push(step.where + "｜標籤｜" + step.tag); }
        e.tag = parts.some(Boolean) ? [...new Set(parts.filter(Boolean))].join(F.sep) : undefined;
      }
      if (step.desc) {
        // 說明是【說明：】【位置：】【順序：】用「；」接起來的（每段自己也可能有「；」）：從頭找最長對得上的一段
        cov.zhOnly.desc++;
        const segs = step.desc.split("；"), parts = [];
        for (let i = 0; i < segs.length;) {
          let j = segs.length, hit;
          for (; j > i && !hit; j--) {
            const d = segs.slice(i, j).join("；"), m = d.match(/^(位置|順序)：(.*)$/s);
            const x = T(step.where, m ? m[2] : d);
            hit = x && (m ? (m[1] === "位置" ? F.loc : F.order) : "") + x;
          }
          parts.push(hit);
          i = hit ? j + 1 : i + 1;
        }
        if (parts.some((x) => !x)) { left.desc++; leftAt.push(step.where + "｜說明｜" + step.desc); }
        e.desc = parts.some(Boolean) ? parts.filter(Boolean).map(X.endDot).join(F.join) : undefined;
      }
      if (step.spot) {
        cov.zhOnly.desc++;
        e.spot = T(step.where, step.spot);
        if (step.ph === "in" && step.when?.missingBag && e.spot) e.hint = e.spot;
        if (!e.spot) { left.desc++; leftAt.push(step.where + "｜所在｜" + step.spot); }
      }
      if (step.preText) { const ids = [...step.preText.matchAll(/\d{2,6}/g)].map((m) => +m[0]).filter((x) => db.quest(x)); e.preText = ids.length ? ids.map(X.qn).join(F.sep) : undefined; }
      if (step.star) {
        const n = db.enByZh("Item", step.star[0]);
        if (!n) cov.zhOnly.star++;
        const n2 = X.item(n) || T(step.where, step.star[0]);
        if (!n2) { left.star++; leftAt.push(step.where + "｜★｜" + step.star[0]); }
        e.star = n2 ? [n2, ...step.star.slice(1)] : undefined;
      }
      steps[k] = e;
    }
    cov.zhOnly.tips += s.tips.length; cov.zhOnly.pickup += s.pickup ? 1 : 0; cov.zhOnly.entrance += s.entrance ? 1 : 0;
    cov.zhOnly.grindNote += (s.grind || []).filter((g) => g.note).length;
    cov.zhOnly.danger += (s.danger || []).length;
    // 站的提醒／交通／取捨／說明／動線（k 是判斷用，保持中文）；翻不到的整條不放
    refSteps = s.steps.filter((x) => !x.cls);
    const tips = s.tips.map((t) => {
      const text = T(t.where, t.raw) || (t.src && T(t.where, t.src));
      if (!text) { left.tips++; return undefined; }
      if (t.k === "動線") return { k: t.k, text: X.route(text) };
      return { k: t.k, text, s: enSents(t.raw, text, t.k === "交通" || t.k === "取捨", X.split) };
    }).filter(Boolean);
    const pickup = s.pickupRaw && T(s.pickupAt, s.pickupRaw);
    if (s.pickup && !pickup) left.pickup++;
    // 入口：介面只用括號裡的分區門說明（區域、座標另外取）；地圖 ID 由 enIds 拿掉
    const entrance = s.entrance && T(s.entrance.where, s.entrance.raw);
    if (s.entrance && !entrance) left.entrance++;
    const danger = {}; (s.danger || []).forEach((d, i) => { danger[i + 1] = T(s.dangerAt[i], d.text); if (!danger[i + 1]) left.danger++; });
    const grind = {}; (s.grind || []).forEach((g, i) => { const note = g.note && T(g.where, g.note); if (g.note && !note) left.grindNote++; grind[i + 1] = { mob: N(g.npcId ? db.npc(g.npcId)?.en : npcEn(g.mob)), note }; });
    const supply = {}; (s.supply || []).forEach((x, i) => { supply[i + 1] = { npc: x.npc && N(npcEn(x.npc)) }; });
    en += `    [${JSON.stringify(s.id)}] = ${plain({ name, nameA: nm.nameA, short: nm.short, shortA: nm.shortA, entrance, pickup, pickupS: pickup && enSents(s.pickupRaw, pickup, false, X.split), tips, danger, grind, supply, steps })},\n`;
  }
  refSteps = [];
  en += `  },\n  quests = {\n`;
  // Verified Forever display names for the chosen Ambermill NPCs in this gathering route.
  const farmNames = {
    "Dalaran Apprentice": { esES:"Aprendiz Dalaran", frFR:"Apprenti de Dalaran", koKR:"달라란 수습마법사", ruRU:"Даларанский ученик" },
    "Dalaran Protector": { ruRU:"Даларанский заступник" },
  };
  for (const [id, q] of [...quests.entries()].sort((a, b) => a[0] - b[0])) {
    cov.quests++;
    const e = q.en || {};
    if (e.n) cov.qName++;
    if (e.d) cov.qObj++;
    let star;
    if (q.star) { const n = X.item(db.enByZh("Item", q.star[0])) || T("", q.star[0]); star = n ? [n, ...q.star.slice(1)] : undefined; }
    const tgo = e.tgo?.map(group => group.map(name => (q.farmMaterial && farmNames[name]?.[loc]) || N(name)));
    en += `    [${id}] = ${plain({ n: X.qName(id, e), d: X.qd(id, e), tgo, objs: e.objs && e.objs.map(N), star })},\n`;
  }
  en += `  },\n`;
  const keepEn = (id, k) => { if (k.q) return undefined; const x = T(keepAt.get(id), k.use); if (!x) left.keepUse++; return x || F.later; };
  en += `  keep = ${plain(Object.fromEntries([...keep].map(([id, k]) => [id, { n: X.itemId(id), use: keepEn(id, k) }])))},\n`;
  const offEn = (id, o) => { const x = o.why && T(offAt.get(id), o.why); if (o.why && !x) left.offrouteWhy++; return x; };
  en += `  offroute = ${plain(Object.fromEntries([...offroute].map(([id, o]) => [id, { why: offEn(id, o) }])))},\n} end\n`;
  return en;
};
const FIX = {
  enUS: { complete: "Complete the quest objectives.", prereq: "Prerequisite: ", quest: "quest ", entrance: "%s entrance", dungeon: "Dungeon", loc: "Location: ", order: "Order: ", target: "Target: ", later: "Needed for a later quest", qobj: "Quest object", kill: "Kill: ", loot: "Loot from: ", use: "Use/collect: ", sep: ", ", join: " ", dot: ".", sent: ". " },
  zhCN: { tags: { 副本前置鏈: "副本前置链" }, complete: "完成任务目标。", prereq: "前置：", quest: "任务 ", entrance: "%s 入口", dungeon: "副本", loc: "位置：", order: "顺序：", target: "目标：", later: "之后的任务会用到", qobj: "任务物件", kill: "击杀：", loot: "掉落自：", use: "使用／收集：", sep: "、", join: "", dot: "。", sent: "。" },
  deDE: { tags: { 副本前置鏈: "Dungeon-Vorquest" }, complete: "Questziele erfüllen.", prereq: "Voraussetzung: ", quest: "Quest ", entrance: "Eingang: %s", dungeon: "Dungeon", loc: "Ort: ", order: "Reihenfolge: ", target: "Ziel: ", later: "Für eine spätere Quest benötigt", qobj: "Questobjekt", kill: "Töten: ", loot: "Beute von: ", use: "Benutzen/Sammeln: " },
  frFR: { tags: { 副本前置鏈: "Prérequis de donjon" }, complete: "Remplissez les objectifs de la quête.", prereq: "Prérequis : ", quest: "quête ", entrance: "Entrée : %s", dungeon: "Donjon", loc: "Lieu : ", order: "Ordre : ", target: "Cible : ", later: "Nécessaire pour une quête ultérieure", qobj: "Objet de quête", kill: "Tuer : ", loot: "Butin sur : ", use: "Utiliser/ramasser : " },
  esES: { tags: { 副本前置鏈: "Requisito de mazmorra" }, complete: "Completa los objetivos de la misión.", prereq: "Requisito previo: ", quest: "misión ", entrance: "Entrada: %s", dungeon: "Mazmorra", loc: "Ubicación: ", order: "Orden: ", target: "Objetivo: ", later: "Necesario para una misión posterior", qobj: "Objeto de misión", kill: "Matar: ", loot: "Botín de: ", use: "Usar/recoger: " },
  ptBR: { tags: { 副本前置鏈: "Pré-requisito de masmorra" }, complete: "Complete os objetivos da missão.", prereq: "Pré-requisito: ", quest: "missão ", entrance: "Entrada: %s", dungeon: "Masmorra", loc: "Local: ", order: "Ordem: ", target: "Alvo: ", later: "Necessário para uma missão posterior", qobj: "Objeto de missão", kill: "Matar: ", loot: "Saque de: ", use: "Usar/coletar: " },
  ruRU: { tags: { 副本前置鏈: "Подготовка к подземелью" }, complete: "Выполните задачи задания.", prereq: "Требуется: ", quest: "задание ", entrance: "Вход: %s", dungeon: "Подземелье", loc: "Место: ", order: "Порядок: ", target: "Цель: ", later: "Понадобится для следующего задания", qobj: "Объект задания", kill: "Убить: ", loot: "Добыча с: ", use: "Использовать/собрать: " },
  koKR: { tags: { 副本前置鏈: "던전 선행" }, complete: "퀘스트 목표를 완료하세요.", prereq: "선행 퀘스트: ", quest: "퀘스트 ", entrance: "%s 입구", dungeon: "던전", loc: "위치: ", order: "순서: ", target: "대상: ", later: "이후 퀘스트에 필요", qobj: "퀘스트 물체", kill: "처치: ", loot: "획득처: ", use: "사용/수집: " },
};
FIX.esMX = FIX.esES;
for (const loc of Object.keys(FIX)) FIX[loc] = { ...FIX.enUS, ...FIX[loc] };
const routeEn = emitRoute({
  loc: "enUS", title: "英文", T: tx, N: (n) => n, F: FIX.enUS, cov, left, leftAt, missNpc,
  station: (s) => { const name = STATION_EN[safeText(s.name)] || (s.dungeon ? s.en && safeText(s.en) : undefined); return { name, short: s.dungeon ? undefined : shortEn(name) }; },
  node: (step) => ({ node: NODE_EN[step.node] || tx(step.where, step.node) }),
  tag: (t) => TAG_EN[t],
  hint: (q) => q?.en?.d?.split("\n")[0] || q?.en?.gen,
  qn: questEn, qName: (id, e) => e.n, qd: (id, e) => e.d || e.gen, item: (n) => n, itemId: (id) => db.itemEn(id),
  endDot: (x) => (/[.!?)]$/.test(x) ? x : x + "."), split: enSplit,
  route: (text) => text.replace(/\s*\((?:steps? )?\d+(?:\s*[–-]\s*\d+)?\)/gi, ""),
});
cov.zhOnly.offrouteWhy = [...offroute.values()].filter((o) => o.why).length;
cov.zhOnly.keepUse = [...keep.values()].filter((k) => !k.q).length;
writeFileSync(join(dirname(OUT), `${LUA_PREFIX}_enUS.lua`), routeEn);
const pct = (a, b) => (b ? Math.round((a / b) * 1000) / 10 : 100) + "%";
console.log(`英文：站名 ${cov.stName}/${cov.stations}（${pct(cov.stName, cov.stations)}）、接交 NPC ${cov.npc}/${cov.npcNeed}（${pct(cov.npc, cov.npcNeed)}）、選取目標 tgt ${cov.tgt}/${cov.tgtNeed}（${pct(cov.tgt, cov.tgtNeed)}）、做步驟提示 ${cov.hint}（其中湊句 ${cov.hintGen}）、任務名 ${cov.qName}/${cov.quests}、任務目標文字 ${cov.qObj}/${cov.quests}`);
console.log("說明文字英文（route-text-enUS.md，翻到／原本只有中文）：" + Object.entries(cov.zhOnly).map(([k, v]) => `${k} ${v - left[k]}/${v}`).join("、") + `；條件對不上改為不帶條件 ${cov.whenLost}`);
const txMiss = TX_ROWS.filter((r) => !txUsed.has(r.zh));
console.log(`翻譯列 ${TX_ROWS.length}，用到 ${TX_ROWS.length - txMiss.length}；英文含中日韓字（不用）${TX_ROWS.filter((r) => CJK.test(r.en)).length}；沒用到（依類型）：` + Object.entries(Object.groupBy(txMiss, (r) => r.type)).map(([k, v]) => k + " " + v.length).join("、"));
if (process.env.TX_MISS) writeFileSync(process.env.TX_MISS, leftAt.concat(txMiss.map((r) => `${r.at}｜${r.type}｜${r.zh}`)).join("\n"));
console.log("英文缺接交 NPC：" + missNpc.join("、"));
if (process.env.TX_NEED) writeFileSync(process.env.TX_NEED, [...txNeed].map(([k, w]) => `${w}｜說明｜${k}｜`).join("\n"));
console.log(`english-names.md：任務 ${MD_QUEST.size}、實體 ${MD_ENT.size}、名稱 ${MD_NAME.size}；和 QuestieDB 英文不同：任務名 ${enDiff.quest}、接交 NPC ${enDiff.npc}、選取目標 ${enDiff.tgt}`);

// ── 其他語系：Data/Route_<locale>.lua，結構同 Route_enUS.lua，每一欄翻不到就用英文 ──
// 名稱：tools/names-<locale>.md（英文名 → 該語系，Codex 查的永恆客戶端名）＞ QuestieDB 該語系＞英文
// 說明文字：tools/route-text-<locale>.md（格式同 enUS）＞英文；任務名、任務目標文字：QuestieDB 該語系＞英文（遊戲內的任務名執行時另由 API 取）
// 站名：區域名用 Questie 的區域翻譯；城鎮寫成 {a:地區ID}（執行時換成遊戲的地區名），換不到就用只有區域的 name
const QZ = join(ADDONS, "Questie/Localization/Translations/Zones");
const ZONE_L = new Map(); // 英文區域名 → { deDE: …, … }
for (const f of readdirSync(QZ)) for (const m of readFileSync(join(QZ, f), "utf8").matchAll(/\["([^"]+)"\]\s*=\s*\{([^}]*)\}/g)) {
  if (ZONE_L.has(m[1])) continue;
  // true＝和英文同名；(Expansions:IsEra() and "舊名") or "新名"（舊寫法 Expansions.Current == Expansions.Era）取舊版（永恆是經典版）
  ZONE_L.set(m[1], Object.fromEntries([...m[2].matchAll(/\["(\w{4})"\]\s*=\s*(?:"([^"]*)"|true|\(Expansions(?:\.Current == Expansions\.Era|:IsEra\(\)) and (?:"([^"]*)"|true)\))/g)].map((x) => [x[1], x[2] ?? x[3] ?? m[1]])));
}
const AREA_ID = new Map(); // 英文地區名 → [{ id, parent }]（QuestieDB 的註解）
const AREA_NAMES = new Map(); // ID → 註解裡出現過的名字；兩個檔名字不同的 ID（永恆改用過的）不用
for (const f of ["subZoneToParentZone.lua", "areaIdToUiMapId.lua"]) {
  for (const m of readFileSync(join(ZONES, f), "utf8").matchAll(/\[(\d+)\]\s*=\s*\d+,\s*--\s*(.+?)\s*->\s*(.+?)\s*$/gm)) {
    AREA_NAMES.set(+m[1], (AREA_NAMES.get(+m[1]) || new Set()).add(m[2]));
    if (!AREA_ID.has(m[2])) AREA_ID.set(m[2], []);
    AREA_ID.get(m[2]).push({ id: +m[1], parent: m[3] });
  }
}
for (const [name, list] of AREA_ID) {
  const ok = list.filter((x) => AREA_NAMES.get(x.id).size === 1);
  if (ok.length) AREA_ID.set(name, ok); else AREA_ID.delete(name);
}
const AREA_ALIAS = { "Sen'jin": "Sen'jin Village", Crossroads: "The Crossroads", "Shimmering Flats": "The Shimmering Flats", Revantusk: "Revantusk Village" };
// 站名裡 Questie 與地區表都沒有的字（副本分區、短訪／回訪）
const PLACE_WORDS = {
  zhCN: { "short visit": "短访", return: "回访", "Sandfury camp": "沙怒营地", "Temple of Arkkoroc": "阿克科兰神殿", South: "南段", Graveyard: "墓地", Library: "图书馆", Armory: "武器库", Cathedral: "大教堂", Live: "血色区", Undead: "亡灵区", East: "东", West: "西", North: "北" },
  deDE: { "short visit": "kurzer Besuch", return: "Rückkehr", "Sandfury camp": "Lager der Sandwüter", "Temple of Arkkoroc": "Tempel von Arkkoroc", South: "Süden", Graveyard: "Friedhof", Library: "Bibliothek", Armory: "Waffenkammer", Cathedral: "Kathedrale", Live: "Lebende", Undead: "Untote", East: "Ost", West: "West", North: "Nord" },
  frFR: { "short visit": "courte visite", return: "retour", "Sandfury camp": "camp Furie-des-Sables", "Temple of Arkkoroc": "temple d'Arkkoroc", South: "sud", Graveyard: "Cimetière", Library: "Bibliothèque", Armory: "Armurerie", Cathedral: "Cathédrale", Live: "Vivants", Undead: "Morts-vivants", East: "Est", West: "Ouest", North: "Nord" },
  esES: { "short visit": "visita corta", return: "regreso", "Sandfury camp": "campamento Furiarena", "Temple of Arkkoroc": "Templo de Arkkoroc", South: "sur", Graveyard: "Cementerio", Library: "Biblioteca", Armory: "Armería", Cathedral: "Catedral", Live: "Vivos", Undead: "No-muertos", East: "Este", West: "Oeste", North: "Norte" },
  ptBR: { "short visit": "visita curta", return: "retorno", "Sandfury camp": "acampamento Fúria-da-areia", "Temple of Arkkoroc": "Templo de Arkkoroc", South: "sul", Graveyard: "Cemitério", Library: "Biblioteca", Armory: "Arsenal", Cathedral: "Catedral", Live: "Vivos", Undead: "Mortos-vivos", East: "Leste", West: "Oeste", North: "Norte" },
  ruRU: { "short visit": "коротко", return: "возвращение", "Sandfury camp": "лагерь племени Песчаной Бури", "Temple of Arkkoroc": "Храм Арккорока", South: "юг", Graveyard: "Кладбище", Library: "Библиотека", Armory: "Оружейная", Cathedral: "Собор", Live: "Живые", Undead: "Нежить", East: "Восток", West: "Запад", North: "Север" },
  koKR: { "short visit": "짧은 방문", return: "재방문", "Sandfury camp": "모래폭풍 야영지", "Temple of Arkkoroc": "아르코록 사원", South: "남부", Graveyard: "묘지", Library: "도서관", Armory: "무기고", Cathedral: "대성당", Live: "생존자 구역", Undead: "언데드 구역", East: "동쪽", West: "서쪽", North: "북쪽" },
};
PLACE_WORDS.esMX = PLACE_WORDS.esES;
// 翻譯列不用：審稿標記拿掉；有 ⁇／�（亂碼）的整列不用；字型顯示不了的字（中文介面的韓文、韓文介面的漢字、其他介面的中日韓字）整列不用
// 非中文語系：全形標點先換半形再檢查
const HALF = { "（": " (", "）": ")", "：": ": ", "，": ", ", "、": ", ", "；": "; ", "。": ". ", "／": "/", "｜": " | ", "「": "\"", "」": "\"", "　": " ", "！": "!", "？": "?" };
const badScript = { zhCN: /[가-힯ᄀ-ᇿ]/, koKR: /[぀-ヿ㐀-鿿＀-￯]/ };
const NOT_LATIN = /[぀-ヿ㐀-鿿가-힯＀-￯]/;
const NAME_LOC = { zhCN: "zhCN", deDE: "deDE", frFR: "frFR", esES: "esES", esMX: "esMX", ruRU: "ruRU", koKR: "koKR", ptBR: "ptBR" };
const locCov = [];
for (const loc of Object.keys(NAME_LOC)) {
  const F = FIX[loc], W = PLACE_WORDS[loc], zh = loc === "zhCN", bad = badScript[loc] || NOT_LATIN;
  const c = { text: 0, textLoc: 0, textEn: 0, names: 0, namesLoc: 0, namesEn: new Set(), qn: 0, qnLoc: 0, qd: 0, qdLoc: 0, rejected: { mark: 0, garbled: 0, script: 0 }, tags: 0, tagsEn: 0 };
  // 說明文字
  const AT = new Map(), ANY = new Map();
  for (const line of txLines(loc)) {
    const f = line.split("｜");
    if (f.length < 4 || !/\.md:\d+$/.test(f[0])) continue;
    const k = txKey(f.slice(2, -1).join("｜"));
    let v = f[f.length - 1];
    if (/【[^】]*】/.test(v)) c.rejected.mark++;
    v = v.replace(/【[^】]*】/g, "");
    if (!zh) v = v.replace(/[（）：，、；。／｜「」　！？]/g, (ch) => HALF[ch]);
    v = v.replace(/\s+/g, " ").replace(/\s+([),.;!?])/g, "$1").trim();
    if (!k || !v) continue;
    if (/[⁇�]/.test(v)) { c.rejected.garbled++; continue; }
    if (bad.test(v)) { c.rejected.script++; continue; }
    AT.set(f[0] + "|" + k, v);
    if (!ANY.has(k)) ANY.set(k, v);
  }
  // 名稱
  // esMX 查不到的名字先用 esES（兩邊大多相同），再退英文
  const NM = new Map();
  for (const nl of loc === "esMX" ? ["esMX", "esES"] : [loc]) {
    let sec = "";
    for (const line of readFileSync(join(ROOT, "tools", `names-${nl}.md`), "utf8").split(/\r?\n/)) {
      if (line.startsWith("## ")) sec = line.trim();
      if (sec !== "## 已查到" || !line.startsWith("| ") || line.startsWith("| 類型")) continue;
      const cells = line.split("|").slice(1, -1).map((x) => x.trim());
      // 英文名在路線資料裡已去掉引號（cleanName），對照表的兩邊也一樣去掉
      if (cells.length === 5 && cells[2] && cells[3] && !NM.has(cleanName(cells[2]))) NM.set(cleanName(cells[2]), cleanName(cells[3]));
    }
  }
  const fromDb = (en) => { for (const type of ["Npc", "Object", "Item"]) { const id = db.idByEn(type, en); const v = id !== undefined && db.l10nName(type, id, loc); if (v) return cleanName(v); } };
  const N = (en) => {
    if (!en) return en;
    if (en === "Quest object") return F.qobj;
    c.names++;
    const one = (x) => NM.get(x) ?? fromDb(x);
    const v = one(en) ?? (en.includes("/") && en.split("/").map(one).every(Boolean) ? en.split("/").map(one).join("/") : undefined); // 「A/B」兩個名字
    if (v) { c.namesLoc++; return v; }
    c.namesEn.add(en);
    return en;
  };
  const qnL = (id) => { const v = db.l10nName("Quest", id, loc); return v || questEn(id); };
  const zoneL = (en) => { const z = ZONE_L.get(en); return z && typeof z[loc] === "string" ? z[loc] : undefined; };
  // 站名：{ name（不靠執行時查表的版本）, nameA（含 {a:ID}）, short, shortA }
  const stCache = new Map();
  const station = (s) => {
    if (stCache.has(s)) return stCache.get(s);
    const out = {};
    stCache.set(s, out);
    const en = STATION_EN[safeText(s.name)] || (s.dungeon ? s.en && safeText(s.en) : undefined);
    if (!en) return out;
    const [, body, qual] = en.match(/^(.*?)(?: \(([^)]*)\))?$/);
    const i = body.indexOf(": ");
    const zoneEn = i > 0 ? body.slice(0, i) : body, rest = i > 0 ? body.slice(i + 2) : "";
    const zone = zoneL(zoneEn) || W[zoneEn];
    if (!zone) {
      // 永恆新增的副本：Questie 沒有翻譯，用副本的地區 ID 在執行時查名字；查不到就用英文
      const area = [...DUNGEON_AREA].find(([id, d]) => d.name === en && [...(AREA_NAMES.get(id) || [en])].every((x) => x === en))?.[0] ?? AREA_ID.get(en)?.[0].id;
      if (s.dungeon) out.name = en;
      if (s.dungeon && area) out.nameA = `{a:${area}}`; else (c.stMiss ||= []).push(en);
      return out;
    }
    const q = qual && W[qual];
    const toks = rest ? rest.split(/ (&|to) /) : []; // 地點、分隔、地點…
    const places = [], seps = [];
    let fixedOnly = true;
    for (let t = 0; t < toks.length; t += 2) {
      if (t) seps.push(toks[t - 1]);
      const p = toks[t];
      const v = zoneL(p) || W[p];
      if (v) { places.push(v); continue; }
      const a = (AREA_ID.get(AREA_ALIAS[p] || p) || []);
      const hit = a.find((x) => x.parent === zoneEn) || a[0];
      if (hit) { places.push(`{a:${hit.id}}`); fixedOnly = false; } else { c.stPartMiss = (c.stPartMiss || 0) + 1; }
    }
    const fmt = (ps) => (zh
      ? zone + (ps.length ? " " + ps.map((p, n) => (n ? (seps[n - 1] === "to" ? "至" : "／") : "") + p).join("") : "") + (q ? "（" + q + "）" : "")
      : zone + (ps.length ? ": " + ps.map((p, n) => (n ? (seps[n - 1] === "to" ? " – " : " & ") : "") + p).join("") : "") + (q ? " (" + q + ")" : ""));
    const full = fmt(places);
    if (fixedOnly) out.name = full;
    else { out.nameA = full; out.name = fmt(places.filter((p) => !p.startsWith("{a:"))); }
    if (places.length > 1 && !s.dungeon) {
      const sh = fmt(places.slice(0, 1)) + " +";
      if (sh.includes("{a:")) out.shortA = sh; else out.short = sh;
    }
    return out;
  };
  // 文字裡的任務 ID：只換英文版也換掉的那些（英文的判斷有前後文，避免把經驗值、金額當任務）
  const locIds = (v, enRaw, zhSrc) => {
    const hit = new Set();
    if (enRaw) enIds(enRaw, hit);
    return stationRefs(v, zhSrc, (n) => { const x = stations.find((s) => s.id.endsWith("-" + n)); const name = x && (station(x).name || "{s:" + x.id + "}"); return name && (zh ? "「" + name + "」" : name); })
      .replace(/(?<!\d)(\d{2})-(?:第\s*(\d+)\s*站|[^\s\d,.;:()（）]+ ?(\d+))/g, (all, p, a, b) => { const x = stations.find((s) => s.id === p + "-" + (a || b)); return (x && station(x).name) || all; })
      .replace(/(?<![\d.,])(\d{3,6})(?![\d%]|[.,]\d)/g, (all, num, at, whole) => {
        if (!hit.has(+num)) return all;
        const name = qnL(+num);
        return whole.includes(name) ? "" : name;
      })
      .replace(/(?<![\d.,])(\d{4})\s+(?=\D{0,8}?\d{1,2}(?:[.,]\d+)?\s*[,，])/g, (all, num) => (MAP_IDS.has(+num) || (+num >= 1400 && +num < 3000) ? "" : all))
      .replace(/[(（]\s*[)）]/g, "").replace(/\s+([),.;）])/g, "$1").replace(/ {2,}/g, " ").trim();
  };
  const TL = (where, zhText) => {
    const k = txKey(zhText);
    const v = k && (AT.get(where + "|" + k) ?? ANY.get(k));
    return v && locIds(v, TX_AT.get(where + "|" + k) ?? TX.get(k), k);
  };
  const T = (where, zhText) => {
    const k = txKey(zhText);
    if (!k) return undefined;
    if (!CJK.test(k.replace(/／/g, "/"))) return N(k.replace(/／/g, "/")); // 原文本來就是英文（目標怪名、物品名）
    c.text++;
    const v = TL(where, zhText);
    if (v) { c.textLoc++; return v; }
    (c.need ||= new Map()).set(k, where); // 這個語系沒翻到的（TX_NEED=檔案 時另存 檔案.<語系>）
    const e = tx(where, zhText);
    if (e) c.textEn++;
    return e;
  };
  const clean = (t) => t.replace(/<([^<>\/]+)\/([^<>\/]+)>/g, "$1/$2").replace(/<name>[,，]\s*|[,，] ?<name>/g, "").replace(/\$[Gg]\s*([^:;]*):[^;]*;/g, "$1").replace(/\$[Bb]/g, " ").replace(/\$[NnCcRr]/g, "").replace(/\$/g, "").replace(/[０-９]/g, (c) => String.fromCharCode(c.charCodeAt(0) - 0xfee0)).replace(/\s+/g, " ").trim();
  const genL = (q) => {
    const mk = q?.en?.mk;
    if (!mk) return undefined;
    const parts = [mk.kill.length && F.kill + [...new Set(mk.kill)].map(N).join(F.sep), mk.drop.length && F.loot + [...new Set(mk.drop)].slice(0, 3).map(N).join(F.sep), mk.objsEn.length && F.use + mk.objsEn.map(N).join(F.sep)].filter(Boolean);
    return parts.length ? parts.join(F.sent) : undefined;
  };
  const qd = (id) => {
    c.qd++;
    const d = db.l10nObj(id, loc).map(clean).filter(Boolean).join("\n");
    if (d && !d.includes("<name>")) { c.qdLoc++; return d; } // <name> 還在＝QuestieDB 把名字、職業甚至冠詞換掉了，還原不了：改用下面的備援
    const q = quests.get(id);
    return genL(q) || q?.en?.d || q?.en?.gen;
  };
  const itemL = (en) => { if (!en) return undefined; const id = db.idByEn("Item", en); return (id !== undefined && db.l10nName("Item", id, loc)) || en; };
  const routeL = emitRoute({
    loc, title: ` ${loc} `, T, N, F, cov: newCov(), left: { ...left }, leftAt: [], missNpc: [],
    station,
    node: (step) => {
      const en = NODE_EN[step.node];
      if (!en) return { node: T(step.where, step.node) };
      const z = zoneL(en);
      if (z) return { node: z };
      const a = AREA_ID.get(en);
      return a ? { nodeA: `{a:${a[0].id}}`, node: en } : { node: en }; // nodeA 在遊戲裡查不到地區名時，退回英文名（不會變成空白）
    },
    tag: (t, where) => { c.tags++; const v = TL(where, t) || F.tags?.[t]; if (v) return v; if (TAG_EN[t]) c.tagsEn++; return TAG_EN[t]; },
    hint: (q, id) => q && (q.en ? qd(id)?.split("\n")[0] : undefined),
    qn: (id) => { c.qn++; const v = db.l10nName("Quest", id, loc); if (v) { c.qnLoc++; return v; } return questEn(id); },
    qName: (id, e) => db.l10nName("Quest", id, loc) || e.n,
    qd: (id) => qd(id),
    item: itemL, itemId: (id) => db.l10nName("Item", id, loc) || db.itemEn(id),
    endDot: zh ? (x) => (/[。！？）.!?)]$/.test(x) ? x : x + "。") : (x) => (/[.!?)]$/.test(x) ? x : x + "."),
    split: zh
      ? (t) => t.split(/(?<=[。；！？])|(?<=[.;!?])\s+(?=[A-Z0-9"'(])/).map((x) => x.replace(/[.;。；]$/, "").trim()).filter(Boolean)
      : (t) => t.split(/(?<=[.;!?])\s+(?=[\p{Lu}\p{Lo}\d"'(«„¿¡])/u).map((x) => x.replace(/[.;]$/, "").trim()).filter(Boolean),
    route: (text) => text.replace(/\s*[(（][^\d()（）]{0,14}\d+(?:\s*[–\-~～]\s*\d+)?\s*[)）]/g, ""),
  });
  writeFileSync(join(dirname(OUT), `${LUA_PREFIX}_${loc}.lua`), routeL);
  locCov.push([loc, c]);
}
for (const [loc, c] of locCov) {
  if (process.env.TX_NEED) writeFileSync(`${process.env.TX_NEED}.${loc}`, [...(c.need || [])].map(([k, w]) => `${w}｜說明｜${k}｜`).join("\n"));
  console.log(`${loc}：名稱 ${c.namesLoc}/${c.names}（英文 ${c.namesEn.size} 種）、說明文字 ${c.textLoc}/${c.text}（用英文 ${c.textEn}）、任務名 ${c.qnLoc}/${c.qn}、任務目標文字 ${c.qdLoc}/${c.qd}、標籤用英文 ${c.tagsEn}/${c.tags}、站名缺 ${(c.stMiss || []).join("、") || 0}／地點缺 ${c.stPartMiss || 0}；翻譯列不用：亂碼 ${c.rejected.garbled}、字型顯示不了 ${c.rejected.script}（另有審稿標記拿掉 ${c.rejected.mark}）`);
  if (process.env.LOC_REPORT) writeFileSync(join(process.env.LOC_REPORT, `names-en-${loc}.txt`), [...c.namesEn].sort().join("\n"));
}
for (const r of raceUnknown) warn("種族條件", `「${r}」不是已知種族，非繁中客戶端比不到（請加進 build.mjs 的 RACE）`);
const report = `# 建置報告（資料版本 ${version}）\n\n來源：${files.join("、")}\n站數：${stations.length}　任務數：${quests.size}\n\n## 需要處理（${issues.hard.length}）\n\n${issues.hard.join("\n") || "無"}\n\n## 提醒（${issues.warn.length}）\n\n${issues.warn.join("\n") || "無"}\n\n## 副本前置鏈\n\n${chainReport.join("\n") || "無"}\n\n## 裸任務 ID 換成任務名（前 40 例）\n\n${idSamples.map((x) => "- " + x).join("\n") || "無"}\n\n## 名稱不一致（${nameIssues.length}）\n\n${nameIssues.join("\n") || "無"}\n\n## 順序錯誤（已自動調整 ${orderFixes.length}）\n\n${orderFixes.join("\n") || "無"}\n\n## 綁爐石步驟（${bindReport.length}）\n\n${bindReport.join("\n") || "無"}\n\n## 前置正規化（${exFixed.length}）\n\n${exFixed.join("\n") || "無"}\n\n## 互斥清單拿掉導引（${exLead.length}）\n\n${exLead.join("\n") || "無"}\n\n## 可跳過的前置改成必做（${leadReq.length}）\n\n${leadReq.join("\n") || "無"}\n\n## 職業任務段落搬到同地圖（${classMoved.length}）\n\n${classMoved.join("\n") || "無"}\n\n## 職業任務段落和前一步不同地圖（${classMap.length}，同洲；跨洲的在提醒）\n\n${classMap.join("\n") || "無"}\n\n## 職業任務回到路線（${backAdded.length}）\n\n${backAdded.join("\n") || "無"}\n\n## 主線自己有交通、不加回到路線（${backDropped.length}）\n\n${backDropped.join("\n") || "無"}\n`;
writeFileSync(REPORT, report);
console.log(`順序錯誤已調整 ${orderFixes.length}、純對話任務的「做」拿掉 ${talkOnly}`);
console.log(`路線外判定 ${offroute.size}、路線外前置 ${feeds.size}、保留物品 ${keep.size}、補給 ${stations.reduce((n, x) => n + (x.supply?.length || 0), 0)}、危險 ${stations.reduce((n, x) => n + (x.danger?.length || 0), 0)}`);
console.log(`站 ${stations.length}、任務 ${quests.size}、需要處理 ${issues.hard.length}、提醒 ${issues.warn.length}、名稱不一致 ${nameIssues.length}`);
console.log("裸任務 ID 換成任務名：" + ([...idStats.entries()].map(([k, v]) => k + " " + v).join("、") || "0"));
console.log(`→ ${OUT}\n→ ${REPORT}`);
process.exitCode = issues.hard.length ? 1 : 0;
