// 離線建置：route/*.md → addon/ShengLeveling/Data/Route.lua + tools/unresolved.md
// 用法：node tools/build.mjs
// 缺任務 ID／座標時查 QuestieDB（zhTW、zhCN、enUS 名稱）。有「找不到／多個候選」時以結束碼 1 結束（輸出仍會寫出）。
import { readFileSync, writeFileSync, readdirSync } from "node:fs";
import { createHash } from "node:crypto";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { openQuestieDB, clusterCenter } from "./questiedb.mjs";

const ROOT = join(dirname(fileURLToPath(import.meta.url)), "..");
// 任務目標座標（tools/objective-coords.md，Codex 查的 Wowhead 永恆版／QuestieDB 點位）：補到「做」步驟的 more
const OBJ = new Map();
let objAdded = 0;
for (const line of readFileSync(join(ROOT, "tools", "objective-coords.md"), "utf8").split(/\r?\n/)) {
  const f = line.split("｜");
  if (f.length < 5 || !/^\d+$/.test(f[0]) || !/^\d+$/.test(f[3])) continue;
  const pts = f[4].split(";").map((p) => p.split(",").map(Number)).filter((p) => p.length === 2 && p.every(Number.isFinite)).map(([x, y]) => ({ map: +f[3], x, y }));
  OBJ.set(+f[0], [...(OBJ.get(+f[0]) || []), ...pts]);
}
const ROUTE = process.env.ROUTE_DIR || join(ROOT, "route"); // 測試時可指到別的資料夾
const OUT = process.env.OUT_LUA || join(ROOT, "addon", "ShengLeveling", "Data", "Route.lua");
const REPORT = process.env.OUT_REPORT || join(ROOT, "tools", "unresolved.md");

const HORDE = 8589934770n; // QuestieDB 的部落種族遮罩（含永恆新種族位元）
const CLASS = { 戰士: "WARRIOR", 獵人: "HUNTER", 薩滿: "SHAMAN", 薩滿祭司: "SHAMAN", 法師: "MAGE", 術士: "WARLOCK", 盜賊: "ROGUE", 德魯伊: "DRUID", 牧師: "PRIEST", 聖騎士: "PALADIN" };
const RACE = { 獸人: "Orc", 食人妖: "Troll", 牛頭人: "Tauren", 不死族: "Scourge", 亡靈: "Scourge", 被遺忘者: "Scourge", 血精靈: "BloodElf" };
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
const NODE_EN = { 蕨牆村: "Brackenwall Village", 斯通納德: "Stonard", 卡加斯: "Kargath", 莫沙徹營地: "Camp Mojache", 瑟銀哨塔: "Thorium Point", 惡齒村: "Revantusk Village", 瓦羅莫克: "Valormok",
  馬紹爾營地: "Marshal's Refuge", 烈焰峰: "Flame Crest", 聖光之願禮拜堂: "Light's Hope Chapel", 血毒崗哨: "Bloodvenom Post", 永望鎮: "Everlook", 月光林地: "Moonglade", 塞納里奧城堡: "Cenarion Hold" };
// 步驟標籤（第 3 行）：整段對得上才翻，對不上的英文介面不顯示
const TAG_EN = { 可跳過: "Optional", 需遊戲實測: "Unverified", 有隊伍再做: "Group", 怪多: "Crowded", 副本前置鏈: "Dungeon prereq", 精英: "Elite", 護送: "Escort", 組隊: "Group",
  副本: "Dungeon", 組隊護送: "Group escort", 有隊伍才下: "Group only", 有隊伍或能單刷: "Group or solo", 有掉落才做: "If it drops", 掉落時才做: "If it drops", 掉落觸發: "Drop starts it",
  巡邏掉落觸發: "Drop starts it", 掉落才接: "If it drops", 之後順路: "Later, on the way", 路過才做: "If passing by", 有餘力再做: "If time allows", 有遇到才做: "If you see it", 已遇到才做: "If you see it",
  能打高階怪再做: "Hard", 低等怪補缺口: "Fills an XP gap", 日後順路或有隊伍: "Later or with a group", 見到獵物才接: "If you see it", 材料齊才做: "When you have the items" };
const tagEn = (tag) => { const out = (tag || "").split(/\s*・\s*/).map((t) => TAG_EN[t.trim()]).filter(Boolean); return out.length ? [...new Set(out)].join(", ") : undefined; };
const enText = (t) => String(t || "").replace(/\$[Bb]/g, " ").replace(/\$[Nn]/g, "you").replace(/\$[CcRr]/g, "adventurer").replace(/\s+/g, " ").trim();
const VERB = { 接: "accept", 做: "do", 交: "turnin", 到: "goto", 鳥: "fp", 爐: "hearth", 飛: "fly", 船: "boat", 練: "level", 註: "note", 交通: "travel" };
// 行尾標籤：這些不顯示；其餘（可跳過、有隊伍再做…）顯示在步驟第 3 行
const HIDDEN_TAG = /^(QuestieDB|補充|所在[：:]|影片|有前置|僅|非|說明|\d+\s*級起|接取等級|建議等級|可共享|不可共享|共享|前置[：:]|★|掉率|位置|副本座標|順序|部落可接)/;
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
// 任務經驗（QuestieDB 的 QuestXP 表：[id] = {等級, 經驗}）
const XP = new Map();
for (const m of readFileSync("C:/Program Files (x86)/World of Warcraft/_forever_/Interface/AddOns/QuestieDB/support/Forever/QuestXP/xpDB-classic.lua", "utf8").matchAll(/\[(\d+)\] = \{(\d+), (\d+)\}/g)) XP.set(+m[1], +m[3]);
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
  return mobs.map((m, k) => m && m.kind !== "object"
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
      if (lv && c) (st.grind ||= []).push({ mob: f[0], lv: [+lv[1], +lv[2]], map: c.map || st.map, x: c.x, y: c.y, note: f[3], where });
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
      else if (key !== "限定" && key !== "二選一") st.tips.push({ k: key, raw: v, text: v.replace(/【[^】]*】/g, "").trim(), where });
      return;
    }
    const sm = line.match(/^\s*(?:\d+\s*[.、)]\s*|[-*]\s*)?(交通|接|做|交|到|鳥|爐|飛|船|練|註)｜(.*)$/);
    if (!sm) return;
    const tags = [...sm[2].matchAll(/【([^】]*)】/g)].map((m) => m[1]);
    const body = sm[2].replace(/【[^】]*】/g, "").trim();
    const keep = /★/.test(body);
    const f = body.replace(/★/g, "").split("｜").map((s) => s.trim());
    const step = { verb: sm[1], t: VERB[sm[1]], where, when: parseWhen(tags), keep, video: tags.includes("影片") || undefined,
      tag: tags.filter((t) => !HIDDEN_TAG.test(t)).join("・") || undefined, opt: tags.includes("可跳過") || undefined, anyRace: tags.includes("部落可接") || undefined,
      desc: [...tags.filter((t) => /^說明[：:]/.test(t)).map((t) => t.replace(/^說明[：:]\s*/, "")),
        ...tags.filter((t) => /^(位置|順序)[：:]/.test(t)).map((t) => t.replace(/^(位置|順序)[：:]\s*/, "$1："))].join("；") || undefined,
      spot: (tags.find((t) => /^所在[：:]/.test(t)) || "").replace(/^所在[：:]s*/, "") || undefined, // 副本內交的人在哪（副本中目標做完時顯示）
      star: starOf(tags), rate: (tags.map((t) => t.match(/^掉率\s*(\d+(?:\.\d+)?)\s*%/)).find(Boolean) || [])[1],
      pre: tags.map((t) => t.match(/^前置[：:].*?(\d{2,6})\s*$/)).filter(Boolean).map((m) => +m[1]) };
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
      const base = { id: p, zh: questName(pq), en: pq.en, ph: "pre", tag: "副本前置鏈", chainOf: qid, where: d.where, when };
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
  for (const p of [...(st.grind || []), ...(st.supply || []), ...(st.danger || [])]) p.map ||= st.map; // 解析當下站的地圖可能還沒定
  for (const step of st.steps) {
    if (!["accept", "do", "turnin"].includes(step.t)) {
      if (step.coord) step.coord.map ||= st.map;
      continue;
    }
    for (const p of step.more || []) p.map ||= st.map;
    // 目標座標補充：同地圖、跟既有點距離 0.8 以上才加；太多就平均取樣到 40 個
    if (step.t === "do" && OBJ.has(step.id)) {
      const have = [step.coord, ...(step.more || [])].filter(Boolean);
      let add = OBJ.get(step.id).filter((p) => !have.some((h) => (h.map || st.map) === p.map && Math.hypot(h.x - p.x, h.y - p.y) < 0.8));
      if (add.length > 40) add = Array.from({ length: 40 }, (_, i) => add[Math.floor((i * add.length) / 40)]);
      if (add.length) { step.more = [...(step.more || []), ...add]; objAdded++; }
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
    const anyRace = step.anyRace; delete step.anyRace;
    used.add(`${step.t}:${id}`);
    if (step.t === "accept") { if (step.zh) lastByName.set(db.norm(step.zh), id); if (step.en) lastByName.set(db.norm(step.en), id); }
    const q = db.quest(id);
    if (!quests.has(id)) {
      quests.set(id, q
        ? { races: q.races && BigInt(q.races) !== HORDE ? q.races : undefined, xp: XP.get(id), mob: mobsOf(q), tgo: targetsOf(q), objs: (() => { const o = [...new Set(db.questMobs(q.id).filter((m) => m && m.kind === "object").flatMap((m) => m.objects))]; return o.length ? o : undefined; })(),
            items: [...new Set([q.sourceItem, ...q.requiredSourceItems].filter((x) => x > 0))].length ? [...new Set([q.sourceItem, ...q.requiredSourceItems].filter((x) => x > 0))] : undefined,
            d: q.obj.filter(Boolean).join("\n") || undefined,
            n: QUEST_NAME[id] || step.zh || q.zhTW || step.en || q.en, zt: q.zhTW && q.zhTW !== (QUEST_NAME[id] || step.zh || q.zhTW) ? q.zhTW : undefined, lvl: q.level, min: q.reqLevel, pg: q.preGroup, ps: q.preSingle, ex: q.exclusiveTo, next: q.next, st: st.id }
        : { n: QUEST_NAME[id] || step.zh || step.en, st: st.id });
    }
    if (q && !quests.get(id).en) {
      const mobs = db.questMobs(id);
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
    const giver = namedNpc || npcs[0] || objIds.map((o) => db.object(o)).find(Boolean);
    if (!step.npc && giver) step.npc = npcs.length && giver.zhTW ? gameName(giver.zhTW) : giver.zhTW || giver.en;
    // 英文：給任務的 NPC／物件英文名；從物品開始的任務用物品英文名（物件、物品不當選取目標）
    if (giver) { step.npcEn = mdEnt(id, step.npc) || cleanName(giver.en); if (step.npcEn !== cleanName(giver.en)) enDiff.npc++; if (!npcs.length) step.npcObj = true; }
    else if (step.t === "accept" && q.startItems.length) { step.npcEn = mdEnt(id, step.npc) || db.itemEn(q.startItems[0]); step.npcObj = true; }
    if (npcs.length && giver) step.tgtEn = mdEnt(id, step.tgt) || cleanName(giver.en);
    const isNpc = npcs.length > 0;
    if (isNpc && giver) {
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
    else if (step.t !== "do") warn(at, "缺座標（QuestieDB 也沒有）");
  }
  const noCoord = st.steps.filter((s) => s.t === "do" && !s.coord).length;
  if (noCoord) warn(`${st.id} ${st.name}`, `${noCoord} 個「做」步驟沒有座標（不會出現箭頭）`);
  if (!st.map) hard(`${st.id} ${st.name}`, "沒有地圖 ID");
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

// 遊戲 zhTW 字型缺的字：・（U+30FB）→ 空白，彎引號 → ASCII
const idStats = new Map(); // 檔案 → 換掉的裸 ID 數
let idFile = "";
const MAP_IDS = new Set(Object.values(ZONE_MAP).concat([1458, 1454, 1456, 2521, 2548]));
const CLASS_RE = new RegExp("^(" + Object.keys(CLASS).join("|") + ")");
const RACE_ZH = { ...RACE, 天裔: "天裔" };
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
const replaceIds = (text) => replaceStations(text).replace(/(?<![\d.\w])(\d{3,6})(?![\d.,]|\s*[個隻只根張份塊件頭名條把顆片枚級%]|\s+\d+[.,]\d)/g, (all, num, at, whole) => {
  const id = +num;
  if (MAP_IDS.has(id)) return all;
  const q = db.quest(id);
  if (!q) return all;
  const name = questName(q);
  idStats.set(idFile, (idStats.get(idFile) || 0) + 1);
  const before = whole.slice(0, at).replace(/[\s（(「]+$/, "");
  const after = whole.slice(at + num.length).replace(/^[\s（(「]+/, "");
  const sample = idFile + "：…" + whole.slice(Math.max(0, at - 12), at + num.length + 4) + "… → " + name;
  if (idSamples.length < 40 && !idSamples.includes(sample)) idSamples.push(sample);
  return [name, q.zhTW].some((n) => n && (before.endsWith(n) || after.startsWith(n))) ? "" : name; // 名字已寫在 ID 前或後 → 只拿掉 ID
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
  star: s.star, t: s.t, q: s.t === "need" || s.t === "accept" || s.t === "do" || s.t === "turnin" ? s.id : undefined, ph: s.ph, pickLv: s.pickLv, recLv: s.recLv, share: s.share, preText: s.preText, opt: s.opt, desc: s.desc, spot: s.spot, tag: s.tag, npc: s.npc, tgt: s.tgt, hint: s.hint, text: s.text, node: s.node, bind: s.bind, to: s.to, from: s.from, lv: s.lv,
  map: s.coord?.map, x: s.coord?.x, y: s.coord?.y, more: s.more?.length ? s.more.map((p) => [p.map, p.x, p.y]) : undefined, when: stepWhen(s.when, st.when), video: s.video,
});
let out = `-- 由 tools/build.mjs 產生，勿手改。來源：route/*.md\nlocal _, MG = ...\nMG.Route = {\n  built = "@@BUILT@@",\n  stations = {\n`;
for (const s of stations) {
  idFile = s.file;
  refPrefix = s.dungeon ? s.after.split("-")[0] : s.id.split("-")[0];
  const start = s.when?.race && s.lv[0] <= 12 ? s.when.race.join("/") : undefined;
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
  for (const step of s.steps) if (step.t !== "accept" && step.t !== "do" && step.t !== "turnin" || step.id) out += `        ${lua(stepOut(step, s))},\n`;
  out += `      } },\n`;
}
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
    offroute.set(+m[1], { v: f[3], why: f[4] || undefined });
    offAt.set(+m[1], `${file}:${li + 1}`);
  });
}
// 路線外但是路線任務的前置 → 值得做（接後續）
const feeds = new Map();
for (const [id, q] of quests) for (const p of [...(q.pg || []), ...(q.ps || [])]) if (!quests.has(p) && !feeds.has(p)) feeds.set(p, id);
// ── 07 訓練師：職業｜等級｜地點｜NPC｜座標｜順路時機 ──
// 只讀「建議回訪等級」那一節（其他節是主城訓練師一覽、專項、武器技能，當參考）；等級欄取第一個數字（「4、6」「10–12」→ 4、10）
const trainers = [];
for (const file of files.filter((f) => /^07-/.test(f))) {
  let inStops = false;
  readFileSync(join(ROUTE, file), "utf8").split(/\r?\n/).forEach((line, li) => {
    if (/^##\s/.test(line)) inStops = /建議回訪等級/.test(line);
    if (!inStops) return;
    const m = line.match(/^\s*-\s*(.+?)｜\s*(\d+)[^｜]*｜(.*)$/);
    if (!m || !CLASS[m[1].trim()]) return;
    const where = `${file}:${li + 1}`;
    const [place, rawNpc, coordText, rawWhen] = m[3].split("｜").map((x) => x.trim());
    const npc = (rawNpc || "").replace(/\s*[（(][^（）()]*[）)]\s*$/, "").trim(); // 去掉英文名，才對得上遊戲裡的 NPC 名
    const when = (rawWhen || "").replace(/【[^】]*】/g, "");
    const lv = +m[2];
    const c = parseCoord(coordText);
    const map = c?.map || ZONE_MAP[(place || "").split(/[ ・·]/)[0]];
    // 候選站（依序，遊戲裡取第一個本角色有的站；起點站只有該種族有）：
    // 寫了「0X-第N站」就用它；站名任一段出現在順路時機或地點文字裡的（等級接近的優先）；同地圖且等級涵蓋；等級涵蓋
    const ref = (when || "").match(/(\d+)\s*-\s*第(\d+)站/);
    const text = (when || "") + " " + (place || "");
    const near = (a, b) => Math.abs(a.lv[0] - lv) - Math.abs(b.lv[0] - lv);
    const main = stations.filter((x) => !x.dungeon);
    // 有明確對到（站號或站名）就只用這些：起點區的訓練師只會出現在該起點站，不會借用到別族的起點
    const named = [
      ...(ref ? main.filter((x) => x.id === `${ref[1]}-${ref[2]}`) : []),
      ...main.filter((x) => x.name.split(/[・·與／\s]/).some((t) => t.length >= 2 && text.includes(t))).sort(near),
    ];
    const cands = named.length ? named : [
      ...main.filter((x) => x.map === map && x.lv[0] <= lv && lv <= x.lv[1]),
      ...main.filter((x) => x.lv[0] <= lv && lv <= x.lv[1]),
    ];
    const ids = [...new Set(cands.map((x) => x.id))].slice(0, 12);
    if (!npc || !ids.length) return warn(where, "訓練師格式看不懂或對不到站：" + line.slice(0, 50));
    if (!c) warn(where, `訓練師 ${npc} 沒有座標`);
    trainers.push({ c: CLASS[m[1].trim()], lv, place, npc, map: map || main.find((x) => x.id === ids[0])?.map, x: c?.x, y: c?.y, st: ids });
  });
}
// ── 08 保留物品：物品名｜物品ID｜何時拿到｜何時用到（用到的任務 ID 寫在文字裡就會在任務交掉後不再提示） ──
const keep = new Map();
const keepAt = new Map(); // 物品 ID → 出處（英文用途用）
for (const file of files.filter((f) => /^08-/.test(f))) {
  readFileSync(join(ROUTE, file), "utf8").split(/\r?\n/).forEach((line, li) => {
    const f = line.replace(/^\s*-\s*/, "").split("｜").map((x) => x.trim());
    if (f.length < 4 || !/^\d+$/.test(f[1])) return;
    const q = [...f[3].matchAll(/\d{2,6}/g)].map((m) => +m[0]).find((n) => quests.has(n));
    keep.set(+f[1], { n: f[0], use: f[3].replace(/【[^】]*】/g, "").trim(), q });
    keepAt.set(+f[1], `${file}:${li + 1}`);
  });
}
const luaMap = (m) => (m.size ? "{" + [...m].map(([k, v]) => `[${k}]=${lua(v)}`).join(", ") + "}" : "nil"); // 數字鍵（任務 ID）
out += `  },\n  offroute = ${luaMap(offroute)},\n  feeds = ${luaMap(feeds)},\n  trainers = ${lua(trainers.length ? trainers : undefined)},\n  keep = ${luaMap(keep)},\n`;
out += `  quests = {\n`;
for (const [id, q] of [...quests.entries()].sort((a, b) => a[0] - b[0])) {
  const { st, next, en, ...rest } = q;
  out += `    [${id}] = ${lua(rest)},\n`;
}
out += `  },\n}\n`;
// 台服用詞（tools/用詞.md）：只改說明文字欄位與句子陣列，任務名／NPC／怪名保持和遊戲一致
const wording = readFileSync(join(ROOT, "tools", "用詞.md"), "utf8").split(/\r?\n/)
  .map((l) => l.match(/^-\s*([^｜]+)｜(.*)$/)).filter(Boolean).map((m) => [m[1].trim(), m[2].trim()]);
const reword = (text) => wording.reduce((t, [from, to]) => t.split(from).join(to), text);
out = out
  .replace(/\b(d|desc|spot|hint|pickup|text|why|use|note|entrance)="(?:[^"\\]|\\.)*"/g, reword)
  .replace(/\b(s|pickupS)=\{(?:[^{}"]|"(?:[^"\\]|\\.)*")*\}/g, reword);
// 資料版本＝內容雜湊（不放時間，內容沒變就不會產生差異）
const version = createHash("sha1").update(out).digest("hex").slice(0, 8);
out = out.replace("@@BUILT@@", version);
writeFileSync(OUT, out);

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
const txKey = (s) => String(s || "").replace(/【[^】]*】/g, "").replace(/\s+/g, " ").trim();
const CJK = /[　-〿぀-ヿ㐀-鿿가-힯＀-￯]/;
const TX_ROWS = [], TX_AT = new Map(), TX = new Map(), txUsed = new Set();
for (const line of readFileSync(join(ROOT, "tools", "route-text-enUS.md"), "utf8").split(/\r?\n/)) {
  const f = line.split("｜");
  if (f.length < 4 || !/\.md:\d+$/.test(f[0])) continue;
  const row = { at: f[0], type: f[1], zh: txKey(f.slice(2, -1).join("｜")), en: f[f.length - 1].trim() };
  TX_ROWS.push(row);
  if (!row.zh || !row.en || CJK.test(row.en)) continue;
  TX_AT.set(row.at + "|" + row.zh, row.en);
  if (!TX.has(row.zh)) TX.set(row.zh, row.en);
}
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
  if (!en) return undefined;
  txUsed.add(k);
  return enIds(en);
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
  const { loc, T, N, F, cov, left, leftAt, missNpc } = X;
  let en = `-- 由 tools/build.mjs 產生，勿手改。Route.lua 的${X.title}名稱與說明（站 ID→步驟序號、任務 ID）\n-- 包成函式：只有介面、客戶端用到的語系才建表（Engine.lua E.Localize），其餘載入後就丟掉\nlocal _, MG = ...\nMG.RouteL = MG.RouteL or {}\nMG.RouteL.${loc} = function() return {\n  stations = {\n`;
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
      cov.steps++;
      const e = {};
      const q = step.id && quests.get(step.id);
      if (step.t === "accept" || step.t === "turnin") {
        e.npc = N(step.npcEn || mdEnt(step.id, step.npc)); e.tgt = N(step.tgtEn || (step.tgt && mdEnt(step.id, step.tgt))); e.npcObj = step.npcObj || (/^(物件|物品)/.test(step.npc || "") || undefined);
        cov.npcNeed++; if (e.npc) cov.npc++; else missNpc.push(`${step.id} ${step.npc}`);
        if (step.tgt) { cov.tgtNeed++; if (e.tgt) cov.tgt++; }
      } else if (step.t === "do") {
        cov.hint++;
        e.hint = X.hint(q, step.id);
        if (!q?.en?.d && q?.en?.gen) cov.hintGen++;
        if (!e.hint) { cov.hint--; e.hint = F.complete; }
      } else if (step.t === "need") e.text = F.prereq + (X.qn(step.id) || F.quest + step.id);
      else if (step.t === "travel" && /^前往 .+ 入口$/.test(step.text || "")) e.text = F.entrance.replace("%s", () => name || F.dungeon);
      else if (step.t === "travel" || step.t === "goto" || step.t === "note") {
        const kind = step.t === "note" ? "note" : "travelText";
        cov.zhOnly[kind]++;
        e.text = step.text && T(step.where, step.text);
        if (!e.text) left[kind]++;
      }
      if (step.t === "fp") Object.assign(e, X.node(step));
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
    const grind = {}; (s.grind || []).forEach((g, i) => { const note = g.note && T(g.where, g.note); if (g.note && !note) left.grindNote++; grind[i + 1] = { mob: N(npcEn(g.mob)), note }; });
    const supply = {}; (s.supply || []).forEach((x, i) => { supply[i + 1] = { npc: x.npc && N(npcEn(x.npc)) }; });
    en += `    [${JSON.stringify(s.id)}] = ${plain({ name, nameA: nm.nameA, short: nm.short, shortA: nm.shortA, entrance, pickup, pickupS: pickup && enSents(s.pickupRaw, pickup, false, X.split), tips, danger, grind, supply, steps })},\n`;
  }
  en += `  },\n  quests = {\n`;
  for (const [id, q] of [...quests.entries()].sort((a, b) => a[0] - b[0])) {
    cov.quests++;
    const e = q.en || {};
    if (e.n) cov.qName++;
    if (e.d) cov.qObj++;
    let star;
    if (q.star) { const n = X.item(db.enByZh("Item", q.star[0])) || T("", q.star[0]); star = n ? [n, ...q.star.slice(1)] : undefined; }
    en += `    [${id}] = ${plain({ n: X.qName(id, e), d: X.qd(id, e), tgo: e.tgo && e.tgo.map((l) => l.map(N)), objs: e.objs && e.objs.map(N), star })},\n`;
  }
  en += `  },\n  trainers = ${plain(Object.fromEntries(trainers.map((t, i) => [i + 1, { npc: N(npcEn(t.npc)) }])))},\n`;
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
writeFileSync(join(dirname(OUT), "Route_enUS.lua"), routeEn);
const pct = (a, b) => (b ? Math.round((a / b) * 1000) / 10 : 100) + "%";
console.log(`英文：站名 ${cov.stName}/${cov.stations}（${pct(cov.stName, cov.stations)}）、接交 NPC ${cov.npc}/${cov.npcNeed}（${pct(cov.npc, cov.npcNeed)}）、選取目標 tgt ${cov.tgt}/${cov.tgtNeed}（${pct(cov.tgt, cov.tgtNeed)}）、做步驟提示 ${cov.hint}（其中湊句 ${cov.hintGen}）、任務名 ${cov.qName}/${cov.quests}、任務目標文字 ${cov.qObj}/${cov.quests}`);
console.log("說明文字英文（route-text-enUS.md，翻到／原本只有中文）：" + Object.entries(cov.zhOnly).map(([k, v]) => `${k} ${v - left[k]}/${v}`).join("、") + `；條件對不上改為不帶條件 ${cov.whenLost}`);
const txMiss = TX_ROWS.filter((r) => !txUsed.has(r.zh));
console.log(`翻譯列 ${TX_ROWS.length}，用到 ${TX_ROWS.length - txMiss.length}；英文含中日韓字（不用）${TX_ROWS.filter((r) => CJK.test(r.en)).length}；沒用到（依類型）：` + Object.entries(Object.groupBy(txMiss, (r) => r.type)).map(([k, v]) => k + " " + v.length).join("、"));
if (process.env.TX_MISS) writeFileSync(process.env.TX_MISS, leftAt.concat(txMiss.map((r) => `${r.at}｜${r.type}｜${r.zh}`)).join("\n"));
console.log("英文缺接交 NPC：" + missNpc.join("、"));
console.log(`english-names.md：任務 ${MD_QUEST.size}、實體 ${MD_ENT.size}、名稱 ${MD_NAME.size}；和 QuestieDB 英文不同：任務名 ${enDiff.quest}、接交 NPC ${enDiff.npc}、選取目標 ${enDiff.tgt}`);

// ── 其他語系：Data/Route_<locale>.lua，結構同 Route_enUS.lua，每一欄翻不到就用英文 ──
// 名稱：tools/names-<locale>.md（英文名 → 該語系，Codex 查的永恆客戶端名）＞ QuestieDB 該語系＞英文
// 說明文字：tools/route-text-<locale>.md（格式同 enUS）＞英文；任務名、任務目標文字：QuestieDB 該語系＞英文（遊戲內的任務名執行時另由 API 取）
// 站名：區域名用 Questie 的區域翻譯；城鎮寫成 {a:地區ID}（執行時換成遊戲的地區名），換不到就用只有區域的 name
const QZ = join(dirname(ZONES.replace(/\/$/, "")), "..", "..", "..", "Questie", "Localization", "Translations", "Zones");
const ZONE_L = new Map(); // 英文區域名 → { deDE: …, … }
for (const f of readdirSync(QZ)) for (const m of readFileSync(join(QZ, f), "utf8").matchAll(/\["([^"]+)"\]\s*=\s*\{([^}]*)\}/g)) {
  if (ZONE_L.has(m[1])) continue;
  // true＝和英文同名；(Expansions.Current == Expansions.Era and "舊名") or "新名" 取舊版（永恆是經典版）
  ZONE_L.set(m[1], Object.fromEntries([...m[2].matchAll(/\["(\w{4})"\]\s*=\s*(?:"([^"]*)"|true|\(Expansions\.Current == Expansions\.Era and (?:"([^"]*)"|true)\))/g)].map((x) => [x[1], x[2] ?? x[3] ?? m[1]])));
}
const AREA_ID = new Map(); // 英文地區名 → [{ id, parent }]（QuestieDB 的註解）
const AREA_NAMES = new Map(); // ID → 註解裡出現過的名字；兩個檔名字不同的 ID（永恆改用過的）不用
for (const f of ["subZoneToParentZone.lua", "areaIdToUiMapId.lua"]) {
  for (const m of readFileSync(ZONES + f, "utf8").matchAll(/\[(\d+)\]\s*=\s*\d+,\s*--\s*(.+?)\s*->\s*(.+?)\s*$/gm)) {
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
  for (const line of readFileSync(join(ROOT, "tools", `route-text-${loc}.md`), "utf8").split(/\r?\n/)) {
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
  const locIds = (v, enRaw) => {
    const hit = new Set();
    if (enRaw) enIds(enRaw, hit);
    return v
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
    return v && locIds(v, TX_AT.get(where + "|" + k) ?? TX.get(k));
  };
  const T = (where, zhText) => {
    const k = txKey(zhText);
    if (!k) return undefined;
    if (!CJK.test(k.replace(/／/g, "/"))) return N(k.replace(/／/g, "/")); // 原文本來就是英文（目標怪名、物品名）
    c.text++;
    const v = TL(where, zhText);
    if (v) { c.textLoc++; return v; }
    const e = tx(where, zhText);
    if (e) c.textEn++;
    return e;
  };
  const clean = (t) => t.replace(/\$[Gg]\s*([^:;]*):[^;]*;/g, "$1").replace(/\$[Bb]/g, " ").replace(/\$[NnCcRr]/g, "").replace(/\s+/g, " ").trim();
  const genL = (q) => {
    const mk = q?.en?.mk;
    if (!mk) return undefined;
    const parts = [mk.kill.length && F.kill + [...new Set(mk.kill)].map(N).join(F.sep), mk.drop.length && F.loot + [...new Set(mk.drop)].slice(0, 3).map(N).join(F.sep), mk.objsEn.length && F.use + mk.objsEn.map(N).join(F.sep)].filter(Boolean);
    return parts.length ? parts.join(F.sent) : undefined;
  };
  const qd = (id) => {
    c.qd++;
    const d = db.l10nObj(id, loc).map(clean).filter(Boolean).join("\n");
    if (d) { c.qdLoc++; return d; }
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
      return a ? { nodeA: `{a:${a[0].id}}` } : { node: en };
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
  writeFileSync(join(dirname(OUT), `Route_${loc}.lua`), routeL);
  locCov.push([loc, c]);
}
for (const [loc, c] of locCov) {
  console.log(`${loc}：名稱 ${c.namesLoc}/${c.names}（英文 ${c.namesEn.size} 種）、說明文字 ${c.textLoc}/${c.text}（用英文 ${c.textEn}）、任務名 ${c.qnLoc}/${c.qn}、任務目標文字 ${c.qdLoc}/${c.qd}、標籤用英文 ${c.tagsEn}/${c.tags}、站名缺 ${(c.stMiss || []).join("、") || 0}／地點缺 ${c.stPartMiss || 0}；翻譯列不用：亂碼 ${c.rejected.garbled}、字型顯示不了 ${c.rejected.script}（另有審稿標記拿掉 ${c.rejected.mark}）`);
  if (process.env.LOC_REPORT) writeFileSync(join(process.env.LOC_REPORT, `names-en-${loc}.txt`), [...c.namesEn].sort().join("\n"));
}
const report = `# 建置報告（資料版本 ${version}）\n\n來源：${files.join("、")}\n站數：${stations.length}　任務數：${quests.size}\n\n## 需要處理（${issues.hard.length}）\n\n${issues.hard.join("\n") || "無"}\n\n## 提醒（${issues.warn.length}）\n\n${issues.warn.join("\n") || "無"}\n\n## 副本前置鏈\n\n${chainReport.join("\n") || "無"}\n\n## 裸任務 ID 換成任務名（前 40 例）\n\n${idSamples.map((x) => "- " + x).join("\n") || "無"}\n\n## 名稱不一致（${nameIssues.length}）\n\n${nameIssues.join("\n") || "無"}\n\n## 順序錯誤（已自動調整 ${orderFixes.length}）\n\n${orderFixes.join("\n") || "無"}\n\n## 學技能站（候選站依序，遊戲取第一個本角色有的）\n\n${trainers.map((t) => `- ${t.c} ${t.lv} ${t.npc}（${t.place}）→ ${t.st.slice(0, 4).map((id) => id + " " + stations.find((x) => x.id === id).name).join("、")}`).join("\n") || "無"}\n`;
writeFileSync(REPORT, report);
console.log(`順序錯誤已調整 ${orderFixes.length}`);
console.log(`路線外判定 ${offroute.size}、路線外前置 ${feeds.size}、訓練師 ${trainers.length}、保留物品 ${keep.size}、補給 ${stations.reduce((n, x) => n + (x.supply?.length || 0), 0)}、危險 ${stations.reduce((n, x) => n + (x.danger?.length || 0), 0)}`);
console.log(`站 ${stations.length}、任務 ${quests.size}、需要處理 ${issues.hard.length}、提醒 ${issues.warn.length}、名稱不一致 ${nameIssues.length}`);
console.log("裸任務 ID 換成任務名：" + ([...idStats.entries()].map(([k, v]) => k + " " + v).join("、") || "0"));
console.log(`→ ${OUT}\n→ ${REPORT}`);
process.exitCode = issues.hard.length ? 1 : 0;
