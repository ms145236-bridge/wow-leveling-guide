# 地鐵升級（MetroGuide）

《魔獸世界：永恆》（WoW Forever，zhTW 1.60.1）部落 1–60 練級路線指示插件。

- 一次顯示目前一步，必要時一起列出附近可順手做的任務
- 依遊戲任務狀態自動推進與對位，可手動勾選或略過（連帶後續）
- WaypointUI 箭頭、世界地圖／小地圖編號標點
- 經驗不足時自動補回可跳過的任務（含打怪經驗估算）
- 職業任務、自選新手村、副本分頁（前置任務、接取路線、副本內任務）
- 「任務目標」巨集：選取任務目標並幫附近任務怪上標記
- 設定頁可調大小、位置、透明度等

## 安裝

1. 下載 [MetroGuide.zip](https://github.com/ms145236-bridge/wow-leveling-guide/releases/latest/download/MetroGuide.zip)（每次更新自動重新打包）
2. 解壓縮，把 `MetroGuide` 資料夾放進 `World of Warcraft\_forever_\Interface\AddOns\`
3. 完整重開遊戲

建議一併安裝 Questie（世界地圖標點）和 WaypointUI（箭頭）；沒裝也能用，只是少了這兩項。

遊戲內指令：`/metro`、`/metro config`、`/metro probe`、`/metro macro`。

## 專案結構

| 路徑 | 內容 |
|---|---|
| `addon/MetroGuide` | 插件本體 |
| `route/*.md` | 路線資料（1–12、12–30、30–45、45–60、副本） |
| `tools/build.mjs` | 把路線資料轉成 `Data/Route.lua`，並用本機 QuestieDB 補任務 ID、座標、名稱 |
| `PLAN.md`、`PIN-SPEC.md`、`TESTING.md` | 設計規劃、標點規格、遊戲內測試說明 |

重建資料：`node tools/build.mjs`（需要本機安裝 Questie／QuestieDB 永恆版）。

## 來源與授權

路線站序參考 Bilibili UP 主「奇怪小鸭」的《魔兽世界无限》練級路線影片，並參考其他公開練級路線優化。任務、NPC、座標資料取自 [Questie](https://github.com/Questie/Questie)／QuestieDB（GPL-3.0），因此本專案以 GPL-3.0 授權。
