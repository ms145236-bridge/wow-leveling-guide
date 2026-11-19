// QuestieDB 變動報告：比對 Data 建置時的快照（tools/questiedb-snapshot.tsv）和本機 QuestieDB，列出路線任務的
// 最低等級、等級、種族、職業、前置、互斥、起點、目標與目標文字變動。只讀，不改檔；需要本機 QuestieDB（CI 不跑）。
// 用法：node tools/questiedb-drift.mjs（更新 QuestieDB 後、重建 Data 前先看；建置時版本不同也會印同一份清單）
import { readFileSync } from "node:fs";
import { join, dirname } from "node:path";
import { fileURLToPath } from "node:url";
import { openQuestieDB, localVersion, readSnapshot, diffSnapshot } from "./questiedb.mjs";

const TOOLS = dirname(fileURLToPath(import.meta.url));
const before = readSnapshot(readFileSync(join(TOOLS, "questiedb-snapshot.tsv"), "utf8"));
const db = openQuestieDB();
const after = new Map([...before.keys()].map((k) => {
  const [side, id] = k.split("\t");
  const row = db.snapshot(+id);
  return [k, row ? `${side}\t${row}` : `${side}\t${id}\t（QuestieDB 已沒有這個任務）`];
}));
const local = localVersion();
for (const line of readFileSync(join(TOOLS, "questiedb-version.txt"), "utf8").split(/\r?\n/).filter((l) => l && !l.startsWith("#"))) {
  const [side, pinned] = line.split("\t");
  console.log(`${side}：Data 用 ${pinned}，本機 ${local}${pinned === local ? "（相同）" : "（不同）"}`);
}
const changes = diffSnapshot(before, after);
console.log(`路線任務欄位變動 ${changes.length} 筆${changes.length ? "：\n" + changes.join("\n") : ""}`);
