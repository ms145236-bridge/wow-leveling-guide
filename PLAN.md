# 部落 1–60 地鐵圖升級路線插件 — 設計計畫

暫名 `MetroGuide`（顯示名「地鐵升級」）。目標客戶端：魔獸世界：永恆 zhTW 1.60.1，`## Interface: 16001`。
本文件只有規劃，尚未寫插件程式。互動示意見同資料夾 `demo.html`（範例資料）。

---

## 1. RXP 的痛點 → 我們的做法

| 痛點（RXP 實際原因） | 我們的做法 |
|---|---|
| 字太多又太淺：每步是多行彩色句子（`>>Talk to …`、`.accept 840 >>Accept …`） | 一步 = 動詞圖示 + 任務名 + 目標/進度，最多 3 行；影片提示只在有內容時出現第 3 行 |
| 卡住／交完不前進：進度是「存下來的 `currentStep` 索引 + 各 element 的 `completed` 旗標」，由事件逐一改寫（`UpdateStepCompletion`、`stepSkip`）；漏接一個事件就永久錯位 | 進度**不存**。每步「完成與否」是遊戲狀態的純函式（已完成任務、任務日誌、等級、位置）；任何事件只觸發「整站重算」。漏事件下一次重算就自己修好 |
| 亂跳步：`completewith next`、sticky、`requires` 等隱性規則互相牽動 | 只有一條規則決定目前步驟（§4 `locate`）；沒有 sticky／completewith |
| 偏離路線無法彈性改道：單一線性清單，只能手動拖回 | 以「站」為單位：每站獨立重算、可從地鐵圖任意切站；超等時一鍵跳到合適的站；漏掉的列成清單，不強迫回頭 |
| 介面雜、視窗大、設定多（`SettingsPanel.lua` 4589 行、146 個選項） | 預設只有一條目前步驟；點一下才展開清單／地鐵圖；設定 ≤ 4 項 |
| 箭頭自成一套 | 不做自己的箭頭，交給 WaypointUI／原生航點（§6） |

**借用 RXP 的**：以任務 ID 為準、事件驅動刷新、`<< 種族/職業` 條件過濾、每步帶座標。
**不借的**：文字 DSL 在遊戲內解析（我們離線產生 Lua 表）、自動接交任務、物品/天賦/拍賣等周邊模組、隊伍同步。

---

## 2. 架構

### 檔案
```
MetroGuide/
  MetroGuide.toc        Interface 16001；SavedVariablesPerCharacter: MetroGuideCharDB；OptionalDeps: WaypointUI
  Compat.lua            薄相容層（任務日誌、地圖、航點），只有這裡碰版本差異
  Data/Route.lua        離線工具產生：站、步驟、地鐵圖座標（勿手改）
  Engine.lua            條件過濾、done 判定、locate、站狀態、超等建議
  Nav.lua               航點（WaypointUI → 原生 → 無）、世界地圖/小地圖圖釘
  UI/Bar.lua            目前步驟列
  UI/Panel.lua          展開：步驟清單 + 地鐵圖
  UI/QuestTip.lua       任務日誌滑過提示、接任務前的判定
  Data/QuestIndex.lua   離線產生：部落可接的全部任務精簡索引（路線外任務判定用）
  Core.lua              事件、節流刷新、slash、存檔
tools/                  離線建置（不進插件資料夾）
  build.mjs             Grokbot 文字 → Data/Route.lua + unresolved.md
  questiedb.mjs         讀 QuestieDB_Forever.toc
route/*.txt             Grokbot 交付的每站文字；route/overrides.json 人工指定 ID
```

### 資料流
```
事件 ─► Core（0.1 秒合併）─► Engine.refresh()
                               ├ 讀 Compat 快照：已完成任務集合、日誌任務與目標、等級、種族/職業、地圖/座標、爐石點
                               ├ 對目前站每一步算 done → locate() 得到目前步驟、漏掉清單
                               └ 算各站完成度、超等建議
                             ─► UI（Bar/Panel 只讀結果重畫）─► Nav（目標變了才換航點/圖釘）
```
- 單向：UI 不改引擎狀態，只送出意圖（上一步/下一步/略過/切站/重新對齊）。
- 已完成任務集合：登入時取一次全量，之後靠 `QUEST_TURNED_IN` 增量；不每次全掃。

### 事件（全部 `pcall(RegisterEvent)`）
| 事件 | 用途 |
|---|---|
| `PLAYER_ENTERING_WORLD` | 取已完成任務全量、首次 locate |
| `QUEST_ACCEPTED` / `QUEST_REMOVED` / `QUEST_TURNED_IN` | 接、放棄、交 |
| `QUEST_LOG_UPDATE`、`UNIT_QUEST_LOG_CHANGED` | 擊殺/收集進度 |
| `PLAYER_LEVEL_UP` | 等級步驟、落後/超等判斷 |
| `ZONE_CHANGED_NEW_AREA`、`PLAYER_CONTROL_GAINED` | 換區、下鳥點 |
| `HEARTHSTONE_BOUND`、`TAXIMAP_OPENED` | 爐石綁定、開鳥點 |
| 0.5 秒 ticker（僅目前步驟是「到達」型時啟動） | 到達判定 |

### 存檔（每角色 `MetroGuideCharDB`）
```lua
{ station = "barrens-1",              -- 目前站（手動或建議跳站後寫入）
  pin = { ["barrens-1"] = "a:870" },  -- 手動上一步/下一步釘住的步驟 key；該步完成或按「重新對齊」即清除
  skip = { ["d:844"] = true },        -- 手動略過的步驟 key
  latch = { ["barrens-1#7"] = true }, -- 無法從遊戲狀態回推的步驟（到達、開鳥點）完成後記一筆
  drop = { ["durotar-2"] = true },    -- 已選擇放掉的站
  pos = {x,y}, scale = 1, locked = false, arrow = true }
```
只存「遊戲狀態查不到的東西」。任務類步驟永遠即時推導。

### 相容層（比照 ProfLevel/Core.lua 的作法：存在才用、`pcall` 包住、錯誤只報一次）
```lua
Compat.IsOnQuest(id)        -- C_QuestLog.IsOnQuest → GetQuestLogIndexByID(id) > 0
Compat.IsTurnedIn(id)       -- C_QuestLog.IsQuestFlaggedCompleted → IsQuestFlaggedCompleted
Compat.AllTurnedIn()        -- C_QuestLog.GetAllCompletedQuestIDs → GetQuestsCompleted
Compat.IsReady(id)          -- C_QuestLog.IsComplete → GetQuestLogTitle 的 isComplete
Compat.Objectives(id)       -- C_QuestLog.GetQuestObjectives → GetQuestLogLeaderBoard；回 {text, have, need, done}
Compat.Title(id)            -- C_QuestLog.GetTitleForQuestID → 資料內建的 zhTW 名
Compat.Position()           -- C_Map.GetBestMapForUnit + GetPlayerMapPosition
Compat.SetWaypoint(map,x,y,name) / ClearWaypoint()
```
啟動時挑一次實作並存成函式，內層不再判斷。Questie 的 `QuestieCompat.lua` 在本客戶端也是這種雙路徑寫法，可對照。

---

## 3. 路線資料格式

### Lua 結構（`Data/Route.lua`）
```lua
MetroGuide_Route = {
  lines = { orc = {name="獸人/食人妖", color={.86,.36,.25}}, main = {name="主線", color={.85,.70,.37}} },
  stations = {
    { id="durotar-1", name="試煉谷", zone="杜洛塔", map=1411, lv={1,6}, line="orc",
      at={2,1},                          -- 地鐵圖格子座標
      next={"durotar-2"},
      when={race={"Orc","Troll"}},       -- 站層條件；不符者整站不存在
      steps = {
        { t="accept", q=788,  npc="高內克", map=1411, x=42.1, y=68.4 },
        { t="do",     q=788,  hint="雜斑野豬" },             -- 進度從任務日誌讀，不寫死數量
        { t="turnin", q=788,  npc="高內克", map=1411, x=42.1, y=68.4 },
        { t="accept", q=790,  npc="…", when={class={"WARRIOR"}} },   -- 職業任務：條件步驟，自動插入/略過
        { t="hearth", bind="剃刀嶺" },                        -- 綁爐石
        { t="fp",     node="十字路口", map=1413, x=51.5, y=30.3 },
        { t="fly",    to="奧格瑪" },    { t="boat", to="幽暗城", from="奧格瑪飛艇塔" },
        { t="goto",   map=1413, x=52.0, y=31.0, r=30, text="往十字路口" },
        { t="level",  lv=6 },                                -- 練到 6 級才往下
        { t="note",   text="箱子在帳篷後面" },                -- 影片提示，附著在下一步顯示
      } },
  },
}
```
- 步驟 key：任務類 `a:788`／`d:788`／`t:788`（跨站唯一、資料改版不失效）；其他 `站id#序號`。
- 每個任務附離線算好的欄位（寫在 `quests[id]`）：`lvl`、`minLvl`、`pre`（前置）、`chain`（是否接到後面站的任務）、`keep`（Grokbot 標 ★ 的好獎勵）、`race/class` 遮罩。
- `when` 只有 `race`、`class`、`lvMin` 三種，站與步驟共用。種族含永恆專屬的**天裔**（澤風島 1–12 → 飛艇到莫高雷）；種族代碼以 `UnitRace` 第二回傳值為準（§7）。
- **二選一站**（30–60 常見，如 希爾斯布萊德丘陵／阿拉希高地）：`alts = { {zone=…, map=…, steps={…}}, {…} }` 取代 `steps`。同一等級帶只算一站；玩家所在地圖決定用哪一個（不在任一區時用第一個），存 `alt[站id]`；任一個做完即整站完成。地鐵圖畫成並排雙圓點。
- 支線（如 梣谷 27–30 的千針石林）：一般站加 `side=true`，可整站略過。
- 站名、區域名顯示用 `C_Map.GetMapInfo(map).name`（客戶端 zhTW 用語，例：杜洛塔、提里斯法林地、奧格瑪、梣谷、石爪山脈）；資料裡的中文名只當備援。
- `Data/QuestIndex.lua`：`[questId] = { lvl, feeds }`，涵蓋部落可接的 1–60 任務（約兩千筆，每筆兩個數字）。`feeds` = 它是哪個路線任務的前置。路線外任務靠它判定，執行期不依賴 Questie。
- Grokbot 可在行尾加短理由標記：`★獎勵好`、`✕太遠`、`✕效率差`；沒標的由規則推導（§5.4）。

> **PM 更正（11/12）**：路線資料實際由 Codex 依「第N站｜區域（等級）｜影片 mm:ss」Markdown 格式產出，存在 `route/0N-*.md`（步驟行 `接｜任務名（英文名）｜任務ID｜NPC｜座標`，行尾【影片】/【補充】/【僅X】，另有「交通／取捨／提醒」小節）。build 工具以該格式為主要輸入；下面的精簡約定保留給手寫補丁用。

### Grokbot 文字約定（手寫補丁用）
```
# 站｜試煉谷｜杜洛塔｜1-6｜獸人,食人妖｜下一站：森金村
接｜削減野豬數量｜高內克｜42.1,68.4
做｜削減野豬數量｜雜斑野豬
交｜削減野豬數量｜高內克            ← 行尾加 ★ = 獎勵好/值得補
爐｜剃刀嶺    鳥｜十字路口    飛｜奧格瑪    船｜幽暗城｜奧格瑪飛艇塔
到｜十字路口｜52,31    練｜6    註｜箱子在帳篷後面
職｜戰士｜接｜…（其餘同上）
```
簡體或繁體皆可（工具兩種名稱都比對）。

### 離線工具
- **語言**：Node（本機已有；單檔 ESM，零依賴，`zlib` 內建）。
- **QuestieDB 讀法（已看過原始碼確認）**：本客戶端的 QuestieDB 是「baked」模式，資料全部在 `QuestieDB_Forever.toc`（17 MB）的 metadata：
  - `## X-Quest-<id>-S`＝純量列、`## X-Quest-<id>-<欄位序號>`＝表格欄位；值是 Base64 → CBOR（`src/read/baked.lua`）。`Npc`／`Object`／`Item` 同理。
  - 欄位序號見 `src/meta/questMeta.lua`：1 name、2 startedBy、3 finishedBy、4 requiredLevel、5 questLevel、6 requiredRaces、7 requiredClasses、10 objectives、12/13 前置、16 exclusiveTo、17 zoneOrSort、22 nextQuestInChain。NPC：1 name、7 spawns、9 zoneID。
  - 中文名在 `X-l10n-zhTW-Quest…`／`X-l10n-zhCN-Quest…`（zlib + CBOR 的欄區塊，`src/l10n/overlay.lua`）。
  - 區域 ID → uiMapID：`support/Forever/Zones/areaIdToUiMapId.lua`。
  - 純量列的精確編碼（`src/meta/codec.lua`、`src/read/shared.lua`）實作時照原始碼移植；**備案**：寫一個 30 行的遊戲內匯出器，用 QuestieDB 的全域 `QuestDB`/`NpcDB` 把需要的任務倒進 SavedVariables 再讀。
- **比對流程**：任務名（簡→繁兩表都查）→ 候選 ID → 依序用「部落可接、站所在區域、等級落在站範圍 ±5、NPC 名相符、同站前後任務的鏈關係」篩到唯一；`overrides.json` 可強制指定。
- **永恆專屬內容**（天裔／澤風島、河林、洛格瑪、爆破引線港）：QuestieDB 可能沒有或不全（Questie 內只找到零星「天裔」「河林」字樣）。工具把這類列為獨立一節「QuestieDB 無資料」；補法是插件內的開發指令 `/metro rec`：實際接/交任務時把任務 ID、NPC、地圖與座標記到 SavedVariables，再匯回 `overrides.json`。
- **座標**：文字有就用；沒有就取 startedBy/finishedBy NPC（或物件）的 spawns，多點取最密集一群的中心。
- **輸出**：`Data/Route.lua` + `Data/QuestIndex.lua` + `unresolved.md`（找不到、仍有多個候選〈列出候選 ID 與區域〉、缺座標、種族/職業遮罩與站條件矛盾、鏈順序顛倒）。報告非空時建置以非零碼結束。

---

## 4. 完成判定與重新對齊

### 4.1 每步 done（純函式）
| 類型 | done 條件 |
|---|---|
| `accept q` | `IsOnQuest(q)` 或 `IsTurnedIn(q)` |
| `do q` | `IsTurnedIn(q)` 或（`IsOnQuest(q)` 且 `IsReady(q)`）；有指定目標序號時只看該目標 |
| `turnin q` | `IsTurnedIn(q)` 或本次登入收到過 `QUEST_TURNED_IN(q)`（旗標比事件晚更新時不卡） |
| `level n` | `UnitLevel ≥ n` |
| `hearth` | `GetBindLocation() == bind` |
| `fp`／`goto`／`fly`／`boat` | `latch` 已記；或距離 ≤ r／已在目的地圖；或**同站後面任一任務步驟已 done**（軟步驟永不擋路） |
| `note` | 不是步驟，跟著下一步顯示 |

另有「不適用」：`when` 不符、任務被 `exclusiveTo` 的另一個任務佔掉、手動略過 → 視同 done 且不顯示。

### 4.2 `locate(站)` — 唯一決定目前步驟的規則
1. 有 `pin`（手動上一步/下一步）且該步未 done → 就是它。
2. 否則由前往後找未 done 的步驟 i：若 i 之後 8 個（不屬於同一任務的）任務步驟中**過半已 done**，代表玩家已走過這裡 → i 列入「漏掉」，繼續往後；否則 i 就是目前步驟。
3. 全部 done → 本站完成，目前步驟變成「前往下一站」。

結果完全由當下遊戲狀態 + `pin/skip/latch` 算出，沒有會壞掉的索引。

### 4.3 漏掉清單
- 以任務為單位合併（接/做/交算一列），只列**還能做**的：未交、前置已滿足或前置也在清單內、等級夠、非灰色。
- 點一列 = `pin` 到那步；不點就不管它，不影響前進。

### 4.4 以站為單位
- 每站各自算：`完成數/總數`、狀態（未到／進行中／完成／已放掉）。重算只算**目前站**的步驟 + 各站的任務完成數（查集合，很便宜）。
- **切站**：地鐵圖點任一站 → `station = 該站` → `locate`。不需確認，點回去即還原。
- **自動到下一站**：目前站完成且玩家進入下一站的地圖時切換；有多個 `next`（分歧）時依種族/職業條件取唯一，仍有多個則在目前步驟列出讓玩家點。
- **超等建議**：`等級 > 目前站 lv.max` 時，找路線上第一個 `lv.min ≤ 等級 ≤ lv.max` 且未完成的站，在步驟列下方出現一顆「→ 站名 等級」；點了才跳，不點照舊。每升一級最多重新出現一次。
- **跳站時被略過的站**（目前站到目標站之間未完成者），其未交任務分兩類：
  - **順路補**：`chain`（後面站的任務以它為前置）、`keep`（★）、或已在任務日誌且已有進度/可交。
  - **可放掉**：其餘（含已灰、獎勵普通、獨立支線）。
  - 「順路補」的任務成為一個虛擬小段，排在新站最前面（可整段略過）；「可放掉」只在跳站面板顯示一次，並把那些站記為 `drop`（地鐵圖上淡化，點它仍可回去做）。

### 4.5 邊界情況
- **放棄任務**：`QUEST_REMOVED` 後 `accept` 自然變回未 done；若它在目前步驟之前且後面過半已做 → 進漏掉清單，否則回到那步。
- **裝插件前就做過**：登入全量已完成集合 → 那些步驟直接 done，`locate` 落在第一個真正沒做的地方。
- **提前交了後面的任務**：該步 done，游標不動；走到時自動跳過。
- **任務日誌滿**（20/25）：`accept` 步驟第 3 行提示該放掉哪個（優先「可放掉」類）。
- **同名/種族版本任務**：資料層已用遮罩分開，執行期只看 ID。
- **等級落後**：`等級 < 目前步驟任務 minLvl` → 擋住並顯示「差 n 級」；`等級 < 站 lv.min` 只在第 3 行以琥珀色提醒，不擋。
- **資料還沒回來**（剛登入任務日誌為空）：`PLAYER_ENTERING_WORLD` 後等第一個 `QUEST_LOG_UPDATE` 才 locate；之前顯示上次的步驟。
- **戰鬥中**：照常重算；框架未用受保護元件，不需延後。

---

## 5. 介面規格

共通：深色為主。底 `#0E0F12` 85% 不透明、1px 邊 `#2A2D34`、主字 `#E8E4D8`、次字 `#8B8F98`、金 `#D9B25F`（目前）、琥珀 `#E0913A`（提醒/漏掉）、綠 `#6FBF73`（完成）。左側 3px 色條 = 所在地鐵線顏色。無標題列、無關閉鈕（`/metro` 開關）。

### 5.1 目前步驟列（預設唯一可見）
```
┌──────────────────────────────────────────┐
▌ 做  削減野豬數量                     6   │   ← 動詞 + 任務名；右側小字 = 建議等級
▌     雜斑野豬 6/10                        │   ← 目標進度（多目標時並排，最多 2 個，其餘 +n）
▌     ↗ 交完綁爐石：剃刀嶺                 │   ← 只有在有交通提示/影片提示/落後提醒時才有這行
└──────────────────────────────────────────┘
  [ → 十字路口 12–16 ]                         ← 超等時才出現的建議
```
- 寬 300、高 44–76（依行數）；可拖曳、可鎖定。
- 狀態：一般／可交（任務名轉綠、動詞自動變「交」）／落後（第 3 行琥珀「差 2 級」）／本站完成（「前往 森金村」）／無資料（「這個角色沒有路線」）。
- 互動：左鍵展開；滾輪上一步/下一步（= pin）；右鍵選單：略過這步、重新對齊、設定。步驟切換時整列 0.15 秒淡入，完成時打勾一閃。

### 5.2 展開：步驟清單
```
┌──────────────────────────────────────────┐
│ 步驟   地鐵圖                 試煉谷 1–6  │   ← 兩個分頁；右側是站名（點它也切到地鐵圖）
├──────────────────────────────────────────┤
│ ● 漏掉 2                                  │   ← 有才出現；點開
│     痛苦的蠍子                            │
│     薩科斯的信                            │
│ ✓ 接  削減野豬數量                        │   ← 完成：變暗
│ ▌做  削減野豬數量        野豬 6/10        │   ← 目前：金色條 + 亮字
│   交  削減野豬數量                        │   ← 未到：正常
│   接  邪靈劣魔                            │
│   爐  剃刀嶺                              │
│ ─ 接  戰士的試煉（已略過）                │   ← 略過：刪除線
└──────────────────────────────────────────┘
```
- 寬 320、高最多 420，清單捲動，開啟時自動捲到目前步驟。
- 點任一列 = 跳到那步（pin）；右鍵 = 略過/取消略過。再點目前步驟列收合。

### 5.3 展開：地鐵圖
```
 ○ ○ ○ ●  試煉谷                 1–6      ← 左側淡色三條 = 其他種族（天裔/牛頭人/不死族）
 ○ ○ ○ ◉  剃刀嶺               ▸ 6–12     ← ◉ 目前站（圓環 = 完成比例）；▸ = 你的等級落點
  ╲ ╲ ╲┃
       ○  十字路口  貧瘠之地    12–16
       ○  瑟伯切爾  銀松森林    16–20
       ○  貧瘠之地              20–23
       ⋮
      ○○  希爾斯布萊德／阿拉希  30–33     ← 二選一站
       ┊ 60
```
- 直式（窄面板放得下），可上下捲動；四條起始線依種族只亮自己那條，其餘淡化、不標字。
- 每站：圓點 + 站名 + 等級範圍；綠色實心 = 完成、虛線圈 = 已放掉。
- 點站 = 切到該站並回到步驟分頁；滑過顯示「完成數/總數」。
- 超等時，符合等級的站外圈閃一次金色；下方面板：
```
 跳到 十字路口 12–16
 順路補  薩科斯的信 ★   部落的新兵 ↦
 可放掉  5 個任務
 [跳過去]   [留在這]
```

### 5.4 任務日誌提示（按 L 滑過任務）
```
 薩科斯的信
 路線：十字路口・第 12 步
 值得做・接後續任務
```
- 只加 1–2 行，接在原提示下方；原本沒有提示框的列，由我們自己開一個小提示。
- 第 1 行：`路線：<站名>・第 n 步`／`不在路線上`。
- 第 2 行：判定 + 一個短理由（顏色：值得做綠、之後順路金、可放掉灰）。規則由上而下取第一個符合的：

| 情況 | 顯示 |
|---|---|
| 在目前站 | 值得做・路線內（有 ★ 則「獎勵好」） |
| 在後面的站 | 之後順路・到〈站名〉再做 |
| 在已過/已放掉的站，且 `chain` | 值得做・接後續任務 |
| 在已過/已放掉的站，且 `keep` | 值得做・獎勵好 |
| 在已過/已放掉的站，其餘 | 可放掉・等級已過 |
| 路線外，`feeds` 指向未完成的路線任務 | 值得做・接後續任務 |
| 路線外，任務等級已灰 | 可放掉・等級已過 |
| 路線外，Grokbot 標了理由 | 可放掉・太遠／效率差 |
| 路線外，其餘 | 可放掉・不在路線上 |

- **掛載方式**（依 §7 探測結果擇一，三者都不改動原框架）：
  1. 有 `QuestMapLogTitleButton_OnEnter` → `hooksecurefunc` 後 `GameTooltip:AddLine`。
  2. 經典式 `QuestLogFrame`（`QuestLogTitle1…n` 或捲動框的列）→ 每列 `HookScript("OnEnter"/"OnLeave")`，以 `GetQuestLogTitle`/`C_QuestLog.GetInfo` 取 ID。
  3. `TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Quest, …)` 作為任務連結提示的補充。
  - 本機另裝了 EllesmereUIQuestTracker 與 DialogueUI，會換掉追蹤列與任務對話框 → 以 `/fstack` 實看的框架名為準。
- **接任務前**（加分項）：`QUEST_DETAIL` 時用 `GetQuestID()` 算同一個判定，暫時顯示在我們自己的步驟列第 3 行（不碰任務對話框，所以不受 DialogueUI 影響）。

### 5.5 設定（僅此 4 項，在右鍵選單內直接勾）
鎖定位置｜縮放（三段）｜箭頭開關｜地圖圖釘開關。

---

## 6. 箭頭與圖釘（已讀 WaypointUI 1.7.5 原始碼確認）

- WaypointUI 有公開 API（`WaypointUI/API.lua`）：
  `WaypointUIAPI.Navigation.NewUserNavigation{ name, mapID, x, y, flags, iconTexture, requestRecolor, suppressAudio }`
  - `x`/`y` 是 **0–100**（它內建的 RestedXP 整合 `Code/SupportedAddons/RestedXP.lua` 就是這樣傳）。
  - 內部會呼叫 `C_Map.SetUserWaypoint` + `C_SuperTrack.SetSuperTrackedUserWaypoint(true)`（`MapPin.lua:778`）。
  - `flags` 是自訂字串標記；用 `IsUserNavigationFlagged("MetroGuide")` 判斷目前航點是不是我們的，`ClearUserNavigation()` 清除。
- 它也監聽 `USER_WAYPOINT_UPDATED`／`SUPER_TRACKING_CHANGED`；設定「AutoTrackPlacedPin」開啟時，原生航點一放就自動追蹤（`Map/AutoTrackPlacedPin.lua`）。
- **我們的順序**：有 `WaypointUIAPI` → 用它（名稱帶入步驟文字、`suppressAudio=true`）；沒有 → 原生 `C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(map, x/100, y/100))` + `SetSuperTrackedUserWaypoint(true)`；都不行 → 不顯示箭頭，只留圖釘。
- **不搶玩家自己的航點**：只有「目前沒在追蹤任何東西」或「目前航點是我們的」才覆蓋（RXP 整合也是這個條件）；玩家手動放了別的點，我們就等它清掉。
- 換航點的時機：只有目前步驟的目標座標變了才換（不在每次重算時重放，避免音效與閃爍）。
- `NewPin`（多圖釘）要玩家在 WaypointUI 開啟自訂圖釘才有效 → **不依賴**。世界地圖圖釘自己做：`WorldMapFrame` 的 data provider + pin pool；顯示目前步驟（金）、接下來 3 步（小灰點）、漏掉（琥珀）。
- 小地圖圖釘：內嵌 HereBeDragons-Pins（Questie 在本客戶端也用它）；只釘目前步驟。

---

## 7. 實作前要在遊戲內確認（請照貼，回報輸出）

任務 API（挑一個日誌裡的任務 ID 代入 `QID`、一個已交的代入 `DONE`）：
```
/dump GetLocale(), (select(4, GetBuildInfo()))
/dump C_QuestLog.GetInfo ~= nil, C_QuestLog.GetNumQuestLogEntries ~= nil, GetQuestLogTitle ~= nil, GetNumQuestLogEntries ~= nil
/dump C_QuestLog.GetInfo(2)
/dump C_QuestLog.IsOnQuest(QID), C_QuestLog.IsComplete(QID), C_QuestLog.GetTitleForQuestID(QID)
/dump C_QuestLog.GetQuestObjectives(QID)
/dump C_QuestLog.IsQuestFlaggedCompleted(DONE), IsQuestFlaggedCompleted ~= nil
/dump C_QuestLog.GetAllCompletedQuestIDs ~= nil, GetQuestsCompleted ~= nil
/dump #C_QuestLog.GetAllCompletedQuestIDs()
/dump C_QuestLog.GetQuestDifficultyLevel ~= nil, C_QuestLog.GetTrivialRange ~= nil, C_QuestLog.GetMaxNumQuestsCanAccept ~= nil
```
地圖／航點：
```
/dump C_Map.GetBestMapForUnit("player")
/dump C_Map.GetPlayerMapPosition(C_Map.GetBestMapForUnit("player"), "player"):GetXY()
/dump C_Map.CanSetUserWaypointOnMap(C_Map.GetBestMapForUnit("player")), C_SuperTrack.SetSuperTrackedUserWaypoint ~= nil
/run C_Map.SetUserWaypoint(UiMapPoint.CreateFromCoordinates(C_Map.GetBestMapForUnit("player"),0.5,0.5)) C_SuperTrack.SetSuperTrackedUserWaypoint(true)
/dump WaypointUIAPI ~= nil and WaypointUIAPI.Navigation.NewUserNavigation ~= nil
/run WaypointUIAPI.Navigation.NewUserNavigation({name="測試",mapID=C_Map.GetBestMapForUnit("player"),x=50,y=50,flags="MetroGuide"})
/dump WaypointUIAPI.Navigation.IsUserNavigationFlagged("MetroGuide")
/run WaypointUIAPI.Navigation.ClearUserNavigation()
```
（第 4 行後看：原生航點有沒有出現、WaypointUI 有沒有接手；第 6 行後看世界內標記與名稱。）

角色／交通／函式庫：
```
/dump UnitRace("player"), UnitClass("player"), UnitLevel("player"), GetBindLocation()
/dump type(QuestDB), type(NpcDB), LibStub and LibStub("HereBeDragons-2.0", true) ~= nil, LibStub and LibStub("HereBeDragons-Pins-2.0", true) ~= nil
/dump WorldMapFrame.AddDataProvider ~= nil, C_TaxiMap ~= nil, UnitOnTaxi ~= nil
```
任務日誌框（按 L 開啟後）：
```
/dump QuestLogFrame ~= nil, QuestMapFrame ~= nil, QuestScrollFrame ~= nil
/dump QuestMapLogTitleButton_OnEnter ~= nil, QuestLogTitleButton_OnEnter ~= nil, QuestLogTitle1 ~= nil
/dump TooltipDataProcessor ~= nil, Enum.TooltipDataType and Enum.TooltipDataType.Quest
/dump GetQuestID ~= nil, GetQuestLogIndexByID ~= nil
/fstack
```
（`/fstack` 開著滑過任務日誌的一列，回報最上面 3 個框架名；再對任務 NPC 開接任務視窗滑一次。滑過列時原本有沒有提示框也請說一下。）

事件是否存在（`false` 的要拿掉）：
```
/run local f=CreateFrame("Frame") for _,e in ipairs({"QUEST_ACCEPTED","QUEST_REMOVED","QUEST_TURNED_IN","QUEST_LOG_UPDATE","UNIT_QUEST_LOG_CHANGED","QUEST_DETAIL"}) do print(e,pcall(f.RegisterEvent,f,e)) end
/run local f=CreateFrame("Frame") for _,e in ipairs({"HEARTHSTONE_BOUND","TAXIMAP_OPENED","ZONE_CHANGED_NEW_AREA","USER_WAYPOINT_UPDATED","SUPER_TRACKING_CHANGED"}) do print(e,pcall(f.RegisterEvent,f,e)) end
```
行為（接一個任務、殺一隻、交掉，各做一次並開 `/etrace`，若沒有此指令請告知）：
- `QUEST_ACCEPTED` 的參數是 `(questID)` 還是 `(logIndex, questID)`。
- `QUEST_TURNED_IN` 之後 `IsQuestFlaggedCompleted` 是立即為 true 還是慢一拍。
- 還沒確認：uiMapID 是否沿用經典編號（杜洛塔 1411、貧瘠之地 1413）— 以第一行 `/dump C_Map.GetBestMapForUnit` 在這兩區的輸出為準。

v0.1 會附 `/metro probe`，一次跑完以上檢查並印成一段可複製的報告。

---

## 8. 里程碑

| 版本 | 內容 | 可驗收 |
|---|---|---|
| v0.1 | 骨架、相容層、`/metro probe`、目前步驟列；手寫試煉谷 1–6 一站 | 新獸人角色：接/殺/交時步驟列自動前進，進度數字會跳 |
| v0.2 | 離線工具 + QuestieDB 讀取；四個起始區 1–12（含天裔/澤風島）+ 貧瘠之地 12–16 資料 | `unresolved.md` 產出；各種族看到自己的起點；永恆專屬區的缺漏列在報告 |
| v0.3 | `locate`、漏掉清單、展開步驟清單、手動上一步/下一步/略過 | 中途角色裝上即落在正確步驟；放棄任務後正確回退；故意跳著做不會卡 |
| v0.4 | 航點（WaypointUI → 原生）、世界地圖/小地圖圖釘 | 換步驟時箭頭跟著換；手動放點不被搶 |
| v0.5 | 地鐵圖、切站、超等建議、順路補/可放掉 | 打完副本升 3 級 → 出現建議；一鍵跳站；被略過的站分類正確 |
| v0.6 | 職業任務插入、爐石/鳥點/飛艇步驟、任務日誌滿提示 | 戰士與非戰士看到的步驟不同；綁爐石後該步自動完成 |
| v0.7 | 任務日誌滑過提示（路線位置 + 判定）、接任務前判定 | 日誌內路線內/外/已過站的任務各滑一個，文字與規則表一致 |
| v0.9 | 1–60 全資料、`unresolved.md` 清空 | 抽 5 站實地對照影片 |
| v1.0 | 新角色 1 級起實跑 + 20/40 級中途接手測試、修正 | 一次總驗收（PC） |

---

## 9. 待決定

1. **名稱**：插件資料夾 `MetroGuide`、遊戲內顯示「地鐵升級」，可以嗎？
2. **自動接/交任務**（對話時自動點）要不要做？建議 v1 不做（RXP 式自動化是雜亂感來源之一），之後要再加一個開關。
3. **職業任務範圍**：v1 做部落全部 7 個職業，還是先只做你實際要練的職業？（資料量差很多，Grokbot 也要多交。）
4. **副本**：影片路線若含副本，要當成「站」顯示在地鐵圖上嗎（只標建議等級與入口，不做副本內步驟）？
5. **好獎勵（★）由誰判斷**：以影片有提到的為準（Grokbot 標記），還是另外用「綠裝以上獎勵/聲望」自動補標？建議先以影片為準。
