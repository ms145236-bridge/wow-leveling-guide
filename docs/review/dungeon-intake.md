# 永恆版副本任務接取追蹤

[逐筆工作表（TSV，134 筆）](dungeon-intake.tsv) 以「陣營、任務 ID」為一列。它涵蓋副本區域索引列出、但在候選路線中仍沒有明確「接」步驟的任務。角色能否接取仍取決於種族、陣營、職業、等級、物品、前置及遊戲模式。兩翼共用的 ID 在各自陣營只計一次。

## 版本與計數

| 固定比對點 | 聯盟缺接取／索引 | 部落缺接取／索引 | 相對前一列的改變 |
|---|---:|---:|---|
| 正式 1.13.15，8f601b6 | 55／137 | 82／234 | 巨集版沿用 1.13.14 路線 |
| 1.13.16 路線候選，8ea0dab | 53／137 | 82／234 | 聯盟濕地 95772、95795 加入接取 |
| 推演至 1.13.17，以上列加聯盟 5251 | 52／137 | 82／234 | 斯坦索姆 5251 排入禮拜堂接取 |

正式版與 1.13.16 候選可在固定提交執行 `lua5.1 tools/audit-dungeon-coverage.lua Alliance` 和 `lua5.1 tools/audit-dungeon-coverage.lua Horde` 核對。1.13.17 列是對候選內容的推演，本表固定於這組 ID。1050、5848 原已有接取步驟。部落 7938、92065、92066 為日誌條件提示，所屬兩個副本站缺區域索引，所以分母與缺接取數維持原值。[正式 1.13.15](https://github.com/ms145236-bridge/wow-leveling-guide/tree/8f601b6d85bc4323c2c88e20b94b1d3b5f65cafe) · [1.13.16 路線候選](https://github.com/ms145236-bridge/wow-leveling-guide/tree/8ea0daba62b6286a485d74b10fca942d2861d368) · [QuestieDB Forever v1.1.2](https://github.com/Questie/QuestieDB/releases/tag/v1.1.2)

## 如何使用工作表

| 處置 | 聯盟 | 部落 | 審核目標 |
|---|---:|---:|---|
| 可桌面查證 | 31 | 43 | 先比對任務原文、起訖點、日誌、實物與既有行程，再決定哪些角色的路線要改。 |
| 宜保留路線外 | 20 | 35 | 預設單人升級不安排專業、後期裝備、指定團隊事件或可重複交換。有相應材料、階段或隊伍的玩家仍可選做。 |
| 須玩家證明可接 | 1 | 4 | 現有資料無法確定永恆版的取得途徑、陣營或遊戲模式。先記下可重現的接取條件。 |

最後一類的聯盟 78916、部落 78917 和 80325 缺可核實的永恆版起始來源或模式。部落 1198 的起點在達納蘇斯，須核對部落玩家實際接取。部落 1318 與 7703 同名同目標，只有 7703 查到起訖 NPC。請以永恆版角色的陣營、等級、模式、實際接取 NPC／物品與日誌 ID 回報。 [聯盟 78916](https://www.wowhead.com/forever/quest=78916) · [部落 78917](https://www.wowhead.com/forever/quest=78917) · [80325](https://www.wowhead.com/forever/quest=80325) · [1198](https://www.wowhead.com/forever/quest=1198) · [1318](https://www.wowhead.com/forever/quest=1318)

## 下一批聯盟優先目標

1. **濕地 95810、98824**。聖物守護者掉落的泰坦聖物 270865 可以開啟 95810。第 23 站本來就向勘察員維爾加接交 299。研究持有聖物時合交、再接 98824，於原有鐵爐堡行程向麥格拉斯交付。驗證空袋、只有舊聖物、已交前置與尚未回城的狀態。 [任務起始物品](https://nether.wowhead.com/forever/tooltip/item/270865?locale=10) · [98824](https://nether.wowhead.com/forever/tooltip/quest/98824?locale=10)
2. **斯坦索姆 5243、5214、5212**。三項最低 55 級都在聖光之願禮拜堂接交。聖水 13180 需五瓶，煙草 13172 需一盒，肉塊 13174 需二十個。三種物品各自一疊就夠。先查隊伍走正門或側門，沿路見到木箱或相關敵人才採集，交件時按現存數量決定。永恆繁中 5214 為「偉大的艾茲拉‧格里姆」，部分舊庫仍稱「弗拉斯·希亞比」。 [5243](https://nether.wowhead.com/forever/tooltip/quest/5243?locale=10) · [5214](https://nether.wowhead.com/forever/tooltip/quest/5214?locale=10) · [5212](https://nether.wowhead.com/forever/tooltip/quest/5212?locale=10)

後續處置可在對應版本記錄陣營、任務 ID、覆蓋的接／做／交步驟和遊戲實測缺口，保留這份表作為比較起點。
